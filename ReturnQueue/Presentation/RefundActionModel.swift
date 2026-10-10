import Foundation
import Observation
import ReturnQueueCore
import ReturnQueueStorage

public enum RefundActionState: Equatable, Sendable {
  case idle
  case awaitingConfirmation(ReturnConfirmationReason)
  case saving, saved
  case failed(String)
}

@MainActor @Observable
public final class RefundActionModel {
  public private(set) var state: RefundActionState = .idle
  public private(set) var pendingPreview: ReturnTransitionPreview?
  private let session: AppSession
  private let original: ReturnItem
  private let revision: UInt64
  private var pendingCommand: ReturnMutation?
  private var pendingTimestamp: Date?

  public init(session: AppSession, item: ReturnItem, revision: UInt64) {
    self.session = session
    original = item
    self.revision = revision
  }

  public func submit(_ command: ReturnMutation, updatedAt: Date) async -> Bool {
    guard !Task.isCancelled, state != .saving, state != .saved,
      pendingPreview == nil
    else { return false }
    do {
      let preview = try ReturnTransitions.preview(command, to: original, updatedAt: updatedAt)
      if let reason = preview.confirmationReason {
        pendingCommand = command
        pendingTimestamp = updatedAt
        pendingPreview = preview
        state = .awaitingConfirmation(reason)
        return false
      }
      return await commit(command, updatedAt: updatedAt, confirmation: .none)
    } catch {
      reject(refundFailureMessage(error))
      return false
    }
  }

  public func confirmPending() async -> Bool {
    guard !Task.isCancelled, case .awaitingConfirmation = state,
      let command = pendingCommand, let timestamp = pendingTimestamp
    else { return false }
    return await commit(command, updatedAt: timestamp, confirmation: .confirmed)
  }

  public func cancelPending() {
    guard state != .saving else { return }
    clearPending()
    if case .awaitingConfirmation = state { state = .idle }
  }

  func reject(_ message: String) {
    guard state != .saving, state != .saved else { return }
    clearPending()
    state = .failed(message)
  }

  private func commit(
    _ command: ReturnMutation, updatedAt: Date, confirmation: ReturnConfirmation
  ) async -> Bool {
    guard !Task.isCancelled, state != .saving, state != .saved else { return false }
    clearPending()
    state = .saving
    do {
      _ = try await session.mutate(
        itemID: original.id, command: command, expectedRevision: revision,
        updatedAt: updatedAt, confirmation: confirmation)
      state = .saved
      return true
    } catch {
      state = .failed(refundFailureMessage(error))
      return false
    }
  }

  private func clearPending() {
    pendingPreview = nil
    pendingCommand = nil
    pendingTimestamp = nil
  }
}

func refundFailureMessage(_ error: any Error) -> String {
  switch error {
  case ReturnQueueError.missingClosureNote,
    SessionFailure.validation(.missingClosureNote):
    return "Edit the closure explanation or reopen this return first."
  case SessionFailure.busy:
    return "Another operation is in progress. Wait and try Save again. Your draft is kept."
  case SessionFailure.notReady:
    return "Reload saved data, then cancel and reopen this form. Your draft is kept."
  case SessionFailure.store(.staleRevision):
    return
      "Saved data changed. Reload, then cancel and reopen to review the latest return. Your draft is kept."
  case SessionFailure.store(.missingRecord):
    return "This return is no longer saved. Cancel and reload saved data."
  case SessionFailure.store(.writeFailed):
    return "Could not save. Your draft and previous saved data are preserved."
  case let error as ReturnTransitionFailure:
    return error.errorDescription ?? "Review this change before saving."
  case SessionFailure.transition(let error):
    return error.errorDescription ?? "Review this change before saving."
  case let error as ReturnQueueError:
    return error.errorDescription ?? "Check the entered values."
  case SessionFailure.validation(let error):
    return error.errorDescription ?? "Check the entered values."
  default:
    return "Could not save. Review the details or reload saved data. Your draft is kept."
  }
}
