#if os(iOS)
  import AVFAudio
  import Synchronization
  import UIKit

  /// While the app is in the background the game's loop is held in its event poll and its audio
  /// engines are paused; both resume when the app returns to the foreground.
  enum BackgroundSuspension {
    private static let suspended = Atomic(false)
    private static let engines = Mutex(NSHashTable<AVAudioEngine>.weakObjects())

    static var isInBackground: Bool { suspended.load(ordering: .acquiring) }

    static func install() {
      let start = #selector(AVAudioEngine.start)
      ObjectiveCRuntime.replace(AVAudioEngine.self, start) { original in
        typealias Function = @convention(c) (AVAudioEngine, Selector, OpaquePointer?) -> Bool
        let function = unsafeBitCast(original, to: Function.self)
        let block: @convention(block) (AVAudioEngine, OpaquePointer?) -> Bool = { engine, error in
          engines.withLock { $0.add(engine) }
          return function(engine, start, error)
        }
        return block
      }
      let center = NotificationCenter.default
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
      ) { _ in
        suspended.store(true, ordering: .releasing)
        let paused = engines.withLock { $0.allObjects }
        for engine in paused { engine.pause() }
        RuntimeLog.write("background: \(paused.count) audio engine(s) paused")
      }
      center.addObserver(
        forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
      ) { _ in
        guard isInBackground else { return }
        for engine in engines.withLock({ $0.allObjects }) {
          do { try engine.start() } catch {
            RuntimeLog.write("foreground: audio engine restart failed: \(error)")
          }
        }
        suspended.store(false, ordering: .releasing)
      }
    }
  }
#endif
