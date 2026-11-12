#if os(iOS)
  import AVFAudio
  import Synchronization
  import UIKit

  enum BackgroundSuspension {
    private final class State {
      var running = false
      var paused = false
    }

    private static let suspended = Atomic(false)
    private static let engines = Mutex(NSMapTable<AVAudioEngine, State>.weakToStrongObjects())
    private static let lifecycle = DispatchQueue(label: "game.audio.lifecycle", qos: .userInitiated)

    static var isInBackground: Bool { suspended.load(ordering: .acquiring) }

    static func install() {
      let pauseSelector = #selector(AVAudioEngine.pause)
      var nativePause: ((AVAudioEngine) -> Void)?
      let pauseInstalled =
        ObjectiveCRuntime.replace(AVAudioEngine.self, pauseSelector) { original in
          typealias Function = @convention(c) (AVAudioEngine, Selector) -> Void
          let function = unsafeBitCast(original, to: Function.self)
          nativePause = { function($0, pauseSelector) }
          let block: @convention(block) (AVAudioEngine) -> Void = { engine in
            engines.withLock { $0.removeObject(forKey: engine) }
            function(engine, pauseSelector)
          }
          return block
        }
      guard pauseInstalled, let nativePause else {
        preconditionFailure("AVAudioEngine.pause is unavailable")
      }

      let startSelector = #selector(AVAudioEngine.start)
      var nativeStart: ((AVAudioEngine) -> Bool)?
      let startInstalled =
        ObjectiveCRuntime.replace(AVAudioEngine.self, startSelector) { original in
          typealias Function =
            @convention(c) (
              AVAudioEngine, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?
            ) -> Bool
          let function = unsafeBitCast(original, to: Function.self)
          nativeStart = { engine in
            var error: NSError?
            let result = function(engine, startSelector, &error)
            if !result {
              RuntimeLog.write(
                "foreground: audio engine restart failed: \(error?.description ?? "no NSError returned")"
              )
            }
            return result
          }
          let block:
            @convention(block) (
              AVAudioEngine, AutoreleasingUnsafeMutablePointer<NSError?>?
            ) -> Bool = { engine, error in
              let state = State()
              engines.withLock { $0.setObject(state, forKey: engine) }
              let result = function(engine, startSelector, error)
              if !result {
                RuntimeLog.write(
                  "audio engine start failed: \(error?.pointee?.description ?? "no NSError returned")"
                )
              }
              started(engine, state: state, succeeded: result, pause: nativePause)
              return result
            }
          return block
        }
      guard startInstalled, let nativeStart else {
        preconditionFailure("AVAudioEngine.start is unavailable")
      }

      let stopSelector = #selector(AVAudioEngine.stop)
      let stopInstalled =
        ObjectiveCRuntime.replace(AVAudioEngine.self, stopSelector) { original in
          typealias Function = @convention(c) (AVAudioEngine, Selector) -> Void
          let function = unsafeBitCast(original, to: Function.self)
          let block: @convention(block) (AVAudioEngine) -> Void = { engine in
            engines.withLock { $0.removeObject(forKey: engine) }
            function(engine, stopSelector)
          }
          return block
        }
      guard stopInstalled else { preconditionFailure("AVAudioEngine.stop is unavailable") }

      let center = NotificationCenter.default
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
      ) { _ in
        suspended.store(true, ordering: .releasing)
        lifecycle.async {
          for (engine, state) in candidates(paused: false) {
            pause(engine, state: state, native: nativePause)
          }
        }
      }
      center.addObserver(
        forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
      ) { _ in
        suspended.store(false, ordering: .releasing)
        lifecycle.async {
          for (engine, state) in candidates(paused: true) {
            guard !isInBackground else { break }
            let owned = engines.withLock { table in
              guard table.object(forKey: engine) === state, state.paused else { return false }
              state.paused = false
              return true
            }
            guard owned else { continue }
            let alreadyRunning = engine.isRunning
            guard engines.withLock({ $0.object(forKey: engine) === state }) else { continue }
            let result = alreadyRunning || nativeStart(engine)
            started(engine, state: state, succeeded: result, pause: nativePause)
          }
        }
      }
    }

    private static func candidates(paused: Bool) -> [(AVAudioEngine, State)] {
      engines.withLock { table in
        table.keyEnumerator().allObjects.compactMap { object -> (AVAudioEngine, State)? in
          guard let engine = object as? AVAudioEngine, let state = table.object(forKey: engine),
            paused ? state.paused : state.running
          else { return nil }
          return (engine, state)
        }
      }
    }

    private static func started(
      _ engine: AVAudioEngine, state: State, succeeded: Bool,
      pause nativePause: @escaping (AVAudioEngine) -> Void
    ) {
      let running = succeeded && engine.isRunning
      let accepted = engines.withLock { table in
        guard table.object(forKey: engine) === state else { return false }
        if running {
          state.running = true
          state.paused = false
        } else {
          table.removeObject(forKey: engine)
        }
        return running
      }
      if accepted && isInBackground {
        lifecycle.async { pause(engine, state: state, native: nativePause) }
      }
    }

    private static func pause(
      _ engine: AVAudioEngine, state: State, native: (AVAudioEngine) -> Void
    ) {
      guard isInBackground, engine.isRunning,
        engines.withLock({ $0.object(forKey: engine) === state && state.running })
      else { return }
      native(engine)
      let running = engine.isRunning
      engines.withLock { table in
        guard table.object(forKey: engine) === state else { return }
        state.running = running
        state.paused = !running
      }
      if running { RuntimeLog.write("background: audio engine remained running after pause") }
    }
  }
#endif
