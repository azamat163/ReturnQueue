import Foundation
import ReturnQueueCore

public struct RestorePreview: Equatable, Sendable {
  public let id: UUID
  public let returnCount: Int
  public let reimbursementCount: Int
  public let currentReturnCount: Int?
}

public struct ArchiveExport: Equatable, Sendable {
  public let id: UUID
  public let url: URL
}

public enum ArchiveConfirmation: Equatable, Sendable {
  case none, confirmed
}

public enum ArchiveFailure: Error, Equatable, Sendable {
  case invalidArchive, archiveTooLarge, sourceUnavailable
  case invalidPreview, stalePreview, confirmationRequired
  case exportFailed, cleanupFailed, invalidExport
}

/// Coordinates selected-file reads and retains ownership of private, validated exports.
public actor ArchiveService {
  private let store: ReturnStore
  private let directory: URL
  private let exportCreatedObserver: @Sendable (ArchiveExport) -> Void
  private var exports: [UUID: URL] = [:]

  public init(store: ReturnStore, directory: URL) {
    self.store = store
    self.directory = directory
    exportCreatedObserver = { _ in }
  }

  init(
    store: ReturnStore, directory: URL,
    exportCreatedObserver: @escaping @Sendable (ArchiveExport) -> Void
  ) {
    self.store = store
    self.directory = directory
    self.exportCreatedObserver = exportCreatedObserver
  }

  public func exportValidated() async throws -> ArchiveExport {
    try Task.checkCancellation()
    let data = try await store.encodedCommittedArchive()
    try Task.checkCancellation()
    guard directory.isFileURL, !directory.path.utf8.contains(0) else {
      throw ArchiveFailure.exportFailed
    }
    let id = UUID()
    let destination = directory.appendingPathComponent("ReturnQueue-backup-\(id.uuidString).json")
    do {
      try ReturnRepository(fileURL: destination).writeAtomically(data)
    } catch {
      // The atomic writer removes its own staging file and never publishes a failed write.
      throw ArchiveFailure.exportFailed
    }
    let export = ArchiveExport(id: id, url: destination)
    exports[id] = destination
    exportCreatedObserver(export)
    // Once created, transfer the capability even if the caller was cancelled meanwhile.
    return export
  }

  public func previewImport(from selectedURL: URL) async throws -> RestorePreview {
    try Task.checkCancellation()
    let data = try readSelection(selectedURL)
    try Task.checkCancellation()
    // Store admission owns cancellation; never lose the identity of an admitted candidate.
    return try await store.stageRestore(data)
  }

  public func discardPreview(_ id: UUID) async { await store.discardRestore(id) }

  public func restore(
    _ id: UUID, confirmation: ArchiveConfirmation = .none
  ) async throws -> ReturnSnapshot {
    try Task.checkCancellation()
    return try await store.restore(id, confirmation: confirmation)
  }

  public func removeExport(_ export: ArchiveExport) throws {
    guard exports[export.id] == export.url else { throw ArchiveFailure.invalidExport }
    do {
      try FileManager.default.removeItem(at: export.url)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      // An owned destination already absent needs no further cleanup.
    } catch {
      throw ArchiveFailure.cleanupFailed
    }
    exports.removeValue(forKey: export.id)
  }

  private func readSelection(_ url: URL) throws -> Data {
    guard url.isFileURL, !url.path.utf8.contains(0) else {
      throw ArchiveFailure.sourceUnavailable
    }
    #if canImport(Darwin)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      var coordinationError: NSError?
      var result: Result<Data, ArchiveFailure>?
      let coordinator = NSFileCoordinator(filePresenter: nil)
      coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
        selected in
        result = Result { try Self.readBounded(selected) }
          .mapError { $0 as? ArchiveFailure ?? .sourceUnavailable }
      }
      guard coordinationError == nil, let result else { throw ArchiveFailure.sourceUnavailable }
      return try result.get()
    #else
      return try Self.readBounded(url)
    #endif
  }

  private static func readBounded(_ url: URL) throws -> Data {
    do {
      guard let data = try ReturnRepository(fileURL: url).readArchiveData() else {
        throw ArchiveFailure.sourceUnavailable
      }
      return data
    } catch ReturnPersistenceFailure.archiveTooLarge {
      throw ArchiveFailure.archiveTooLarge
    } catch {
      throw ArchiveFailure.sourceUnavailable
    }
  }
}
