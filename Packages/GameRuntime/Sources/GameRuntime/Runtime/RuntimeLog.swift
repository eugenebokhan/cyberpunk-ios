import Foundation
import Synchronization

/// Runtime diagnostics in Documents/macshim.log. The game's stdout and stderr, where the engine
/// prints its own log, go to Documents/game_output.log.
enum RuntimeLog {
  private static let output = Mutex<FileHandle?>(nil)

  static func open() {
    let manager = FileManager.default
    let log = URL.documentsDirectory.appending(path: "macshim.log")
    if let size = try? manager.attributesOfItem(atPath: log.path)[.size] as? Int, size > 512 << 10 {
      try? manager.removeItem(at: log)
    }
    if !manager.fileExists(atPath: log.path) { manager.createFile(atPath: log.path, contents: nil) }
    let handle = try? FileHandle(forWritingTo: log)
    _ = try? handle?.seekToEnd()
    output.withLock { $0 = handle }

    let gameOutput = URL.documentsDirectory.appending(path: "game_output.log")
    if manager.createFile(atPath: gameOutput.path, contents: nil),
      let game = try? FileHandle(forWritingTo: gameOutput)
    {
      setvbuf(stdout, nil, _IOLBF, 0)
      dup2(game.fileDescriptor, STDOUT_FILENO)
      dup2(game.fileDescriptor, STDERR_FILENO)
      try? game.close()
    }
    var system = utsname()
    uname(&system)
    let machine = withUnsafeBytes(of: system.machine) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    write(
      "---- launch: \(machine) \(ProcessInfo.processInfo.operatingSystemVersionString), "
        + "\(ProcessInfo.processInfo.physicalMemory >> 20) MB RAM")
  }

  static func write(_ message: String) {
    let line = String(format: "%.3f ", ProcessInfo.processInfo.systemUptime) + message + "\n"
    output.withLock { try? $0?.write(contentsOf: Data(line.utf8)) }
  }
}
