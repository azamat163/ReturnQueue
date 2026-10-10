import Foundation
import Observation
import ReturnQueueCore
import ReturnQueueStorage

public enum EditorSaveState: Equatable, Sendable {
  case idle, awaitingConfirmation, saving, saved
  case failed(String)
}

@MainActor @Observable
public final class ReturnEditorModel {
  public var draft: ReturnDraft {
    didSet {
      if draft != oldValue { cancelPendingSave() }
    }
  }
  public private(set) var pendingSummary: RefundSummary?
  private var pendingCandidate: ReturnItem?
  public private(set) var fieldErrors: [ReturnEditorField: String] = [:]
  public private(set) var saveState: EditorSaveState = .idle
  private let session: AppSession
  private let original: ReturnItem
  private let originalRevision: UInt64?
  private let now: @Sendable () -> Date

  public init(session: AppSession, now: @escaping @Sendable () -> Date = { Date() }) {
    self.session = session
    self.now = now
    original = ReturnItem(title: "", merchant: "", createdAt: now())
    originalRevision = nil
    draft = ReturnDraft()
  }

  public init(
    session: AppSession, item: ReturnItem, revision: UInt64,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.session = session
    self.now = now
    original = item
    originalRevision = revision
    draft = ReturnDraft(item: item)
  }

  public var isEditing: Bool { originalRevision != nil }

  public func save() async -> Bool {
    guard !Task.isCancelled, saveState != .saving, saveState != .saved,
      saveState != .awaitingConfirmation
    else { return false }
    fieldErrors = [:]
    var item = original
    item.title = text(draft.title, field: .title, label: "item name", limit: 120, required: true)
    item.merchant = text(
      draft.merchant, field: .merchant, label: "merchant", limit: 120, required: true)
    item.dropOffLocation = optionalText(
      draft.dropOffLocation, field: .dropOffLocation, label: "location", limit: 200)
    item.returnBy = day(draft.returnBy, field: .returnBy)
    item.purchaseDate = day(draft.purchaseDate, field: .purchaseDate)
    item.expectedRefundDate = day(draft.expectedRefundDate, field: .expectedRefundDate)
    item.purchasePriceCents = amount(draft.purchasePrice, field: .purchasePrice)
    item.expectedRefundCents = amount(draft.expectedRefund, field: .expectedRefund)
    item.policyReference = optionalText(
      draft.policyReference, field: .policyReference, label: "policy reference", limit: 1_000)
    item.notes = text(draft.notes, field: .notes, label: "notes", limit: 4_000)
    item.updatedAt = now()
    guard fieldErrors.isEmpty else {
      saveState = .failed("Check the highlighted fields.")
      return false
    }
    let validated: ReturnItem
    do {
      validated = try item.validated()
    } catch {
      saveState = .failed(
        error as? ReturnQueueError == .missingClosureNote
          ? "Edit the closure explanation or reopen this return first."
          : "These changes are not valid for the saved return. Review the details.")
      return false
    }
    do {
      if isEditing,
        try ReturnTransitions.requiresExpectedRefundConfirmation(from: original, to: validated)
      {
        pendingSummary = try RefundSummary(item: validated)
        pendingCandidate = validated
        saveState = .awaitingConfirmation
        return false
      }
    } catch {
      saveState = .failed("Review the recorded amounts before saving. Your draft is kept.")
      return false
    }
    return await commit(validated, confirmation: .none)
  }

  public func confirmPendingSave() async -> Bool {
    guard !Task.isCancelled, saveState == .awaitingConfirmation,
      let candidate = pendingCandidate
    else { return false }
    return await commit(candidate, confirmation: .confirmed)
  }

  public func cancelPendingSave() {
    guard saveState != .saving else { return }
    pendingCandidate = nil
    pendingSummary = nil
    if saveState == .awaitingConfirmation { saveState = .idle }
  }

  private func commit(_ candidate: ReturnItem, confirmation: ReturnConfirmation) async -> Bool {
    guard !Task.isCancelled, saveState != .saving, saveState != .saved else { return false }
    saveState = .saving
    pendingCandidate = nil
    pendingSummary = nil
    do {
      if let originalRevision {
        _ = try await session.update(
          candidate, expectedRevision: originalRevision, confirmation: confirmation)
      } else {
        _ = try await session.create(candidate)
      }
      saveState = .saved
      return true
    } catch {
      saveState = .failed(message(for: error))
      return false
    }
  }

  private func text(
    _ input: String, field: ReturnEditorField, label: String, limit: Int, required: Bool = false
  ) -> String {
    let result = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if required, result.isEmpty {
      fieldErrors[field] = field == .title ? "Enter an item name." : "Enter a merchant."
    } else if result.count > limit {
      fieldErrors[field] = "Keep \(label) within \(limit) characters."
    }
    return result
  }

  private func optionalText(
    _ input: String, field: ReturnEditorField, label: String, limit: Int
  ) -> String? {
    let result = text(input, field: field, label: label, limit: limit)
    return result.isEmpty ? nil : result
  }

  private func day(_ input: String, field: ReturnEditorField) -> CalendarDay? {
    let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return nil }
    do {
      return try CalendarDay(iso8601: input)
    } catch {
      fieldErrors[field] = "Enter a real date as YYYY-MM-DD, or leave this blank."
      return nil
    }
  }

  private func amount(_ input: String, field: ReturnEditorField) -> Int? {
    let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return nil }
    do {
      return try Money.cents(from: input)
    } catch {
      fieldErrors[field] = "Enter USD as 19.99, from 0 to 1000000.00, or leave this blank."
      return nil
    }
  }

  private func message(for error: any Error) -> String {
    switch error as? SessionFailure {
    case .busy: return "Another operation is in progress. Wait and try Save again."
    case .notReady:
      return "Reload saved data, then cancel and reopen this editor. Your draft is kept."
    case .store(.staleRevision):
      return
        "Saved data changed. Reload, then cancel and reopen to review the latest return. Your draft is kept."
    case .store(.missingRecord):
      return "This return is no longer saved. Cancel and reload the queue."
    case .store(.writeFailed):
      return "Could not save. Your draft and previous saved data are preserved."
    default: return "Could not save. Review the details or reload saved data. Your draft is kept."
    }
  }
}
