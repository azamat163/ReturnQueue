import Foundation
import ReturnQueueCore
import ReturnQueueStorage
import XCTest

final class MutationTests: XCTestCase {
  func testSemanticCommandsPersistTheManualPartialClosureAcrossANewStore() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    var original = StorageFixtures.item()
    original.expectedRefundCents = 10_000
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    _ = try await store.load()
    var snapshot = try await store.create(original)
    let day = try CalendarDay(iso8601: "2026-10-04")
    let money = Reimbursement(
      returnItemID: original.id, date: day, amountCents: 5_000, kind: .money)
    let credit = Reimbursement(
      returnItemID: original.id, date: day, amountCents: 3_000, kind: .storeCredit)
    for command in [
      ReturnMutation.dropOff(date: day, expectedRefundDate: nil),
      .addReimbursement(money), .addReimbursement(credit),
      .close(outcome: .partialRefund, note: "Accepted $20 difference"),
    ] {
      snapshot = try await store.mutate(
        itemID: original.id, command: command, expectedRevision: snapshot.revision,
        updatedAt: StorageFixtures.instant.addingTimeInterval(60), confirmation: .confirmed)
    }
    let relaunched = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let restored = try await relaunched.load()
    XCTAssertEqual(restored.records, snapshot.records)
    let closed = try XCTUnwrap(restored.records.first)
    XCTAssertEqual(closed.state, .closed)
    XCTAssertEqual(closed.closureOutcome, .partialRefund)
    XCTAssertEqual(closed.closureNote, "Accepted $20 difference")
    XCTAssertEqual(closed.reimbursements, [money, credit])
    XCTAssertEqual(try RefundSummary(item: closed).differenceCents, 2_000)
    XCTAssertEqual(closed.createdAt, original.createdAt)
  }

  func testConfirmationAndDomainFailuresPreserveBytesSnapshotAndRevision() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    var original = StorageFixtures.item()
    original.expectedRefundCents = 0
    try fixture.write(ArchiveCodec.encode([original]))
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let before = try await store.load()
    let bytes = try Data(contentsOf: fixture.fileURL)
    let event = Reimbursement(
      returnItemID: original.id, date: try CalendarDay(iso8601: "2026-10-04"), amountCents: 1,
      kind: .money)
    for command in [ReturnMutation.keep, .addReimbursement(event)] {
      do {
        _ = try await store.mutate(
          itemID: original.id, command: command, expectedRevision: before.revision,
          updatedAt: StorageFixtures.instant)
        XCTFail("Unconfirmed mutation committed")
      } catch {
        XCTAssertNotNil(error as? ReturnTransitionFailure)
      }
      let state = await store.state()
      XCTAssertEqual(state, .ready(before))
      XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
    }
    do {
      _ = try await store.mutate(
        itemID: original.id, command: .deleteReimbursement(UUID()),
        expectedRevision: before.revision, updatedAt: StorageFixtures.instant,
        confirmation: .confirmed)
      XCTFail("Missing reimbursement committed")
    } catch {
      XCTAssertEqual(error as? ReturnTransitionFailure, .missingReimbursement)
    }
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
  }

  func testRevisionAndReadinessChecksPrecedeCommandValidation() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let item = StorageFixtures.item()
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    do {
      _ = try await store.mutate(
        itemID: item.id, command: .deleteReimbursement(UUID()), expectedRevision: 0,
        updatedAt: .distantPast)
      XCTFail("Not-loaded mutation succeeded")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .notLoaded) }
    _ = try await store.load()
    let before = try await store.create(item)
    do {
      _ = try await store.mutate(
        itemID: item.id, command: .deleteReimbursement(UUID()),
        expectedRevision: before.revision - 1, updatedAt: .distantPast)
      XCTFail("Stale command succeeded")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .staleRevision) }
    do {
      _ = try await store.mutate(
        itemID: UUID(), command: .deleteReimbursement(UUID()), expectedRevision: before.revision,
        updatedAt: .distantPast)
      XCTFail("Missing return succeeded")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .missingRecord) }
    let corrupt = Data("corrupt".utf8)
    try fixture.write(corrupt)
    do { _ = try await store.load() } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    do {
      _ = try await store.mutate(
        itemID: item.id, command: .keep, expectedRevision: before.revision,
        updatedAt: StorageFixtures.instant, confirmation: .confirmed)
      XCTFail("Blocked mutation succeeded")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .readBlocked) }
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), corrupt)
  }

  func testFailedAtomicMutationPreservesOldStateEventsAndAllowsRetry() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let original = StorageFixtures.item()
    try fixture.write(ArchiveCodec.encode([original]))
    let marker = fixture.directory.appendingPathComponent("fail")
    try Data().write(to: marker)
    let store = ReturnStore(
      persistence: ReturnRepository(fileURL: fixture.fileURL) { stage in
        if stage == .replacement, FileManager.default.fileExists(atPath: marker.path) {
          throw ReturnPersistenceFailure.writeFailed
        }
      })
    let before = try await store.load()
    let bytes = try Data(contentsOf: fixture.fileURL)
    do {
      _ = try await store.mutate(
        itemID: original.id, command: .keep, expectedRevision: before.revision,
        updatedAt: StorageFixtures.instant, confirmation: .confirmed)
      XCTFail("Injected failed write succeeded")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .writeFailed) }
    let state = await store.state()
    XCTAssertEqual(state, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
    try FileManager.default.removeItem(at: marker)
    let after = try await store.mutate(
      itemID: original.id, command: .keep, expectedRevision: before.revision,
      updatedAt: StorageFixtures.instant, confirmation: .confirmed)
    XCTAssertEqual(after.revision, before.revision + 1)
    XCTAssertEqual(after.records[0].state, .kept)
    XCTAssertEqual(after.records[0].createdAt, original.createdAt)
  }

  func testArchiveWideDuplicateEventRejectsAValidLocalCommandBeforeWriting() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let first = StorageFixtures.item()
    var second = StorageFixtures.item()
    let eventID = UUID()
    second.reimbursements = [
      Reimbursement(
        id: eventID, returnItemID: second.id, date: try CalendarDay(iso8601: "2026-10-04"),
        amountCents: 100, kind: .money)
    ]
    try fixture.write(ArchiveCodec.encode([first, second]))
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let before = try await store.load()
    let bytes = try Data(contentsOf: fixture.fileURL)
    let event = Reimbursement(
      id: eventID, returnItemID: first.id, date: second.reimbursements[0].date, amountCents: 200,
      kind: .storeCredit)
    do {
      _ = try await store.mutate(
        itemID: first.id, command: .addReimbursement(event), expectedRevision: before.revision,
        updatedAt: StorageFixtures.instant)
      XCTFail("Cross-record duplicate event committed")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .invalidRecords) }
    let state = await store.state()
    XCTAssertEqual(state, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
  }

  func testExpectedAmountUpdateRequiresConfirmationButUnrelatedExcessEditDoesNot() async throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    var original = StorageFixtures.item()
    original.reimbursements = [
      Reimbursement(
        returnItemID: original.id, date: try CalendarDay(iso8601: "2026-10-04"), amountCents: 300,
        kind: .money)
    ]
    try fixture.write(ArchiveCodec.encode([original]))
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.fileURL))
    let before = try await store.load()
    let bytes = try Data(contentsOf: fixture.fileURL)
    var candidate = original
    candidate.expectedRefundCents = 0
    do {
      _ = try await store.update(candidate, expectedRevision: before.revision)
      XCTFail("Unknown-to-zero excess update committed unconfirmed")
    } catch {
      XCTAssertEqual(error as? ReturnTransitionFailure, .confirmationRequired(.excessReimbursement))
    }
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
    let confirmed = try await store.update(
      candidate, expectedRevision: before.revision, confirmation: .confirmed)
    candidate.title = "Unrelated edit"
    // Caller creation metadata is replaced with the saved value before domain validation.
    candidate.createdAt = Date(timeIntervalSince1970: .nan)
    let unrelated = try await store.update(candidate, expectedRevision: confirmed.revision)
    XCTAssertEqual(unrelated.records[0].createdAt, original.createdAt)
    XCTAssertEqual(unrelated.records[0].expectedRefundCents, 0)
    XCTAssertEqual(unrelated.records[0].reimbursements, original.reimbursements)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.fileURL)), unrelated.records)
  }
}
