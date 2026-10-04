import Dispatch
import Foundation
import ReturnQueueCore
import ReturnQueuePresentation
import ReturnQueueStorage

struct PresentationFixture: Sendable {
  let directory: URL
  let archiveURL: URL
  let recoveryDirectory: URL

  init(records: [ReturnItem]? = nil) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    archiveURL = directory.appendingPathComponent("returns.json")
    recoveryDirectory = directory.appendingPathComponent("recovery")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let records { try ArchiveCodec.encode(records).write(to: archiveURL) }
  }

  @MainActor
  func session(persistence: (any ReturnPersistence)? = nil) -> AppSession {
    AppSession(
      store: ReturnStore(persistence: persistence ?? ReturnRepository(fileURL: archiveURL)),
      recovery: RecoveryFileService(directory: recoveryDirectory))
  }

  func remove() throws {
    try FileManager.default.removeItem(at: directory)
  }

  static let instant = Date(timeIntervalSince1970: 1_800_000_000.123)

  static func item() -> ReturnItem {
    ReturnItem(title: "Original shoes", merchant: "Example Store", createdAt: instant)
  }
}

enum PresentationGateFailure: Error { case timedOut }

/// Holds an actual synchronous filesystem boundary while MainActor remains free to receive intents.
struct PresentationGate: Sendable {
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)

  func hold() throws {
    entered.signal()
    guard release.wait(timeout: .now() + 10) == .success else {
      throw PresentationGateFailure.timedOut
    }
  }

  func waitUntilEntered() async -> Bool {
    await withCheckedContinuation { continuation in
      // Waiting here on MainActor would prevent the very concurrency being tested.
      DispatchQueue.global().async {
        continuation.resume(returning: entered.wait(timeout: .now() + 10) == .success)
      }
    }
  }

  func repository(at url: URL) -> ReturnRepository {
    ReturnRepository(fileURL: url) { stage in
      if case .replacement = stage { try hold() }
    }
  }
}

struct DelayedReadPersistence: ReturnPersistence {
  let repository: ReturnRepository
  let gate: PresentationGate

  func readArchiveData() throws -> Data? {
    try gate.hold()
    return try repository.readArchiveData()
  }

  func writeAtomically(_ data: Data) throws { try repository.writeAtomically(data) }
  func copyRawArchive(to destination: URL) throws { try repository.copyRawArchive(to: destination) }
}

/// Records the real candidate for a failed first write, without pretending it was committed.
struct RecordingPersistence: ReturnPersistence {
  let repository: ReturnRepository
  let candidateURL: URL

  func readArchiveData() throws -> Data? { try repository.readArchiveData() }

  func writeAtomically(_ data: Data) throws {
    try data.write(to: candidateURL)
    try repository.writeAtomically(data)
  }

  func copyRawArchive(to destination: URL) throws { try repository.copyRawArchive(to: destination) }
}
