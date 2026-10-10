import Foundation
import ReturnQueueCore
import ReturnQueuePresentation
import ReturnQueueStorage
import XCTest

@MainActor
final class RefundActionTests: XCTestCase {
  func testPreviewCancelAndConfirmPublishOnlyTheFrozenDurableCommand() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let model = RefundActionModel(session: session, item: item, revision: before.revision)
    let date = try CalendarDay(iso8601: "2026-10-04")
    let submitted = await model.submit(
      .dropOff(date: date, expectedRefundDate: nil), updatedAt: PresentationFixture.instant)
    XCTAssertFalse(submitted)
    XCTAssertEqual(model.state, .awaitingConfirmation(.stateChange))
    XCTAssertEqual(model.pendingPreview?.item.droppedOffDate, date)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    model.cancelPending()
    XCTAssertNil(model.pendingPreview)
    let cancelled = await model.confirmPending()
    XCTAssertFalse(cancelled)
    XCTAssertEqual(session.snapshot, before)
    _ = await model.submit(
      .dropOff(date: date, expectedRefundDate: nil), updatedAt: PresentationFixture.instant)
    let confirmed = await model.confirmPending()
    XCTAssertTrue(confirmed)
    XCTAssertEqual(model.state, .saved)
    XCTAssertEqual(session.snapshot?.records[0].state, .droppedOff)
    XCTAssertEqual(session.snapshot?.records[0].droppedOffDate, date)
    XCTAssertEqual(session.snapshot?.revision, before.revision + 1)
    XCTAssertEqual(
      try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), session.snapshot?.records)
    let duplicate = await model.confirmPending()
    XCTAssertFalse(duplicate)
    XCTAssertEqual(session.snapshot?.revision, before.revision + 1)
  }

  func testStaleConfirmationClearsApprovalAndCannotRebindAfterReload() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let model = RefundActionModel(
      session: session, item: item, revision: try XCTUnwrap(session.snapshot?.revision))
    _ = await model.submit(.keep, updatedAt: PresentationFixture.instant)
    _ = try await session.create(PresentationFixture.item())
    let latest = session.snapshot
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let confirmed = await model.confirmPending()
    XCTAssertFalse(confirmed)
    XCTAssertNil(model.pendingPreview)
    guard case .failed = model.state else { return XCTFail("Stale failure not visible") }
    XCTAssertEqual(session.snapshot, latest)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    try await session.load()
    let afterReload = session.snapshot
    _ = await model.submit(.keep, updatedAt: PresentationFixture.instant)
    let retry = await model.confirmPending()
    XCTAssertFalse(retry)
    XCTAssertEqual(session.snapshot, afterReload)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testTypedValidationAndTransitionFailuresDoNotAlterSharedState() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    do {
      _ = try await session.mutate(
        itemID: item.id, command: .keep, expectedRevision: before.revision,
        updatedAt: PresentationFixture.instant)
      XCTFail("Unconfirmed action succeeded")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .transition(.confirmationRequired(.stateChange)))
    }
    let invalid = Reimbursement(
      returnItemID: item.id, date: try CalendarDay(iso8601: "2026-10-04"), amountCents: 0,
      kind: .money)
    do {
      _ = try await session.mutate(
        itemID: item.id, command: .addReimbursement(invalid), expectedRevision: before.revision,
        updatedAt: PresentationFixture.instant)
      XCTFail("Invalid amount succeeded")
    } catch { XCTAssertEqual(error as? SessionFailure, .validation(.invalidAmount)) }
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(session.activity, .idle)
  }

  func testFailureRetainsCommandDraftAndBytesAndRetryCommitsOnce() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let marker = fixture.directory.appendingPathComponent("fail")
    try Data().write(to: marker)
    let repository = ReturnRepository(fileURL: fixture.archiveURL) { stage in
      if stage == .replacement, FileManager.default.fileExists(atPath: marker.path) {
        throw ReturnPersistenceFailure.writeFailed
      }
    }
    let session = fixture.session(persistence: repository)
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let editor = ReimbursementEditorModel(
      session: session, item: item, revision: before.revision, now: { PresentationFixture.instant },
      timeZone: { TimeZone(secondsFromGMT: 0)! })
    editor.draft.amount = "30.25"
    editor.draft.note = "Keep this draft"
    let draft = editor.draft
    let saved = await editor.save()
    XCTAssertFalse(saved)
    guard case .failed = editor.action.state else { return XCTFail("Write failure not visible") }
    XCTAssertEqual(editor.draft, draft)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    try FileManager.default.removeItem(at: marker)
    let retried = await editor.save()
    XCTAssertTrue(retried)
    XCTAssertEqual(session.snapshot?.revision, before.revision + 1)
    XCTAssertEqual(session.snapshot?.records[0].reimbursements.count, 1)
    XCTAssertEqual(session.snapshot?.records[0].reimbursements[0].amountCents, 3_025)
  }

  func testSavingGateRejectsConcurrentActionsAndCancellationAfterEntryStillPublishes() async throws
  {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let gate = PresentationGate()
    defer { gate.release.signal() }
    let session = fixture.session(persistence: gate.repository(at: fixture.archiveURL))
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let model = RefundActionModel(session: session, item: item, revision: before.revision)
    _ = await model.submit(.keep, updatedAt: PresentationFixture.instant)
    let task = Task { await model.confirmPending() }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    XCTAssertEqual(session.activity, .saving)
    XCTAssertEqual(session.snapshot, before)
    let duplicate = await model.confirmPending()
    XCTAssertFalse(duplicate)
    do {
      _ = try await session.mutate(
        itemID: item.id, command: .reopenToReturn, expectedRevision: before.revision,
        updatedAt: PresentationFixture.instant, confirmation: .confirmed)
      XCTFail("Busy action succeeded")
    } catch { XCTAssertEqual(error as? SessionFailure, .busy) }
    task.cancel()
    gate.release.signal()
    let saved = await task.value
    XCTAssertTrue(saved)
    XCTAssertEqual(session.snapshot?.records[0].state, .kept)
    XCTAssertEqual(session.snapshot?.revision, before.revision + 1)
    XCTAssertEqual(session.activity, .idle)
    XCTAssertEqual(
      try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), session.snapshot?.records)
  }

  func testAlreadyCancelledSubmissionAndConfirmationNeverEnterTheStore() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let model = RefundActionModel(session: session, item: item, revision: before.revision)
    let event = Reimbursement(
      returnItemID: item.id, date: try CalendarDay(iso8601: "2026-10-04"), amountCents: 30,
      kind: .money)
    let cancelledSubmit = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      return await model.submit(.addReimbursement(event), updatedAt: PresentationFixture.instant)
    }
    let submitted = await cancelledSubmit.value
    XCTAssertFalse(submitted)
    _ = await model.submit(.keep, updatedAt: PresentationFixture.instant)
    let cancelledConfirm = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      return await model.confirmPending()
    }
    let confirmed = await cancelledConfirm.value
    XCTAssertFalse(confirmed)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testFailedReadRetainsProjectionsAndBlocksNewCommands() async throws {
    var item = PresentationFixture.item()
    item.state = .droppedOff
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    let model = RefundsViewModel(session: session)
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let corrupt = Data("broken original".utf8)
    try corrupt.write(to: fixture.archiveURL)
    do { try await session.load() } catch {
      XCTAssertEqual(error as? SessionFailure, .store(.readFailed))
    }
    XCTAssertEqual(model.waitingItems, [item])
    XCTAssertEqual(model.waitingCount, 1)
    XCTAssertEqual(model.historyCount, 0)
    XCTAssertFalse(session.canEdit)
    do {
      _ = try await session.mutate(
        itemID: item.id, command: .keep, expectedRevision: before.revision,
        updatedAt: PresentationFixture.instant, confirmation: .confirmed)
      XCTFail("Read-blocked command succeeded")
    } catch { XCTAssertEqual(error as? SessionFailure, .notReady) }
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), corrupt)
  }

  func testWaitingHistoryFilterAndDeterministicOrderFollowLatestCommittedState() async throws {
    let day = try CalendarDay(iso8601: "2026-10-04")
    var waiting = PresentationFixture.item()
    waiting.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    waiting.state = .droppedOff
    waiting.droppedOffDate = day
    var unknown = waiting
    unknown.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    unknown.droppedOffDate = nil
    var closed = waiting
    closed.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    closed.state = .closed
    closed.closureOutcome = .denied
    var kept = closed
    kept.id = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    kept.state = .kept
    kept.closureOutcome = nil
    kept.updatedAt = closed.updatedAt.addingTimeInterval(1)
    let planned = PresentationFixture.item()
    let records = [unknown, kept, planned, closed, waiting]
    let fixture = try PresentationFixture(records: records)
    defer { try? fixture.remove() }
    let session = fixture.session()
    let model = RefundsViewModel(session: session)
    try await session.load()
    XCTAssertEqual(model.waitingItems.map(\.id), [waiting.id, unknown.id])
    XCTAssertEqual(model.historyItems.map(\.id), [kept.id, closed.id])
    XCTAssertEqual(model.waitingCount, 2)
    XCTAssertEqual(model.historyCount, 2)
    let before = try XCTUnwrap(session.snapshot)
    _ = try await session.mutate(
      itemID: waiting.id, command: .keep, expectedRevision: before.revision,
      updatedAt: kept.updatedAt.addingTimeInterval(1), confirmation: .confirmed)
    XCTAssertEqual(model.waitingItems.map(\.id), [unknown.id])
    XCTAssertEqual(model.historyItems.map(\.id), [waiting.id, kept.id, closed.id])
    XCTAssertEqual(model.waitingCount, 1)
    XCTAssertEqual(model.historyCount, 3)
    XCTAssertEqual(session.snapshot?.records.count, 5)
  }
}
