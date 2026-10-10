import Foundation

public enum ReturnConfirmation: Equatable, Sendable { case none, confirmed }
public enum ReturnConfirmationReason: Equatable, Sendable {
  case stateChange, reimbursementDeletion, excessReimbursement
}
public enum ReturnMutation: Equatable, Sendable {
  case dropOff(date: CalendarDay, expectedRefundDate: CalendarDay?)
  case keep
  case reopenToReturn
  case reopenWaiting(date: CalendarDay, expectedRefundDate: CalendarDay?)
  case close(outcome: ClosureOutcome, note: String?)
  case addReimbursement(Reimbursement)
  case editReimbursement(Reimbursement)
  case deleteReimbursement(UUID)
}
public enum ReturnTransitionFailure: Error, Equatable, LocalizedError, Sendable {
  case confirmationRequired(ReturnConfirmationReason)
  case missingReimbursement
  case invalidStateAction
  case historyNotesTooLong

  public var errorDescription: String? {
    switch self {
    case .confirmationRequired: return "Review and confirm this change before saving."
    case .missingReimbursement: return "This reimbursement is no longer saved. Reload this return."
    case .invalidStateAction: return "This action is unavailable for the current return state."
    case .historyNotesTooLong:
      return "The previous closure explanation cannot fit in Notes. Edit Notes before retrying."
    }
  }
}
public struct ReturnTransitionPreview: Equatable, Sendable {
  public let item: ReturnItem
  public let summary: RefundSummary
  public let confirmationReason: ReturnConfirmationReason?
}

public enum ReturnTransitions {
  public static func preview(
    _ command: ReturnMutation, to item: ReturnItem, updatedAt: Date
  ) throws -> ReturnTransitionPreview {
    var candidate = try item.validated()
    var reason: ReturnConfirmationReason? = .stateChange
    switch command {
    case .dropOff(let date, let expectedDate):
      guard candidate.state == .planned else { throw ReturnTransitionFailure.invalidStateAction }
      candidate.state = .droppedOff
      candidate.droppedOffDate = date
      candidate.expectedRefundDate = expectedDate
      candidate.closureOutcome = nil
    case .keep:
      candidate.state = .kept
      candidate.closureOutcome = nil
    case .reopenToReturn:
      candidate.state = .planned
      candidate.closureOutcome = nil
    case .reopenWaiting(let date, let expectedDate):
      candidate.state = .droppedOff
      candidate.droppedOffDate = date
      candidate.expectedRefundDate = expectedDate
      candidate.closureOutcome = nil
    case .close(let outcome, let note):
      let note = try normalizedOptionalText(note, field: "closure note", limit: 1_000)
      if let previous = candidate.closureNote, previous != note {
        let history = "Previous closure explanation: \(previous)"
        let notes = candidate.notes.isEmpty ? history : candidate.notes + "\n\n" + history
        guard notes.count <= 4_000 else { throw ReturnTransitionFailure.historyNotesTooLong }
        candidate.notes = notes
      }
      candidate.state = .closed
      candidate.closureOutcome = outcome
      candidate.closureNote = note
    case .addReimbursement(let event):
      guard !candidate.reimbursements.contains(where: { $0.id == event.id }) else {
        throw ReturnQueueError.duplicateEventID
      }
      guard event.returnItemID == candidate.id else { throw ReturnQueueError.invalidEventParent }
      candidate.reimbursements.append(try event.validated())
      reason = nil
    case .editReimbursement(let event):
      guard let index = candidate.reimbursements.firstIndex(where: { $0.id == event.id }) else {
        throw ReturnTransitionFailure.missingReimbursement
      }
      guard event.returnItemID == candidate.id else { throw ReturnQueueError.invalidEventParent }
      candidate.reimbursements[index] = try event.validated()
      reason = nil
    case .deleteReimbursement(let id):
      guard let index = candidate.reimbursements.firstIndex(where: { $0.id == id }) else {
        throw ReturnTransitionFailure.missingReimbursement
      }
      candidate.reimbursements.remove(at: index)
      reason = .reimbursementDeletion
    }
    candidate.updatedAt = updatedAt
    candidate = try candidate.validated()
    let summary = try RefundSummary(item: candidate)
    switch command {
    case .addReimbursement, .editReimbursement:
      if summary.isExcess { reason = .excessReimbursement }
    default: break
    }
    return ReturnTransitionPreview(item: candidate, summary: summary, confirmationReason: reason)
  }

  public static func applying(
    _ command: ReturnMutation, to item: ReturnItem, updatedAt: Date,
    confirmation: ReturnConfirmation = .none
  ) throws -> ReturnItem {
    let preview = try preview(command, to: item, updatedAt: updatedAt)
    if let reason = preview.confirmationReason, confirmation != .confirmed {
      throw ReturnTransitionFailure.confirmationRequired(reason)
    }
    return preview.item
  }

  public static func requiresExpectedRefundConfirmation(
    from original: ReturnItem, to candidate: ReturnItem
  ) throws -> Bool {
    guard original.expectedRefundCents != candidate.expectedRefundCents,
      candidate.expectedRefundCents != nil
    else { return false }
    return try RefundSummary(item: candidate).isExcess
  }
}
