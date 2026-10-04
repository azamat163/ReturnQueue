import Foundation
import ReturnQueueCore
import ReturnQueueStorage
import XCTest

@MainActor
final class StoreTests: XCTestCase {
  func testMissingLoadPublishesEmptyReadyWithoutWriting() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let snapshot = try await store.load()
    let state = await store.state()
    XCTAssertEqual(snapshot.revision, 1)
    XCTAssertEqual(snapshot.records, [])
    XCTAssertEqual(state, .ready(snapshot))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
  }

  func testMutationsBeforeLoadAreBlocked() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    do {
      _ = try await store.create(StorageFixtures.item())
      XCTFail("Create succeeded before load")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .notLoaded)
    }
    do {
      _ = try await store.update(StorageFixtures.item(), expectedRevision: 0)
      XCTFail("Update succeeded before load")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .notLoaded)
    }
    let state = await store.state()
    XCTAssertEqual(state, .notLoaded)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
  }

  func testMalformedUnsupportedAndOversizedLoadBlockMutations() async throws {
    for scenario in ["malformed", "unsupported", "oversized"] {
      let fixture = try TemporaryArchive()
      defer { try? fixture.remove() }
      let original: Data
      switch scenario {
      case "unsupported":
        original = Data(#"{"format":"com.azamat163.returnqueue.p1","version":2,"records":[]}"#.utf8)
      case "oversized":
        original = Data(repeating: 0xA5, count: ArchiveCodec.maximumArchiveBytes + 1)
      default:
        original = Data("malformed source".utf8)
      }
      try fixture.write(original)
      let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
      do {
        _ = try await store.load()
        XCTFail("Load succeeded for \(scenario)")
      } catch {
        XCTAssertEqual(error as? ReturnStoreFailure, .readFailed, scenario)
      }
      do {
        _ = try await store.create(StorageFixtures.item())
        XCTFail("Create succeeded after failed load")
      } catch {
        XCTAssertEqual(error as? ReturnStoreFailure, .readBlocked, scenario)
      }
      do {
        _ = try await store.update(StorageFixtures.item(), expectedRevision: 0)
        XCTFail("Update succeeded after failed load")
      } catch {
        XCTAssertEqual(error as? ReturnStoreFailure, .readBlocked, scenario)
      }
      let state = await store.state()
      XCTAssertEqual(state, .readFailed(.readFailed, lastCommitted: nil), scenario)
      XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original, scenario)
    }
  }

  func testUnreadableLoadBlocksMutationsAndPreservesBytes() async throws {
    try XCTSkipIf(
      StorageFixtures.isRoot, "UID 0 bypasses POSIX read permissions; run as a normal user.")
    let fixture = try TemporaryArchive()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: fixture.fileURL.path)
      try? fixture.remove()
    }
    let original = try ArchiveCodec.encode([StorageFixtures.item()])
    try fixture.write(original)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0], ofItemAtPath: fixture.fileURL.path)
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    do {
      _ = try await store.load()
      XCTFail("Unreadable archive loaded")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    do {
      _ = try await store.create(StorageFixtures.item())
      XCTFail("Create succeeded after unreadable load")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readBlocked)
    }
    do {
      _ = try await store.update(StorageFixtures.item(), expectedRevision: 0)
      XCTFail("Update succeeded after unreadable load")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readBlocked)
    }
    let state = await store.state()
    XCTAssertEqual(state, .readFailed(.readFailed, lastCommitted: nil))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: fixture.fileURL.path)
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
  }

  func testFailedReloadPreservesLastCommittedAndRetryIncrementsOnlyOnSuccess() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let original = try ArchiveCodec.encode([StorageFixtures.item()])
    try fixture.write(original)
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let before = try await store.load()
    let corrupt = Data("external corruption".utf8)
    try fixture.write(corrupt)
    do {
      _ = try await store.load()
      XCTFail("Corrupt reload succeeded")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    let failed = await store.state()
    XCTAssertEqual(failed, .readFailed(.readFailed, lastCommitted: before))
    do {
      _ = try await store.create(StorageFixtures.item())
      XCTFail("Read-blocked store accepted a write")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readBlocked)
    }
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), corrupt)
    try fixture.write(original)
    let retried = try await store.load()
    XCTAssertEqual(retried.records, before.records)
    XCTAssertEqual(retried.revision, before.revision + 1)
    let committed = try await store.create(StorageFixtures.item())
    XCTAssertEqual(committed.revision, retried.revision + 1)
  }

  func testNormalizedCreateSurvivesRestartWithMoneyAndCreditLedger() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let repository = ReturnRepository(fileURL: fixture.fileURL)
    let store = ReturnStore(persistence: repository)
    _ = try await store.load()
    var item = StorageFixtures.item()
    item.title = "  Running shoes\n"
    item.merchant = " Example Store "
    item.purchasePriceCents = 0
    item.returnBy = try CalendarDay(iso8601: "2026-10-06")
    let day = try CalendarDay(iso8601: "2026-10-01")
    item.reimbursements = [
      Reimbursement(returnItemID: item.id, date: day, amountCents: 5_000, kind: .money),
      Reimbursement(returnItemID: item.id, date: day, amountCents: 3_000, kind: .storeCredit),
    ]
    let committed = try await store.create(item)
    XCTAssertEqual(committed.records, [try item.validated()])
    let restarted = ReturnStore(persistence: repository)
    let reloaded = try await restarted.load()
    XCTAssertEqual(reloaded.records, committed.records)
    XCTAssertEqual(reloaded.revision, 1)
    XCTAssertNil(reloaded.records[0].expectedRefundCents)
    XCTAssertEqual(try reloaded.records[0].moneyReceivedCents(), 5_000)
    XCTAssertEqual(try reloaded.records[0].storeCreditCents(), 3_000)
  }

  func testAtomicFailuresPreserveCommittedMemoryRevisionAndDisk() async throws {
    let stages: [ReturnRepository.WriteStage] = [.stage, .protection, .replacement]
    for stage in stages {
      let fixture = try TemporaryArchive()
      defer { try? fixture.remove() }
      let original = try ArchiveCodec.encode([StorageFixtures.item()])
      try fixture.write(original)
      let repository = StorageFixtures.failingRepository(fileURL: fixture.fileURL, stage: stage)
      let store = ReturnStore(persistence: repository)
      let before = try await store.load()
      do {
        _ = try await store.create(StorageFixtures.item())
        XCTFail("Injected write failure succeeded")
      } catch {
        XCTAssertEqual(error as? ReturnStoreFailure, .writeFailed)
      }
      let state = await store.state()
      XCTAssertEqual(state, .ready(before))
      XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
      XCTAssertEqual(
        try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path),
        ["archive.json"])
    }
  }

  func testWriteFailureAllowsSameStoreRetryAfterCauseRemoved() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let gate = fixture.directory.appendingPathComponent("fail-replacement")
    try Data().write(to: gate)
    let repository = ReturnRepository(fileURL: fixture.fileURL) { stage in
      if case .replacement = stage, FileManager.default.fileExists(atPath: gate.path) {
        throw StorageFixtures.InjectedFailure.precommit
      }
    }
    let store = ReturnStore(persistence: repository)
    let before = try await store.load()
    let item = StorageFixtures.item()
    do {
      _ = try await store.create(item)
      XCTFail("Injected failure succeeded")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .writeFailed)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    try FileManager.default.removeItem(at: gate)
    let retried = try await store.create(item)
    XCTAssertEqual(retried.records, [item])
    XCTAssertEqual(retried.revision, before.revision + 1)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.fileURL)), [item])
  }

  func testInvalidAndDuplicateCandidatesNeverReachDisk() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    _ = try await store.load()
    var first = StorageFixtures.item()
    let eventID = UUID()
    let day = try CalendarDay(iso8601: "2026-10-01")
    first.reimbursements = [
      Reimbursement(id: eventID, returnItemID: first.id, date: day, amountCents: 500, kind: .money)
    ]
    let before = try await store.create(first)
    let bytes = try Data(contentsOf: fixture.fileURL)
    var blank = StorageFixtures.item()
    blank.title = " \n"
    var repeatedEvent = StorageFixtures.item()
    repeatedEvent.reimbursements = [
      Reimbursement(
        id: eventID, returnItemID: repeatedEvent.id, date: day, amountCents: 500, kind: .money)
    ]
    for candidate in [blank, first, repeatedEvent] {
      do {
        _ = try await store.create(candidate)
        XCTFail("Invalid candidate was committed")
      } catch {
        XCTAssertEqual(error as? ReturnStoreFailure, .invalidRecords)
      }
      let state = await store.state()
      XCTAssertEqual(state, .ready(before))
      XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
    }
  }

  func testStaleAndMissingUpdatesPreserveLatestSnapshot() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    _ = try await store.load()
    let first = StorageFixtures.item()
    let editor = try await store.create(first)
    let latest = try await store.create(StorageFixtures.item())
    let bytes = try Data(contentsOf: fixture.fileURL)
    var stale = first
    stale.title = "Stale edit"
    do {
      _ = try await store.update(stale, expectedRevision: editor.revision)
      XCTFail("Stale edit replaced newer state")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .staleRevision)
    }
    do {
      _ = try await store.update(StorageFixtures.item(), expectedRevision: latest.revision)
      XCTFail("Missing record update succeeded")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .missingRecord)
    }
    let state = await store.state()
    XCTAssertEqual(state, .ready(latest))
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
  }

  func testEncodingOversizedCandidatePreservesCommittedMemoryAndBytes() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    func largeItem() -> ReturnItem {
      var item = StorageFixtures.item()
      item.notes = String(repeating: "x", count: 4_000)
      return item
    }
    let firstSize = try ArchiveCodec.encode([largeItem()]).count
    let step = try ArchiveCodec.encode([largeItem(), largeItem()]).count - firstSize
    let count = (ArchiveCodec.maximumArchiveBytes - firstSize) / step + 1
    let records = (0..<count).map { _ in largeItem() }
    let bytes = try ArchiveCodec.encode(records)
    XCTAssertLessThanOrEqual(bytes.count, ArchiveCodec.maximumArchiveBytes)
    XCTAssertLessThan(ArchiveCodec.maximumArchiveBytes - bytes.count, step)
    try fixture.write(bytes)
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let before = try await store.load()
    let candidate = largeItem()
    XCTAssertEqual(try candidate.validated(), candidate)
    do {
      _ = try await store.create(candidate)
      XCTFail("Oversized encoded candidate was committed")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .invalidRecords)
    }
    let state = await store.state()
    XCTAssertEqual(state, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), ["archive.json"])
  }

  func testUpdateRetainsOriginalCreatedAt() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    _ = try await store.load()
    let original = StorageFixtures.item()
    let before = try await store.create(original)
    var edit = original
    edit.title = "Edited shoes"
    edit.createdAt = original.createdAt.addingTimeInterval(60)
    edit.updatedAt = original.createdAt.addingTimeInterval(120)
    let committed = try await store.update(edit, expectedRevision: before.revision)
    XCTAssertEqual(committed.records[0].createdAt, original.createdAt)
    XCTAssertEqual(committed.records[0].updatedAt, edit.updatedAt)
    XCTAssertEqual(committed.records[0].title, edit.title)
    XCTAssertEqual(committed.revision, before.revision + 1)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.fileURL)), committed.records)
  }

  func testConcurrentCreatesNeverLoseARecord() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let before = try await store.load()
    let items = (0..<50).map { _ in StorageFixtures.item() }
    let revisions = try await withThrowingTaskGroup(of: ReturnSnapshot.self) { group in
      for item in items {
        group.addTask { try await store.create(item) }
      }
      var revisions = Set<UInt64>()
      for try await snapshot in group {
        revisions.insert(snapshot.revision)
        XCTAssertEqual(snapshot.records.count, Int(snapshot.revision - before.revision))
      }
      return revisions
    }
    let state = await store.state()
    guard case .ready(let final) = state else { return XCTFail("Store was not ready") }
    XCTAssertEqual(final.records.count, items.count)
    XCTAssertEqual(Set(final.records.map(\.id)), Set(items.map(\.id)))
    XCTAssertEqual(final.revision, before.revision + UInt64(items.count))
    XCTAssertEqual(revisions, Set((before.revision + 1)...final.revision))
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.fileURL)), final.records)
  }

  func testRawCopyInBlockedStateDoesNotRepairOrMutateState() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let bytes = Data([0xFF, 0x00, 0xA5])
    try fixture.write(bytes)
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    do {
      _ = try await store.load()
      XCTFail("Corrupt load succeeded")
    } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    let before = await store.state()
    let destination = fixture.directory.appendingPathComponent("recovery.bin")
    try await store.copyRawArchive(to: destination)
    let after = await store.state()
    XCTAssertEqual(after, before)
    XCTAssertEqual(try Data(contentsOf: destination), bytes)
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
  }

  func testRawCopyFailureDoesNotChangeReadySnapshot() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let original = try ArchiveCodec.encode([StorageFixtures.item()])
    try fixture.write(original)
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let before = try await store.load()
    do {
      try await store.copyRawArchive(to: fixture.fileURL)
      XCTFail("Copied onto the source")
    } catch {
      XCTAssertEqual(error as? ReturnPersistenceFailure, .invalidDestination)
    }
    let state = await store.state()
    XCTAssertEqual(state, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
  }

  func testRepeatedSuccessfulLoadHasMonotonicSessionRevision() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let first = try await store.load()
    let second = try await store.load()
    let third = try await store.load()
    XCTAssertEqual([first.revision, second.revision, third.revision], [1, 2, 3])
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
  }
}
