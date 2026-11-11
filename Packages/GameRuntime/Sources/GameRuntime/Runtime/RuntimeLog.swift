import Darwin
import Foundation
import Synchronization

/// Runtime diagnostics and the game's standard output have separate files in Documents.
enum RuntimeLog {
  private static let output = Mutex<FileHandle?>(prepareOutput())

  static func open() {
    _ = output.withLock { $0 != nil }
  }

  static func write(_ message: String) {
    output.withLock { handle in
      do {
        try handle?.write(contentsOf: line(message))
      } catch {
        report("writing game-runtime.log", error)
      }
    }
  }

  private static func prepareOutput() -> FileHandle? {
    let log = URL.documentsDirectory.appending(path: "game-runtime.log")
    var handle: FileHandle?
    do {
      if !FileManager.default.fileExists(atPath: log.path) { try Data().write(to: log) }
      let file = try FileHandle(forWritingTo: log)
      handle = file
      if try file.seekToEnd() > 512 << 10 {
        try file.truncate(atOffset: 0)
        try file.seek(toOffset: 0)
      }
    } catch {
      report("opening game-runtime.log", error)
      do { try handle?.close() } catch { report("closing game-runtime.log", error) }
      handle = nil
    }

    do {
      let gameOutput = URL.documentsDirectory.appending(path: "game_output.log")
      try Data().write(to: gameOutput)
      let game = try FileHandle(forWritingTo: gameOutput)
      defer {
        do { try game.close() } catch { report("closing game_output.log", error) }
      }
      if setvbuf(stdout, nil, _IOLBF, 0) != 0 {
        fputs("GameRuntime: cannot configure stdout buffering\n", stderr)
      }
      for descriptor in [STDOUT_FILENO, STDERR_FILENO] {
        if dup2(game.fileDescriptor, descriptor) == -1 {
          report(
            "redirecting descriptor \(descriptor)",
            NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
      }
    } catch {
      report("opening game_output.log", error)
    }

    var system = utsname()
    uname(&system)
    let machine = withUnsafeBytes(of: system.machine) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    let header =
      "---- launch: \(machine) \(ProcessInfo.processInfo.operatingSystemVersionString), "
      + "\(ProcessInfo.processInfo.physicalMemory >> 20) MB RAM"
    do { try handle?.write(contentsOf: line(header)) } catch {
      report("writing launch header", error)
    }
    return handle
  }

  private static func line(_ message: String) -> Data {
    Data((String(format: "%.3f ", ProcessInfo.processInfo.systemUptime) + message + "\n").utf8)
  }

  private static func report(_ operation: String, _ error: Error) {
    fputs("GameRuntime: \(operation): \(error)\n", stderr)
  }
}
