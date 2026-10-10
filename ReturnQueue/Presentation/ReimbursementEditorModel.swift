import Foundation
import Observation
import ReturnQueueCore

public struct ReimbursementDraft: Equatable, Sendable {
  public var date: String
  public var amount: String
  public var note: String
  public var kind: ReimbursementKind

  public init(
    date: String = "", amount: String = "", kind: ReimbursementKind = .money, note: String = ""
  ) {
    self.date = date
    self.amount = amount
    self.kind = kind
    self.note = note
  }

  public init(event: Reimbursement) {
    date = event.date.iso8601
    amount = String(event.amountCents / 100) + "." + String(format: "%02d", event.amountCents % 100)
    kind = event.kind
    note = event.note
  }
}
public enum ReimbursementField: String, Sendable { case date, amount, note }

@MainActor @Observable
public final class ReimbursementEditorModel {
  public var draft: ReimbursementDraft {
    didSet { if draft != oldValue { action.cancelPending() } }
  }
  public private(set) var fieldErrors: [ReimbursementField: String] = [:]
  public let action: RefundActionModel
  private let itemID: UUID
  private let eventID: UUID
  private let isEditing: Bool
  private let now: @MainActor @Sendable () -> Date

  public init(
    session: AppSession, item: ReturnItem, revision: UInt64,
    event: Reimbursement? = nil, newEventID: UUID = UUID(),
    now: @escaping @MainActor @Sendable () -> Date = { Date() },
    timeZone: @escaping @MainActor @Sendable () -> TimeZone = { .current }
  ) {
    action = RefundActionModel(session: session, item: item, revision: revision)
    itemID = item.id
    eventID = event?.id ?? newEventID
    isEditing = event != nil
    self.now = now
    draft =
      event.map(ReimbursementDraft.init(event:))
      ?? ReimbursementDraft(date: refundLocalDay(now(), zone: timeZone())?.iso8601 ?? "")
  }

  public func save() async -> Bool {
    guard !Task.isCancelled, action.state != .saving, action.state != .saved,
      action.pendingPreview == nil
    else { return false }
    fieldErrors = [:]
    let date: CalendarDay?
    do {
      date = try CalendarDay(iso8601: draft.date.trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
      date = nil
      fieldErrors[.date] = "Enter a real Date received as YYYY-MM-DD."
    }
    let amount: Int?
    do {
      let cents = try Money.cents(
        from: draft.amount.trimmingCharacters(in: .whitespacesAndNewlines))
      try Money.validate(cents: cents, currency: "USD")
      amount = cents
    } catch {
      amount = nil
      fieldErrors[.amount] =
        "Enter a positive USD amount, from 0.01 to 1000000.00, with up to two decimal places."
    }
    let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
    if note.count > 1_000 { fieldErrors[.note] = "Keep the note within 1000 characters." }
    guard fieldErrors.isEmpty, let date, let amount else {
      action.reject("Check the highlighted fields. Your draft is kept.")
      return false
    }
    let event = Reimbursement(
      id: eventID, returnItemID: itemID, date: date, amountCents: amount,
      kind: draft.kind, note: note)
    return await action.submit(
      isEditing ? .editReimbursement(event) : .addReimbursement(event), updatedAt: now())
  }

  public func confirmPending() async -> Bool { await action.confirmPending() }
  public func cancelPending() { action.cancelPending() }
}

/// Calendar-day defaults are local Gregorian days, independent of UTC conversion.
func refundLocalDay(_ instant: Date, zone: TimeZone) -> CalendarDay? {
  let seconds = instant.timeIntervalSince1970
  guard seconds.isFinite, (-62_135_769_600...253_402_473_600).contains(seconds) else { return nil }
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = Locale(identifier: "en_US_POSIX")
  calendar.timeZone = zone
  let components = calendar.dateComponents([.era, .year, .month, .day], from: instant)
  guard components.era == 1, let year = components.year, let month = components.month,
    let day = components.day
  else { return nil }
  do { return try CalendarDay(year: year, month: month, day: day) } catch { return nil }
}
