import Foundation
import ReturnQueueCore
import ReturnQueuePresentation
import ReturnQueueStorage
import XCTest

@MainActor
final class RefundFormTests: XCTestCase {
  func testNewEventUsesLocalDayWhileEditedEventRetainsItsOriginalCalendarDay() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let revision = try XCTUnwrap(session.snapshot?.revision)
    let now = Date(timeIntervalSince1970: 84_600)
    let model = ReimbursementEditorModel(
      session: session, item: item, revision: revision, now: { now },
      timeZone: { TimeZone(secondsFromGMT: 50_400)! })
    XCTAssertEqual(model.draft.date, "1970-01-02")
    XCTAssertEqual(model.draft.amount, "")
    XCTAssertEqual(model.draft.kind, .money)
    XCTAssertEqual(model.draft.note, "")
    let event = Reimbursement(
      returnItemID: item.id, date: try CalendarDay(iso8601: "2026-09-30"), amountCents: 3_001,
      kind: .storeCredit, note: "Original event")
    let edited = ReimbursementEditorModel(
      session: session, item: item, revision: revision, event: event, now: { now },
      timeZone: { TimeZone(secondsFromGMT: -43_200)! })
    XCTAssertEqual(edited.draft, ReimbursementDraft(event: event))
    XCTAssertEqual(edited.draft.date, "2026-09-30")
    XCTAssertEqual(edited.draft.kind, .storeCredit)
  }

  func testInvalidClockLeavesRequiredDaysBlankRatherThanInventingADDates() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let revision = try XCTUnwrap(session.snapshot?.revision)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let bce = try XCTUnwrap(calendar.date(from: DateComponents(era: 0, year: 1, month: 1, day: 1)))
    let far = try XCTUnwrap(
      calendar.date(from: DateComponents(era: 1, year: 10_000, month: 1, day: 1)))
    let bytes = try Data(contentsOf: fixture.archiveURL)
    for instant in [
      bce, far, Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity),
    ] {
      let event = ReimbursementEditorModel(
        session: session, item: item, revision: revision, now: { instant },
        timeZone: { TimeZone(secondsFromGMT: 0)! })
      XCTAssertEqual(event.draft.date, "")
      event.draft.amount = "10"
      let eventSaved = await event.save()
      XCTAssertFalse(eventSaved)
      XCTAssertNotNil(event.fieldErrors[.date])
      let state = StateEditorModel(
        session: session, item: item, revision: revision, mode: .dropOff, now: { instant },
        timeZone: { TimeZone(secondsFromGMT: 0)! })
      XCTAssertEqual(state.draft.droppedOffDate, "")
      let stateSaved = await state.save()
      XCTAssertFalse(stateSaved)
      XCTAssertNotNil(state.fieldErrors[.droppedOffDate])
    }
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testEventFieldErrorsRetainEveryInputAndCannotWriteAnArchive() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let model = ReimbursementEditorModel(session: session, item: item, revision: before.revision)
    model.draft.date = "2026-02-30"
    model.draft.note = String(repeating: "é", count: 1_001)
    for amount in ["", "0", "-1", "1.001", "1000000.01"] {
      model.draft.amount = amount
      let draft = model.draft
      let saved = await model.save()
      XCTAssertFalse(saved)
      XCTAssertNotNil(model.fieldErrors[.date])
      XCTAssertNotNil(model.fieldErrors[.amount])
      XCTAssertNotNil(model.fieldErrors[.note])
      XCTAssertEqual(model.draft, draft)
    }
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testChangingAnExcessDraftInvalidatesApprovalAndCannotAuthorizeANewEvent() async throws {
    var item = PresentationFixture.item()
    item.expectedRefundCents = 0
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let eventID = UUID()
    let model = ReimbursementEditorModel(
      session: session, item: item, revision: before.revision, newEventID: eventID)
    model.draft.date = "2026-10-04"
    model.draft.amount = "30"
    let submitted = await model.save()
    XCTAssertFalse(submitted)
    XCTAssertEqual(model.action.state, .awaitingConfirmation(.excessReimbursement))
    XCTAssertEqual(model.action.pendingPreview?.summary.differenceCents, -3_000)
    model.draft.amount = "40"
    model.draft.kind = .storeCredit
    model.draft.date = "2026-10-05"
    model.draft.note = "Changed after preview"
    XCTAssertNil(model.action.pendingPreview)
    let invalidated = await model.confirmPending()
    XCTAssertFalse(invalidated)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    _ = await model.save()
    XCTAssertEqual(model.action.pendingPreview?.summary.moneyCents, 0)
    XCTAssertEqual(model.action.pendingPreview?.summary.storeCreditCents, 4_000)
    model.cancelPending()
    let cancelled = await model.confirmPending()
    XCTAssertFalse(cancelled)
    _ = await model.save()
    let confirmed = await model.confirmPending()
    XCTAssertTrue(confirmed)
    let event = try XCTUnwrap(session.snapshot?.records[0].reimbursements.first)
    XCTAssertEqual(event.id, eventID)
    XCTAssertEqual(event.amountCents, 4_000)
    XCTAssertEqual(event.kind, .storeCredit)
    XCTAssertEqual(event.date.iso8601, "2026-10-05")
    XCTAssertEqual(event.note, "Changed after preview")
    XCTAssertEqual(session.snapshot?.records[0].state, .planned)
  }

  func testStateDraftDefaultsKeepIndependentDatesAndClosureOutcomeIsNeverInferred() async throws {
    var item = PresentationFixture.item()
    item.droppedOffDate = try CalendarDay(iso8601: "2026-10-02")
    item.expectedRefundDate = try CalendarDay(iso8601: "2026-10-20")
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let revision = try XCTUnwrap(session.snapshot?.revision)
    let model = StateEditorModel(session: session, item: item, revision: revision, mode: .dropOff)
    XCTAssertEqual(model.draft.droppedOffDate, "2026-10-02")
    XCTAssertEqual(model.draft.expectedRefundDate, "2026-10-20")
    let close = StateEditorModel(session: session, item: item, revision: revision, mode: .close)
    XCTAssertNil(close.draft.closureOutcome)
    let saved = await close.save()
    XCTAssertFalse(saved)
    XCTAssertNotNil(close.fieldErrors[.closureOutcome])
    XCTAssertNil(close.action.pendingPreview)
  }

  func testChangedClosureDraftCannotReuseStateConfirmationAndPreservesPriorNote() async throws {
    var item = PresentationFixture.item()
    item.state = .closed
    item.expectedRefundCents = 10_000
    item.closureOutcome = .denied
    item.closureNote = "Original denial"
    item.notes = "Original notes"
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let model = StateEditorModel(
      session: session, item: item, revision: before.revision, mode: .correct)
    XCTAssertEqual(model.draft.closureOutcome, .denied)
    XCTAssertEqual(model.draft.closureNote, "Original denial")
    model.draft.closureOutcome = .partialRefund
    model.draft.closureNote = "  New explanation  "
    _ = await model.save()
    XCTAssertEqual(model.action.state, .awaitingConfirmation(.stateChange))
    model.draft.closureNote = "Changed explanation"
    XCTAssertNil(model.action.pendingPreview)
    let invalidated = await model.confirmPending()
    XCTAssertFalse(invalidated)
    XCTAssertEqual(session.snapshot, before)
    _ = await model.save()
    let confirmed = await model.confirmPending()
    XCTAssertTrue(confirmed)
    let saved = try XCTUnwrap(session.snapshot?.records[0])
    XCTAssertEqual(saved.closureNote, "Changed explanation")
    XCTAssertEqual(saved.notes, "Original notes\n\nPrevious closure explanation: Original denial")
    XCTAssertEqual(saved.createdAt, item.createdAt)
  }

  func testClosedEventEditWithoutExplanationFailsAndRetainsTheDraft() async throws {
    var item = PresentationFixture.item()
    item.expectedRefundCents = 3_000
    item.state = .closed
    item.closureOutcome = .fullRefund
    let event = Reimbursement(
      returnItemID: item.id, date: try CalendarDay(iso8601: "2026-10-04"), amountCents: 3_000,
      kind: .money)
    item.reimbursements = [event]
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let model = ReimbursementEditorModel(
      session: session, item: item, revision: before.revision, event: event)
    model.draft.amount = "20"
    let draft = model.draft
    let saved = await model.save()
    XCTAssertFalse(saved)
    guard case .failed(let message) = model.action.state else {
      return XCTFail("Invalid closed ledger not surfaced")
    }
    XCTAssertTrue(message.contains("Edit the closure explanation or reopen this return first."))
    XCTAssertEqual(model.draft, draft)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testItemEditorExcessWarningBindsCandidateAndChangingDraftOrCancelInvalidatesIt() async throws
  {
    var item = PresentationFixture.item()
    item.reimbursements = [
      Reimbursement(
        returnItemID: item.id, date: try CalendarDay(iso8601: "2026-10-04"), amountCents: 3_000,
        kind: .money)
    ]
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let model = ReturnEditorModel(session: session, item: item, revision: before.revision)
    model.draft.expectedRefund = "0"
    let submitted = await model.save()
    XCTAssertFalse(submitted)
    XCTAssertEqual(model.saveState, .awaitingConfirmation)
    XCTAssertEqual(model.pendingSummary?.differenceCents, -3_000)
    model.draft.title = "Changed title"
    XCTAssertNil(model.pendingSummary)
    let invalidated = await model.confirmPendingSave()
    XCTAssertFalse(invalidated)
    XCTAssertEqual(session.snapshot, before)
    _ = await model.save()
    model.cancelPendingSave()
    XCTAssertNil(model.pendingSummary)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    _ = await model.save()
    let confirmed = await model.confirmPendingSave()
    XCTAssertTrue(confirmed)
    XCTAssertEqual(session.snapshot?.records[0].title, "Changed title")
    XCTAssertEqual(session.snapshot?.records[0].expectedRefundCents, 0)
    XCTAssertEqual(session.snapshot?.records[0].reimbursements, item.reimbursements)
  }

  func testItemEditorStaleExcessApprovalCannotOverwriteANewerSnapshot() async throws {
    var item = PresentationFixture.item()
    item.reimbursements = [
      Reimbursement(
        returnItemID: item.id, date: try CalendarDay(iso8601: "2026-10-04"), amountCents: 1,
        kind: .money)
    ]
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let model = ReturnEditorModel(
      session: session, item: item, revision: try XCTUnwrap(session.snapshot?.revision))
    model.draft.expectedRefund = "0"
    _ = await model.save()
    _ = try await session.create(PresentationFixture.item())
    let latest = session.snapshot
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let confirmed = await model.confirmPendingSave()
    XCTAssertFalse(confirmed)
    XCTAssertNil(model.pendingSummary)
    XCTAssertEqual(session.snapshot, latest)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    XCTAssertEqual(model.draft.expectedRefund, "0")
  }
}
