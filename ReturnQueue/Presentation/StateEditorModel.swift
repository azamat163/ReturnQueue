import Foundation
import Observation
import ReturnQueueCore

public enum StateEditorMode: Equatable, Sendable { case dropOff, keep, close, correct }
public struct StateDraft: Equatable, Sendable {
  public var state: ReturnState
  public var droppedOffDate: String
  public var expectedRefundDate: String
  public var closureNote: String
  public var closureOutcome: ClosureOutcome?

  public init(
    state: ReturnState = .planned, droppedOffDate: String = "", expectedRefundDate: String = "",
    closureOutcome: ClosureOutcome? = nil, closureNote: String = ""
  ) {
    self.state = state
    self.droppedOffDate = droppedOffDate
    self.expectedRefundDate = expectedRefundDate
    self.closureOutcome = closureOutcome
    self.closureNote = closureNote
  }
}
public enum StateEditorField: String, Sendable {
  case droppedOffDate, expectedRefundDate, closureOutcome, closureNote
}

@MainActor @Observable
public final class StateEditorModel {
  public var draft: StateDraft {
    didSet { if draft != oldValue { action.cancelPending() } }
  }
  public private(set) var fieldErrors: [StateEditorField: String] = [:]
  public let action: RefundActionModel
  private let original: ReturnItem
  private let mode: StateEditorMode
  private let now: @MainActor @Sendable () -> Date

  public init(
    session: AppSession, item: ReturnItem, revision: UInt64, mode: StateEditorMode,
    now: @escaping @MainActor @Sendable () -> Date = { Date() },
    timeZone: @escaping @MainActor @Sendable () -> TimeZone = { .current }
  ) {
    original = item
    self.mode = mode
    self.now = now
    action = RefundActionModel(session: session, item: item, revision: revision)
    let target: ReturnState
    switch mode {
    case .dropOff: target = .droppedOff
    case .keep: target = .kept
    case .close: target = .closed
    case .correct: target = item.state
    }
    draft = StateDraft(
      state: target,
      droppedOffDate: item.droppedOffDate?.iso8601
        ?? refundLocalDay(now(), zone: timeZone())?.iso8601 ?? "",
      expectedRefundDate: item.expectedRefundDate?.iso8601 ?? "",
      closureOutcome: mode == .correct && item.state == .closed ? item.closureOutcome : nil,
      closureNote: item.closureNote ?? "")
  }

  public func save() async -> Bool {
    guard !Task.isCancelled, action.state != .saving, action.state != .saved,
      action.pendingPreview == nil
    else { return false }
    fieldErrors = [:]
    let command: ReturnMutation?
    switch draft.state {
    case .planned: command = .reopenToReturn
    case .kept: command = .keep
    case .droppedOff:
      let droppedOff = day(draft.droppedOffDate, field: .droppedOffDate, required: true)
      let expected = day(draft.expectedRefundDate, field: .expectedRefundDate, required: false)
      if let droppedOff {
        command =
          mode == .dropOff
          ? .dropOff(date: droppedOff, expectedRefundDate: expected)
          : .reopenWaiting(date: droppedOff, expectedRefundDate: expected)
      } else {
        command = nil
      }
    case .closed:
      let note = draft.closureNote.trimmingCharacters(in: .whitespacesAndNewlines)
      if note.count > 1_000 {
        fieldErrors[.closureNote] = "Keep the explanation within 1000 characters."
      }
      if draft.closureOutcome == nil { fieldErrors[.closureOutcome] = "Choose a closure outcome." }
      do {
        if let difference = try RefundSummary(item: original).differenceCents,
          difference != 0, note.isEmpty
        {
          fieldErrors[.closureNote] = "Explain the remaining difference, including any excess."
        }
      } catch {
        action.reject(refundFailureMessage(error))
        return false
      }
      command = draft.closureOutcome.map { .close(outcome: $0, note: note.isEmpty ? nil : note) }
    }
    guard fieldErrors.isEmpty, let command else {
      action.reject("Check the highlighted fields. Your draft is kept.")
      return false
    }
    return await action.submit(command, updatedAt: now())
  }

  public func confirmPending() async -> Bool { await action.confirmPending() }
  public func cancelPending() { action.cancelPending() }

  private func day(_ input: String, field: StateEditorField, required: Bool) -> CalendarDay? {
    let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if input.isEmpty && !required { return nil }
    do { return try CalendarDay(iso8601: input) } catch {
      fieldErrors[field] =
        required
        ? "Enter a real Dropped off date as YYYY-MM-DD."
        : "Enter a real date as YYYY-MM-DD, or leave this blank."
      return nil
    }
  }
}
