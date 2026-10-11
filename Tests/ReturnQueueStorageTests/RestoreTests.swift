import Dispatch
import Foundation
import ReturnQueueCore
import XCTest

@testable import ReturnQueueStorage

@MainActor
final class RestoreTests: XCTestCase {
  func testRestoreRequiresConfirmationReplacesRatherThanMergesAndConsumesToken() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    try ArchiveCodec.encode([StorageFixtures.item()]).write(to: fixture.live)
    let store = fixture.store()
    let before = try await store.load()
    let bytes = try Data(contentsOf: fixture.live)
    let records = try US4ArchiveFixture.records()
    let data = try ArchiveCodec.encode(records)
    let preview = try await store.stageRestore(data)
    do {
      _ = try await store.restore(preview.id, confirmation: .none)
      XCTFail("Unconfirmed replacement committed")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .confirmationRequired) }
    await us4AssertState(store, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), bytes)
    let committed = try await store.restore(preview.id, confirmation: .confirmed)
    XCTAssertEqual(committed.revision, before.revision + 1)
    XCTAssertEqual(committed.records, records)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.live)), records)
    do {
      _ = try await store.restore(preview.id, confirmation: .confirmed)
      XCTFail("Consumed preview used twice")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .invalidPreview) }
    let repeated = try await store.stageRestore(data)
    let again = try await store.restore(repeated.id, confirmation: .confirmed)
    XCTAssertEqual(again.records, records)
    XCTAssertEqual(again.revision, committed.revision + 1)
    let restarted = try await fixture.store().load()
    XCTAssertEqual(restarted.records, records)
  }

  func testEmptyReplacementStillRequiresConfirmationAndPersistsCanonicalArchive() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    try ArchiveCodec.encode([StorageFixtures.item()]).write(to: fixture.live)
    let store = fixture.store()
    _ = try await store.load()
    let preview = try await store.stageRestore(ArchiveCodec.encode([]))
    do {
      _ = try await store.restore(preview.id, confirmation: .none)
      XCTFail("Empty replacement bypassed confirmation")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .confirmationRequired) }
    let committed = try await store.restore(preview.id, confirmation: .confirmed)
    XCTAssertEqual(committed.records, [])
    XCTAssertEqual(try Data(contentsOf: fixture.live), try ArchiveCodec.encode([]))
    let restarted = try await fixture.store().load()
    XCTAssertEqual(restarted.records, [])
  }

  func testUnknownDiscardedAndReplacedTokensCannotWrite() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let store = fixture.store()
    let before = try await store.load()
    let data = try ArchiveCodec.encode(US4ArchiveFixture.records())
    let first = try await store.stageRestore(data)
    let second = try await store.stageRestore(data)
    await store.discardRestore(first.id)
    for id in [UUID(), first.id] {
      do {
        _ = try await store.restore(id, confirmation: .confirmed)
        XCTFail("Unknown or replaced token accepted")
      } catch { XCTAssertEqual(error as? ArchiveFailure, .invalidPreview) }
    }
    await us4AssertState(store, .ready(before))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.live.path))
    let committed = try await store.restore(second.id, confirmation: .confirmed)
    XCTAssertEqual(committed.records.count, 2)
    let third = try await store.stageRestore(data)
    await store.discardRestore(third.id)
    do {
      _ = try await store.restore(third.id, confirmation: .confirmed)
      XCTFail("Discarded token accepted")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .invalidPreview) }
  }

  func testMutationAndFailedReloadMakeKnownPreviewStaleNotUnknown() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let store = fixture.store()
    _ = try await store.load()
    let data = try ArchiveCodec.encode(US4ArchiveFixture.records())
    let preview = try await store.stageRestore(data)
    let committed = try await store.create(StorageFixtures.item())
    let bytes = try Data(contentsOf: fixture.live)
    do {
      _ = try await store.restore(preview.id, confirmation: .confirmed)
      XCTFail("Intervening commit overwritten by stale candidate")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .stalePreview) }
    await us4AssertState(store, .ready(committed))
    XCTAssertEqual(try Data(contentsOf: fixture.live), bytes)
    let next = try await store.stageRestore(data)
    let corrupt = Data("corrupt external change".utf8)
    try corrupt.write(to: fixture.live)
    do { _ = try await store.load() } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    do {
      _ = try await store.restore(next.id, confirmation: .confirmed)
      XCTFail("Failed load did not invalidate staged generation")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .stalePreview) }
    await us4AssertState(store, .readFailed(.readFailed, lastCommitted: committed))
    XCTAssertEqual(try Data(contentsOf: fixture.live), corrupt)
  }

  func testNotLoadedRejectsStagingAndReadFailedPreviewKeepsUnknownCurrentCount() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let store = fixture.store()
    let data = try ArchiveCodec.encode(US4ArchiveFixture.records())
    do {
      _ = try await store.stageRestore(data)
      XCTFail("Not-loaded store staged replacement")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .notLoaded) }
    let corrupt = Data("corrupt original".utf8)
    try corrupt.write(to: fixture.live)
    do { _ = try await store.load() } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    let preview = try await store.stageRestore(data)
    XCTAssertNil(preview.currentReturnCount)
    XCTAssertEqual(try Data(contentsOf: fixture.live), corrupt)
    let committed = try await store.restore(preview.id, confirmation: .confirmed)
    XCTAssertEqual(committed.records.count, 2)
    await us4AssertState(store, .ready(committed))
    let restarted = try await fixture.store().load()
    XCTAssertEqual(restarted.records, committed.records)
  }

  func testEveryPrecommitFailurePreservesBytesSnapshotCandidateAndRemovesStaging() async throws {
    for stage in [ReturnRepository.WriteStage.stage, .protection, .replacement] {
      let fixture = try US4ArchiveFixture()
      defer { try? fixture.remove() }
      let original = try ArchiveCodec.encode([StorageFixtures.item()])
      try original.write(to: fixture.live)
      let rejection = fixture.directory.appendingPathComponent("reject-write")
      try Data().write(to: rejection)
      let repository = ReturnRepository(fileURL: fixture.live) { actual in
        let matches: Bool
        switch (actual, stage) {
        case (.stage, .stage), (.protection, .protection), (.replacement, .replacement):
          matches = true
        default: matches = false
        }
        if matches, FileManager.default.fileExists(atPath: rejection.path) {
          throw StorageFixtures.InjectedFailure.precommit
        }
      }
      let store = ReturnStore(persistence: repository)
      let before = try await store.load()
      let records = try US4ArchiveFixture.records()
      let preview = try await store.stageRestore(ArchiveCodec.encode(records))
      do {
        _ = try await store.restore(preview.id, confirmation: .confirmed)
        XCTFail("Injected precommit failure committed")
      } catch { XCTAssertEqual(error as? ReturnStoreFailure, .writeFailed) }
      await us4AssertState(store, .ready(before))
      XCTAssertEqual(try Data(contentsOf: fixture.live), original)
      XCTAssertEqual(
        try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted(),
        ["live.json", "reject-write"])
      try FileManager.default.removeItem(at: rejection)
      let committed = try await store.restore(preview.id, confirmation: .confirmed)
      XCTAssertEqual(committed.records, records)
    }
  }

  func testAdmittedStageReturnsExactTokenAfterCancellationAndOldDiscardKeepsNewCandidate()
    async throws
  {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let gate = US4TransactionGate()
    defer { gate.release.signal() }
    let store = ReturnStore(
      persistence: ReturnRepository(fileURL: fixture.live),
      restoreStageObserver: {
        do { try gate.hold() } catch { XCTFail("Admitted-stage observation timed out") }
      })
    let before = try await store.load()
    let records = try US4ArchiveFixture.records()
    let data = try ArchiveCodec.encode(records)
    let staging = Task { try await store.stageRestore(data) }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    staging.cancel()
    gate.release.signal()
    let returned = try await staging.value
    XCTAssertEqual(returned.returnCount, 2)
    await us4AssertState(store, .ready(before))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.live.path))
    gate.release.signal()
    let replacement = try await store.stageRestore(data)
    XCTAssertNotEqual(returned.id, replacement.id)
    await store.discardRestore(returned.id)
    let committed = try await store.restore(replacement.id, confirmation: .confirmed)
    XCTAssertEqual(committed.records, records)
  }

  func testSingleAndAllDeletionRequireCapturedRevisionAndKeepUnrelatedRecordExact() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let records = try US4ArchiveFixture.records()
    try ArchiveCodec.encode(records).write(to: fixture.live)
    let store = fixture.store()
    let before = try await store.load()
    let bytes = try Data(contentsOf: fixture.live)
    do {
      _ = try await store.delete(itemID: records[0].id, expectedRevision: before.revision)
      XCTFail("Unconfirmed single deletion accepted")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .confirmationRequired) }
    XCTAssertEqual(try Data(contentsOf: fixture.live), bytes)
    let deleted = try await store.delete(
      itemID: records[0].id, expectedRevision: before.revision, confirmation: .confirmed)
    XCTAssertEqual(deleted.records, [records[1]])
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.live)), [records[1]])
    do {
      _ = try await store.deleteAll(expectedRevision: before.revision, confirmation: .confirmed)
      XCTFail("Stale delete-all accepted")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .staleRevision) }
    do {
      _ = try await store.deleteAll(expectedRevision: deleted.revision)
      XCTFail("Unconfirmed delete-all accepted")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .confirmationRequired) }
    let empty = try await store.deleteAll(
      expectedRevision: deleted.revision, confirmation: .confirmed)
    XCTAssertEqual(empty.records, [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.live.path))
    XCTAssertEqual(try Data(contentsOf: fixture.live), try ArchiveCodec.encode([]))
    do {
      _ = try await store.deleteAll(expectedRevision: deleted.revision, confirmation: .confirmed)
      XCTFail("Duplicate captured delete-all committed")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .staleRevision) }
  }

  func testCancelledQueuedDeleteNeverEntersTransactionButAdmittedWriteCommits() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let original = StorageFixtures.item()
    try ArchiveCodec.encode([original]).write(to: fixture.live)
    let gate = US4TransactionGate()
    defer { gate.release.signal() }
    let store = ReturnStore(
      persistence: ReturnRepository(fileURL: fixture.live) { stage in
        if case .replacement = stage { try gate.hold() }
      })
    let before = try await store.load()
    let added = StorageFixtures.item()
    let write = Task { try await store.create(added) }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    let deletion = Task {
      try await store.deleteAll(expectedRevision: before.revision, confirmation: .confirmed)
    }
    deletion.cancel()
    gate.release.signal()
    let committed = try await write.value
    do {
      _ = try await deletion.value
      XCTFail("Cancelled queued deletion admitted")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(committed.records, [original, added])
    await us4AssertState(store, .ready(committed))
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.live)), committed.records)
    let deletionAfterAdmission = Task {
      try await store.deleteAll(expectedRevision: committed.revision, confirmation: .confirmed)
    }
    let deleting = await gate.waitUntilEntered()
    XCTAssertTrue(deleting)
    deletionAfterAdmission.cancel()
    gate.release.signal()
    let empty = try await deletionAfterAdmission.value
    XCTAssertEqual(empty.records, [])
    await us4AssertState(store, .ready(empty))
    XCTAssertEqual(try Data(contentsOf: fixture.live), try ArchiveCodec.encode([]))
  }
  func testFailedOrdinaryWriteKeepsStagedGenerationForExplicitRestoreRetry() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let original = try ArchiveCodec.encode([StorageFixtures.item()])
    try original.write(to: fixture.live)
    let rejection = fixture.directory.appendingPathComponent("reject-write")
    try Data().write(to: rejection)
    let store = ReturnStore(
      persistence: ReturnRepository(fileURL: fixture.live) { stage in
        if case .replacement = stage, FileManager.default.fileExists(atPath: rejection.path) {
          throw StorageFixtures.InjectedFailure.precommit
        }
      })
    let before = try await store.load()
    let records = try US4ArchiveFixture.records()
    let preview = try await store.stageRestore(ArchiveCodec.encode(records))
    do {
      _ = try await store.create(StorageFixtures.item())
      XCTFail("Injected ordinary write committed")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .writeFailed) }
    await us4AssertState(store, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), original)
    try FileManager.default.removeItem(at: rejection)
    let restored = try await store.restore(preview.id, confirmation: .confirmed)
    XCTAssertEqual(restored.records, records)
  }

  func testFailedRestoreFromReadFailurePreservesCorruptOriginalAndSameCandidateRepairsOnRetry()
    async throws
  {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    try ArchiveCodec.encode([StorageFixtures.item()]).write(to: fixture.live)
    let rejection = fixture.directory.appendingPathComponent("reject-write")
    try Data().write(to: rejection)
    let store = ReturnStore(
      persistence: ReturnRepository(fileURL: fixture.live) { stage in
        if case .replacement = stage, FileManager.default.fileExists(atPath: rejection.path) {
          throw StorageFixtures.InjectedFailure.precommit
        }
      })
    let before = try await store.load()
    let corrupt = Data("retained corrupt original".utf8)
    try corrupt.write(to: fixture.live)
    do { _ = try await store.load() } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    let records = try US4ArchiveFixture.records()
    let preview = try await store.stageRestore(ArchiveCodec.encode(records))
    XCTAssertNil(preview.currentReturnCount)
    do {
      _ = try await store.restore(preview.id, confirmation: .confirmed)
      XCTFail("Failed recovery write committed")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .writeFailed) }
    await us4AssertState(store, .readFailed(.readFailed, lastCommitted: before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), corrupt)
    try FileManager.default.removeItem(at: rejection)
    let repaired = try await store.restore(preview.id, confirmation: .confirmed)
    XCTAssertEqual(repaired.records, records)
    let restarted = try await fixture.store().load()
    XCTAssertEqual(restarted.records, records)
  }

  func testDeletionRejectsNotLoadedBlockedMissingAndEveryAtomicFailure() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let record = StorageFixtures.item()
    let original = try ArchiveCodec.encode([record])
    try original.write(to: fixture.live)
    let notLoaded = fixture.store()
    do {
      _ = try await notLoaded.deleteAll(expectedRevision: 0, confirmation: .confirmed)
      XCTFail("Deletion before load admitted")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .notLoaded) }
    for stage in [ReturnRepository.WriteStage.stage, .protection, .replacement] {
      let store = ReturnStore(
        persistence: StorageFixtures.failingRepository(fileURL: fixture.live, stage: stage))
      let before = try await store.load()
      do {
        _ = try await store.delete(
          itemID: UUID(), expectedRevision: before.revision, confirmation: .confirmed)
        XCTFail("Missing record deletion succeeded")
      } catch { XCTAssertEqual(error as? ReturnStoreFailure, .missingRecord) }
      for all in [false, true] {
        do {
          if all {
            _ = try await store.deleteAll(
              expectedRevision: before.revision, confirmation: .confirmed)
          } else {
            _ = try await store.delete(
              itemID: record.id, expectedRevision: before.revision, confirmation: .confirmed)
          }
          XCTFail("Injected deletion failure committed")
        } catch { XCTAssertEqual(error as? ReturnStoreFailure, .writeFailed) }
        await us4AssertState(store, .ready(before))
        XCTAssertEqual(try Data(contentsOf: fixture.live), original)
        XCTAssertEqual(
          try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), ["live.json"]
        )
      }
    }
    let blocked = fixture.store()
    _ = try await blocked.load()
    let corrupt = Data("blocked original".utf8)
    try corrupt.write(to: fixture.live)
    do { _ = try await blocked.load() } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    do {
      _ = try await blocked.deleteAll(expectedRevision: 1, confirmation: .confirmed)
      XCTFail("Unreadable live archive deleted")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .readBlocked) }
    XCTAssertEqual(try Data(contentsOf: fixture.live), corrupt)
  }

  func testConcurrentDeletesUsingOneRevisionProduceOneCommitAndOneStaleFailure() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let records = try US4ArchiveFixture.records()
    try ArchiveCodec.encode(records).write(to: fixture.live)
    let store = fixture.store()
    let before = try await store.load()
    let operations = records.map { record in
      Task {
        try await store.delete(
          itemID: record.id, expectedRevision: before.revision, confirmation: .confirmed)
      }
    }
    var successes: [ReturnSnapshot] = []
    var failures: [ReturnStoreFailure] = []
    for operation in operations {
      do { successes.append(try await operation.value) } catch {
        failures.append(try XCTUnwrap(error as? ReturnStoreFailure))
      }
    }
    XCTAssertEqual(successes.count, 1)
    XCTAssertEqual(failures, [.staleRevision])
    let committed = try XCTUnwrap(successes.first)
    XCTAssertEqual(committed.revision, before.revision + 1)
    XCTAssertEqual(committed.records.count, 1)
    XCTAssertTrue(records.contains(committed.records[0]))
    await us4AssertState(store, .ready(committed))
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.live)), committed.records)
  }
}

@MainActor
func us4AssertState(
  _ store: ReturnStore, _ expected: ReturnStoreState, file: StaticString = #filePath,
  line: UInt = #line
) async {
  let actual = await store.state()
  XCTAssertEqual(actual, expected, file: file, line: line)
}

struct US4TransactionGate: Sendable {
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  func hold() throws {
    entered.signal()
    guard release.wait(timeout: .now() + 10) == .success else {
      throw StorageFixtures.InjectedFailure.precommit
    }
  }
  func waitUntilEntered() async -> Bool {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: entered.wait(timeout: .now() + 10) == .success)
      }
    }
  }
}
