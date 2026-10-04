import Foundation

/// Synchronous operations let the store keep apply/write/publish in one actor turn.
public protocol ReturnPersistence: Sendable {
  func readArchiveData() throws -> Data?
  func writeAtomically(_ data: Data) throws
  func copyRawArchive(to destination: URL) throws
}

public enum ReturnPersistenceFailure: Error, Equatable, LocalizedError, Sendable {
  case readFailed
  case writeFailed
  case archiveTooLarge
  case sourceMissing
  case rawCopyFailed
  case invalidDestination

  public var errorDescription: String? {
    switch self {
    case .readFailed: return "The saved returns could not be read. Retry or recover a backup."
    case .writeFailed: return "The changes could not be saved. Your previous data is preserved."
    case .archiveTooLarge: return "The saved archive exceeds the supported size."
    case .sourceMissing: return "There is no saved archive to copy."
    case .rawCopyFailed: return "The saved archive could not be copied. Try another destination."
    case .invalidDestination: return "Choose a separate destination for the recovery copy."
    }
  }
}
