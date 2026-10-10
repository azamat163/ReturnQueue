import Foundation
import ReturnQueueCore
import XCTest

final class RefundTests: XCTestCase {
  private let changedAt = CoreFixtures.instant.addingTimeInterval(60)

  func testSummarySeparatesMoneyCreditAndDifferenceWithoutUsingPurchasePrice() throws {
    var item = ledger()
    item.purchasePriceCents = 99_999
    let summary = try RefundSummary(item: item)
    XCTAssertEqual(summary.moneyCents, 5_000)
    XCTAssertEqual(summary.storeCreditCents, 3_000)
    XCTAssertEqual(summary.expectedRefundCents, 10_000)
    XCTAssertEqual(summary.differenceCents, 2_000)
    XCTAssertFalse(summary.isExcess)
    item.expectedRefundCents = nil
    XCTAssertNil(try RefundSummary(item: item).differenceCents)
    XCTAssertFalse(try RefundSummary(item: item).isExcess)
    item.expectedRefundCents = 0
    XCTAssertEqual(try RefundSummary(item: item).differenceCents, -8_000)
    XCTAssertTrue(try RefundSummary(item: item).isExcess)
  }

  func testSummaryAllowsTotalsAboveEventLimitButRejectsInvalidArithmeticInputs() throws {
    var item = ledger()
    item.expectedRefundCents = nil
    item.reimbursements[0].amountCents = 100_000_000
    item.reimbursements[1].amountCents = 100_000_000
    let summary = try RefundSummary(item: item)
    XCTAssertEqual(summary.moneyCents, 100_000_000)
    XCTAssertEqual(summary.storeCreditCents, 100_000_000)
    item.reimbursements[0].amountCents = Int.max
    XCTAssertThrowsError(try RefundSummary(item: item))
    item = ledger()
    item.reimbursements[0].returnItemID = UUID()
    XCTAssertThrowsError(try RefundSummary(item: item))
    item = ledger()
    item.currency = "EUR"
    XCTAssertThrowsError(try RefundSummary(item: item))
  }

  func testDropOffRequiresConfirmationAndNeverChangesTheInputOrLedger() throws {
    let original = ledger()
    let day = try CalendarDay(iso8601: "2026-10-03")
    let refundDay = try CalendarDay(iso8601: "2026-10-20")
    let command = ReturnMutation.dropOff(date: day, expectedRefundDate: refundDay)
    let preview = try ReturnTransitions.preview(command, to: original, updatedAt: changedAt)
    XCTAssertEqual(preview.confirmationReason, .stateChange)
    XCTAssertEqual(preview.item.state, .droppedOff)
    XCTAssertEqual(preview.item.droppedOffDate, day)
    XCTAssertEqual(preview.item.expectedRefundDate, refundDay)
    XCTAssertThrowsError(
      try ReturnTransitions.applying(command, to: original, updatedAt: changedAt)
    ) {
      XCTAssertEqual($0 as? ReturnTransitionFailure, .confirmationRequired(.stateChange))
    }
    let applied = try apply(command, original)
    XCTAssertEqual(applied, preview.item)
    assertRetained(applied, from: original)
    XCTAssertEqual(original.state, .planned)
    XCTAssertNil(original.droppedOffDate)
    XCTAssertEqual(original.updatedAt, CoreFixtures.instant)
    XCTAssertThrowsError(try apply(command, applied)) {
      XCTAssertEqual($0 as? ReturnTransitionFailure, .invalidStateAction)
    }
  }

  func testPartialClosureIsManualAndDoesNotManufactureAReimbursement() throws {
    var original = ledger()
    original.state = .droppedOff
    let command = ReturnMutation.close(outcome: .partialRefund, note: "  Accepted a $20 fee  ")
    let preview = try ReturnTransitions.preview(command, to: original, updatedAt: changedAt)
    XCTAssertEqual(preview.summary.differenceCents, 2_000)
    XCTAssertEqual(preview.confirmationReason, .stateChange)
    XCTAssertEqual(preview.item.closureNote, "Accepted a $20 fee")
    XCTAssertEqual(preview.item.closureOutcome, .partialRefund)
    XCTAssertEqual(preview.item.state, .closed)
    XCTAssertEqual(preview.item.reimbursements, original.reimbursements)
    XCTAssertEqual(try apply(command, original), preview.item)
    XCTAssertEqual(original.state, .droppedOff)
    XCTAssertThrowsError(try apply(.close(outcome: .partialRefund, note: " \n"), original)) {
      XCTAssertEqual($0 as? ReturnQueueError, .missingClosureNote)
    }
  }

  func testFullLedgerDoesNotAutoCloseAndUnknownClosureNeedsManualConfirmation() throws {
    var item = CoreFixtures.item()
    item.expectedRefundCents = 5_000
    let candidate = try ReturnTransitions.applying(
      .addReimbursement(CoreFixtures.event()), to: item, updatedAt: changedAt)
    XCTAssertEqual(candidate.state, .planned)
    XCTAssertNil(candidate.closureOutcome)
    item.expectedRefundCents = nil
    for outcome in ClosureOutcome.allCases {
      let command = ReturnMutation.close(outcome: outcome, note: nil)
      let preview = try ReturnTransitions.preview(command, to: item, updatedAt: changedAt)
      XCTAssertNil(preview.summary.differenceCents)
      XCTAssertEqual(preview.confirmationReason, .stateChange)
      XCTAssertEqual(try apply(command, item).reimbursements, [])
    }
  }

  func testKeepAndReopenPreserveDaysLedgerPriorExplanationAndIdentity() throws {
    var item = try apply(.close(outcome: .partialRefund, note: "Accepted fee"), ledger())
    item.droppedOffDate = try CalendarDay(iso8601: "2026-10-02")
    item.expectedRefundDate = try CalendarDay(iso8601: "2026-10-22")
    for command in [ReturnMutation.keep, .reopenToReturn] {
      let candidate = try apply(command, item)
      assertRetained(candidate, from: item)
      XCTAssertNil(candidate.closureOutcome)
      XCTAssertEqual(candidate.closureNote, "Accepted fee")
      XCTAssertEqual(candidate.droppedOffDate, item.droppedOffDate)
      XCTAssertEqual(candidate.expectedRefundDate, item.expectedRefundDate)
    }
    let date = try CalendarDay(iso8601: "2026-09-30")
    let waiting = try apply(.reopenWaiting(date: date, expectedRefundDate: nil), item)
    XCTAssertEqual(waiting.state, .droppedOff)
    XCTAssertEqual(waiting.droppedOffDate, date)
    XCTAssertNil(waiting.expectedRefundDate)
    XCTAssertEqual(waiting.closureNote, item.closureNote)
    assertRetained(waiting, from: item)
  }

  func testAllStateCommandsRequireExplicitConfirmationEvenForAnUnchangedState() throws {
    let item = ledger()
    let commands: [ReturnMutation] = [
      .keep, .reopenToReturn,
      .reopenWaiting(date: CoreFixtures.eventDay, expectedRefundDate: nil),
      .close(outcome: .denied, note: "Denied remainder"),
    ]
    for command in commands {
      XCTAssertThrowsError(try ReturnTransitions.applying(command, to: item, updatedAt: changedAt))
      {
        XCTAssertEqual($0 as? ReturnTransitionFailure, .confirmationRequired(.stateChange))
      }
    }
    XCTAssertEqual(item, ledger())
  }

  func testReplacingOrClearingClosureExplanationPreservesHistoryAndUnchangedDoesNotDuplicate()
    throws
  {
    let closed = try apply(.close(outcome: .partialRefund, note: "Old fee"), ledger())
    let unchanged = try apply(.close(outcome: .denied, note: " Old fee "), closed)
    XCTAssertEqual(unchanged.notes, closed.notes)
    let replacement = try apply(.close(outcome: .partialRefund, note: "New fee"), closed)
    XCTAssertEqual(replacement.notes, "Bring box\n\nPrevious closure explanation: Old fee")
    XCTAssertEqual(replacement.closureNote, "New fee")
    var balanced = closed
    balanced.expectedRefundCents = 8_000
    let cleared = try apply(.close(outcome: .fullRefund, note: nil), balanced)
    XCTAssertNil(cleared.closureNote)
    XCTAssertEqual(cleared.notes, replacement.notes)
    var noNotes = closed
    noNotes.notes = ""
    XCTAssertEqual(
      try apply(.close(outcome: .denied, note: "New fee"), noNotes).notes,
      "Previous closure explanation: Old fee")
  }

  func testClosureHistoryLimitAcceptsExactBoundaryAndRejectsWithoutTruncation() throws {
    var closed = try apply(.close(outcome: .partialRefund, note: "Old"), ledger())
    let suffix = "\n\nPrevious closure explanation: Old"
    closed.notes = String(repeating: "é", count: 4_000 - suffix.count)
    let original = closed
    let candidate = try apply(.close(outcome: .denied, note: "New"), closed)
    XCTAssertEqual(candidate.notes.count, 4_000)
    closed.notes += "é"
    XCTAssertThrowsError(try apply(.close(outcome: .denied, note: "New"), closed)) {
      XCTAssertEqual($0 as? ReturnTransitionFailure, .historyNotesTooLong)
    }
    XCTAssertEqual(closed.notes, original.notes + "é")
    XCTAssertEqual(closed.closureNote, "Old")
  }

  func testEventEditsPreservePositionAndIdentityAndDeleteOnlyTheChosenEvent() throws {
    let item = ledger()
    var edited = item.reimbursements[0]
    edited.kind = .storeCredit
    edited.amountCents = 2_000
    edited.date = try CalendarDay(iso8601: "2026-09-29")
    edited.note = " Corrected card  "
    let changed = try ReturnTransitions.applying(
      .editReimbursement(edited), to: item, updatedAt: changedAt)
    XCTAssertEqual(changed.reimbursements.map(\.id), item.reimbursements.map(\.id))
    XCTAssertEqual(changed.reimbursements[0].note, "Corrected card")
    XCTAssertEqual(changed.reimbursements[0].returnItemID, item.id)
    XCTAssertEqual(try RefundSummary(item: changed).moneyCents, 0)
    XCTAssertEqual(try RefundSummary(item: changed).storeCreditCents, 5_000)
    let command = ReturnMutation.deleteReimbursement(edited.id)
    XCTAssertThrowsError(try ReturnTransitions.applying(command, to: changed, updatedAt: changedAt))
    {
      XCTAssertEqual($0 as? ReturnTransitionFailure, .confirmationRequired(.reimbursementDeletion))
    }
    let deleted = try apply(command, changed)
    XCTAssertEqual(deleted.reimbursements, [item.reimbursements[1]])
    XCTAssertEqual(deleted.state, item.state)
    XCTAssertEqual(item, ledger())
  }

  func testInvalidEventCommandsRejectDuplicateMissingParentAndAmountsWithoutChangingSource() throws
  {
    let item = ledger()
    XCTAssertThrowsError(try apply(.addReimbursement(item.reimbursements[0]), item)) {
      XCTAssertEqual($0 as? ReturnQueueError, .duplicateEventID)
    }
    let missing = CoreFixtures.event(id: UUID())
    for command in [ReturnMutation.editReimbursement(missing), .deleteReimbursement(missing.id)] {
      XCTAssertThrowsError(try apply(command, item)) {
        XCTAssertEqual($0 as? ReturnTransitionFailure, .missingReimbursement)
      }
    }
    var event = CoreFixtures.event(id: UUID(), parentID: UUID())
    XCTAssertThrowsError(try apply(.addReimbursement(event), item)) {
      XCTAssertEqual($0 as? ReturnQueueError, .invalidEventParent)
    }
    event.returnItemID = item.id
    for cents in [0, -1, 100_000_001, Int.max] {
      event.amountCents = cents
      XCTAssertThrowsError(try apply(.addReimbursement(event), item))
    }
    XCTAssertEqual(item, ledger())
  }

  func testExcessAddAndKindOnlyEditRequireConfirmationAndNeverCapTheRecordedAmount() throws {
    var item = ledger()
    item.expectedRefundCents = 7_000
    var kindChange = item.reimbursements[0]
    kindChange.kind = .storeCredit
    let event = CoreFixtures.event(id: UUID(), cents: 1_001)
    for command in [ReturnMutation.addReimbursement(event), .editReimbursement(kindChange)] {
      let preview = try ReturnTransitions.preview(command, to: item, updatedAt: changedAt)
      XCTAssertEqual(preview.confirmationReason, .excessReimbursement)
      XCTAssertTrue(preview.summary.isExcess)
      XCTAssertThrowsError(try ReturnTransitions.applying(command, to: item, updatedAt: changedAt))
      {
        XCTAssertEqual($0 as? ReturnTransitionFailure, .confirmationRequired(.excessReimbursement))
      }
      XCTAssertEqual(try apply(command, item), preview.item)
    }
    XCTAssertEqual(
      try apply(.addReimbursement(event), item).reimbursements.last?.amountCents, 1_001)
  }

  func testClosedLedgerCorrectionRequiresAnExplanationInsteadOfSilentlyReopening() throws {
    var item = ledger()
    item.expectedRefundCents = 8_000
    item = try apply(.close(outcome: .fullRefund, note: nil), item)
    var edited = item.reimbursements[0]
    edited.amountCents = 4_999
    for command in [ReturnMutation.editReimbursement(edited), .deleteReimbursement(edited.id)] {
      XCTAssertThrowsError(try apply(command, item)) {
        XCTAssertEqual($0 as? ReturnQueueError, .missingClosureNote)
      }
    }
    XCTAssertEqual(item.state, .closed)
    XCTAssertEqual(item.reimbursements, ledger().reimbursements)
    let explained = try apply(.close(outcome: .partialRefund, note: "Correction accepted"), item)
    XCTAssertEqual(try apply(.deleteReimbursement(edited.id), explained).state, .closed)
  }

  func testExpectationWarningOnlyAppliesToChangedKnownExpectationBelowRecordedTotal() throws {
    let original = ledger()
    var candidate = original
    candidate.expectedRefundCents = 7_999
    XCTAssertTrue(
      try ReturnTransitions.requiresExpectedRefundConfirmation(from: original, to: candidate))
    candidate.expectedRefundCents = 8_000
    XCTAssertFalse(
      try ReturnTransitions.requiresExpectedRefundConfirmation(from: original, to: candidate))
    candidate.expectedRefundCents = nil
    XCTAssertFalse(
      try ReturnTransitions.requiresExpectedRefundConfirmation(from: original, to: candidate))
    var unknown = original
    unknown.expectedRefundCents = nil
    candidate.expectedRefundCents = 0
    XCTAssertTrue(
      try ReturnTransitions.requiresExpectedRefundConfirmation(from: unknown, to: candidate))
    var excess = original
    excess.expectedRefundCents = 7_000
    candidate = excess
    candidate.title = "Unrelated edit"
    candidate.purchasePriceCents = 1
    XCTAssertFalse(
      try ReturnTransitions.requiresExpectedRefundConfirmation(from: excess, to: candidate))
  }

  private func ledger() -> ReturnItem {
    var item = CoreFixtures.item()
    item.expectedRefundCents = 10_000
    item.notes = "Bring box"
    item.reimbursements = [
      CoreFixtures.event(cents: 5_000),
      CoreFixtures.event(id: CoreFixtures.secondEventID, cents: 3_000, kind: .storeCredit),
    ]
    return item
  }

  private func apply(_ command: ReturnMutation, _ item: ReturnItem) throws -> ReturnItem {
    try ReturnTransitions.applying(
      command, to: item, updatedAt: changedAt, confirmation: .confirmed)
  }

  private func assertRetained(_ candidate: ReturnItem, from original: ReturnItem) {
    XCTAssertEqual(candidate.id, original.id)
    XCTAssertEqual(candidate.createdAt, original.createdAt)
    XCTAssertEqual(candidate.updatedAt, changedAt)
    XCTAssertEqual(candidate.title, original.title)
    XCTAssertEqual(candidate.merchant, original.merchant)
    XCTAssertEqual(candidate.reimbursements, original.reimbursements)
  }
}
