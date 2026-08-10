import Foundation

struct BuildFailure: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}
