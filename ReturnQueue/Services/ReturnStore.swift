import Foundation
import ReturnQueueCore

public struct ReturnSnapshot: Equatable, Sendable {
  public let revision: UInt64
  public let records: [ReturnItem]

  public init(revision: UInt64, records: [ReturnItem]) {
    self.revision = revision
    self.records = records
  }
}

public enum ReturnStoreFailure: Error, Equatable, LocalizedError, Sendable {
  case notLoaded
  case readBlocked
  case readFailed
  case writeFailed
  case invalidRecords
  case staleRevision
  case missingRecord
  case revisionOverflow

  public var errorDescription: String? {
    switch self {
    case .notLoaded: return "Load saved returns before making changes."
    case .readBlocked: return "Retry loading or recover saved data before making changes."
    case .readFailed:
      return "Saved returns could not be loaded. Existing data has not been replaced."
    case .writeFailed: return "Changes could not be saved. Your previous data is preserved."
    case .invalidRecords: return "Check the return details before saving."
    case .staleRevision: return "The saved data changed. Reopen this return before editing."
    case .missingRecord: return "This return is no longer in the saved data."
    case .revisionOverflow: return "Reopen the app before making more changes."
    }
  }
}

public enum ReturnStoreState: Equatable, Sendable {
  case notLoaded
  case ready(ReturnSnapshot)
  case readFailed(ReturnStoreFailure, lastCommitted: ReturnSnapshot?)
}

/// Owns one committed snapshot. Transactions never suspend between applying and publication.
public actor ReturnStore {
  private let persistence: any ReturnPersistence
  private var currentState: ReturnStoreState = .notLoaded
  private var revision: UInt64 = 0

  public init(persistence: any ReturnPersistence) {
    self.persistence = persistence
  }

  public func state() -> ReturnStoreState { currentState }

  public func load() throws -> ReturnSnapshot {
    let previous: ReturnSnapshot?
    switch currentState {
    case .notLoaded: previous = nil
    case .ready(let snapshot): previous = snapshot
    case .readFailed(_, let snapshot): previous = snapshot
    }
    do {
      let next = try nextRevision()
      let data = try persistence.readArchiveData()
      let records = try data.map { try ArchiveCodec.decode($0) } ?? []
      let snapshot = ReturnSnapshot(revision: next, records: records)
      revision = next
      currentState = .ready(snapshot)
      return snapshot
    } catch {
      let failure: ReturnStoreFailure =
        error as? ReturnStoreFailure == .revisionOverflow ? .revisionOverflow : .readFailed
      currentState = .readFailed(failure, lastCommitted: previous)
      throw failure
    }
  }

  public func create(_ item: ReturnItem) throws -> ReturnSnapshot {
    let snapshot = try writableSnapshot()
    guard !snapshot.records.contains(where: { $0.id == item.id }) else {
      throw ReturnStoreFailure.invalidRecords
    }
    return try commit(snapshot.records + [item])
  }

  public func update(
    _ item: ReturnItem, expectedRevision: UInt64, confirmation: ReturnConfirmation = .none
  ) throws -> ReturnSnapshot {
    let snapshot = try writableSnapshot()
    guard expectedRevision == snapshot.revision else { throw ReturnStoreFailure.staleRevision }
    guard let index = snapshot.records.firstIndex(where: { $0.id == item.id }) else {
      throw ReturnStoreFailure.missingRecord
    }
    var replacement = item
    replacement.createdAt = snapshot.records[index].createdAt
    // Validate the actual replacement, preserving the accepted creation-time ownership.
    do {
      _ = try replacement.validated()
    } catch {
      throw ReturnStoreFailure.invalidRecords
    }
    if try ReturnTransitions.requiresExpectedRefundConfirmation(
      from: snapshot.records[index], to: replacement), confirmation != .confirmed
    {
      throw ReturnTransitionFailure.confirmationRequired(.excessReimbursement)
    }
    var records = snapshot.records
    records[index] = replacement
    return try commit(records)
  }

  public func mutate(
    itemID: UUID, command: ReturnMutation, expectedRevision: UInt64, updatedAt: Date,
    confirmation: ReturnConfirmation = .none
  ) throws -> ReturnSnapshot {
    let snapshot = try writableSnapshot()
    guard expectedRevision == snapshot.revision else { throw ReturnStoreFailure.staleRevision }
    guard let index = snapshot.records.firstIndex(where: { $0.id == itemID }) else {
      throw ReturnStoreFailure.missingRecord
    }
    let replacement = try ReturnTransitions.applying(
      command, to: snapshot.records[index], updatedAt: updatedAt, confirmation: confirmation)
    var records = snapshot.records
    records[index] = replacement
    return try commit(records)
  }

  public func copyRawArchive(to destination: URL) throws {
    do {
      try persistence.copyRawArchive(to: destination)
    } catch let failure as ReturnPersistenceFailure {
      throw failure
    } catch {
      throw ReturnStoreFailure.writeFailed
    }
  }

  private func writableSnapshot() throws -> ReturnSnapshot {
    switch currentState {
    case .notLoaded: throw ReturnStoreFailure.notLoaded
    case .readFailed: throw ReturnStoreFailure.readBlocked
    case .ready(let snapshot): return snapshot
    }
  }

  private func nextRevision() throws -> UInt64 {
    let (next, overflow) = revision.addingReportingOverflow(1)
    guard !overflow else { throw ReturnStoreFailure.revisionOverflow }
    return next
  }

  private func commit(_ candidate: [ReturnItem]) throws -> ReturnSnapshot {
    let next = try nextRevision()
    let records: [ReturnItem]
    let data: Data
    do {
      records = try candidate.map { try $0.validated() }
      data = try ArchiveCodec.encode(records)
    } catch {
      throw ReturnStoreFailure.invalidRecords
    }
    do {
      try persistence.writeAtomically(data)
    } catch {
      throw ReturnStoreFailure.writeFailed
    }
    let snapshot = ReturnSnapshot(revision: next, records: records)
    revision = next
    currentState = .ready(snapshot)
    return snapshot
  }
}
