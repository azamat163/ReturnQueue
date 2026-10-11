import Foundation
import Observation
import ReturnQueueCore
import ReturnQueueStorage

public enum SessionPhase: Equatable, Sendable {
  case notLoaded
  case loading(lastCommitted: ReturnSnapshot?)
  case ready(ReturnSnapshot)
  case loadFailed(ReturnStoreFailure, lastCommitted: ReturnSnapshot?)
}

public enum SessionActivity: Equatable, Sendable {
  case idle, loading, saving, exporting, importing
}

public enum SessionFailure: Error, Equatable, Sendable {
  case busy, notReady
  case store(ReturnStoreFailure)
  case recovery(ReturnPersistenceFailure)
  case validation(ReturnQueueError)
  case transition(ReturnTransitionFailure)
  case archive(ArchiveFailure)
}

@MainActor @Observable
public final class AppSession {
  public private(set) var phase: SessionPhase = .notLoaded
  public private(set) var activity: SessionActivity = .idle
  private let store: ReturnStore
  private let recovery: RecoveryFileService
  private let archive: ArchiveService

  public init(store: ReturnStore, recovery: RecoveryFileService, archive: ArchiveService) {
    self.store = store
    self.recovery = recovery
    self.archive = archive
  }

  public var snapshot: ReturnSnapshot? {
    switch phase {
    case .notLoaded: return nil
    case .ready(let snapshot): return snapshot
    case .loading(let snapshot), .loadFailed(_, let snapshot): return snapshot
    }
  }

  public var canEdit: Bool {
    if case .ready = phase { return activity == .idle }
    return false
  }

  public func load() async throws {
    try begin(.loading)
    let previous = snapshot
    phase = .loading(lastCommitted: previous)
    defer { activity = .idle }
    do {
      let committed = try await store.load()
      publish(committed)
    } catch {
      let failure = error as? ReturnStoreFailure ?? .readFailed
      phase = .loadFailed(failure, lastCommitted: previous)
      throw SessionFailure.store(failure)
    }
  }

  public func create(_ item: ReturnItem) async throws -> ReturnSnapshot {
    try beginMutation()
    defer { activity = .idle }
    do {
      let committed = try await store.create(item)
      // Even a cancelled caller must publish an operation that reached durable commit.
      publish(committed)
      return committed
    } catch {
      throw SessionFailure.store(error as? ReturnStoreFailure ?? .writeFailed)
    }
  }

  public func update(
    _ item: ReturnItem, expectedRevision: UInt64, confirmation: ReturnConfirmation = .none
  ) async throws -> ReturnSnapshot {
    try beginMutation()
    defer { activity = .idle }
    do {
      let committed = try await store.update(
        item, expectedRevision: expectedRevision, confirmation: confirmation)
      publish(committed)
      return committed
    } catch let error as ReturnQueueError {
      throw SessionFailure.validation(error)
    } catch let error as ReturnTransitionFailure {
      throw SessionFailure.transition(error)
    } catch {
      throw SessionFailure.store(error as? ReturnStoreFailure ?? .writeFailed)
    }
  }

  public func mutate(
    itemID: UUID, command: ReturnMutation, expectedRevision: UInt64, updatedAt: Date,
    confirmation: ReturnConfirmation = .none
  ) async throws -> ReturnSnapshot {
    try beginMutation()
    defer { activity = .idle }
    do {
      let committed = try await store.mutate(
        itemID: itemID, command: command, expectedRevision: expectedRevision,
        updatedAt: updatedAt, confirmation: confirmation)
      publish(committed)
      return committed
    } catch let error as ReturnQueueError {
      throw SessionFailure.validation(error)
    } catch let error as ReturnTransitionFailure {
      throw SessionFailure.transition(error)
    } catch {
      throw SessionFailure.store(error as? ReturnStoreFailure ?? .writeFailed)
    }
  }

  public func exportOriginal() async throws -> URL {
    try begin(.exporting)
    defer { activity = .idle }
    let destination: URL
    do {
      destination = try await recovery.makeDestination()
    } catch {
      throw SessionFailure.recovery(error as? ReturnPersistenceFailure ?? .rawCopyFailed)
    }
    do {
      try await store.copyRawArchive(to: destination)
      return destination
    } catch {
      do {
        try await recovery.remove(destination)
      } catch {
        throw SessionFailure.recovery(error as? ReturnPersistenceFailure ?? .rawCopyFailed)
      }
      throw SessionFailure.recovery(error as? ReturnPersistenceFailure ?? .rawCopyFailed)
    }
  }

  public func cleanupRecovery(_ url: URL) async throws {
    do {
      try await recovery.remove(url)
    } catch {
      throw SessionFailure.recovery(error as? ReturnPersistenceFailure ?? .rawCopyFailed)
    }
  }

  public func exportBackup() async throws -> ArchiveExport {
    guard canEdit else {
      throw activity == .idle ? SessionFailure.notReady : SessionFailure.busy
    }
    try begin(.exporting)
    defer { activity = .idle }
    do {
      // Return an admitted copy's identity even after caller cancellation.
      return try await archive.exportValidated()
    } catch {
      throw archiveFailure(error)
    }
  }

  public func previewRestore(from url: URL) async throws -> RestorePreview {
    try beginRecovery(.importing)
    defer { activity = .idle }
    do {
      return try await archive.previewImport(from: url)
    } catch {
      throw archiveFailure(error)
    }
  }

  public func cancelRestore(_ id: UUID) async {
    // Exact-ID discard remains available to a cancelled import's owner.
    await archive.discardPreview(id)
  }

  public func restore(
    _ id: UUID, confirmation: ArchiveConfirmation
  ) async throws -> ReturnSnapshot {
    try beginRecovery(.saving)
    defer { activity = .idle }
    do {
      let committed = try await archive.restore(id, confirmation: confirmation)
      publish(committed)
      return committed
    } catch {
      throw archiveFailure(error)
    }
  }

  public func delete(
    itemID: UUID, expectedRevision: UInt64, confirmation: ArchiveConfirmation
  ) async throws -> ReturnSnapshot {
    try beginMutation()
    defer { activity = .idle }
    do {
      let committed = try await store.delete(
        itemID: itemID, expectedRevision: expectedRevision, confirmation: confirmation)
      publish(committed)
      return committed
    } catch {
      throw archiveFailure(error)
    }
  }

  public func deleteAll(
    expectedRevision: UInt64, confirmation: ArchiveConfirmation
  ) async throws -> ReturnSnapshot {
    try beginMutation()
    defer { activity = .idle }
    do {
      let committed = try await store.deleteAll(
        expectedRevision: expectedRevision, confirmation: confirmation)
      publish(committed)
      return committed
    } catch {
      throw archiveFailure(error)
    }
  }

  public func cleanupBackup(_ export: ArchiveExport) async throws {
    do {
      try await archive.removeExport(export)
    } catch {
      throw archiveFailure(error)
    }
  }

  private func beginRecovery(_ activity: SessionActivity) throws {
    guard self.activity == .idle else { throw SessionFailure.busy }
    switch phase {
    case .ready, .loadFailed: self.activity = activity
    case .notLoaded, .loading: throw SessionFailure.notReady
    }
  }

  private func archiveFailure(_ error: any Error) -> any Error {
    switch error {
    case is CancellationError: return error
    case let failure as ArchiveFailure: return SessionFailure.archive(failure)
    case let failure as ReturnStoreFailure: return SessionFailure.store(failure)
    default: return SessionFailure.archive(.invalidArchive)
    }
  }

  private func begin(_ activity: SessionActivity) throws {
    guard self.activity == .idle else { throw SessionFailure.busy }
    self.activity = activity
  }

  private func beginMutation() throws {
    guard activity == .idle else { throw SessionFailure.busy }
    guard canEdit else { throw SessionFailure.notReady }
    activity = .saving
  }

  private func publish(_ committed: ReturnSnapshot) {
    if let previous = snapshot, committed.revision <= previous.revision {
      phase = .ready(previous)
    } else {
      phase = .ready(committed)
    }
  }
}
