import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI

struct ClosureView: View {
  let model: StateEditorModel
  let session: AppSession
  let itemTitle: String
  var onSaved: () -> Void

  var body: some View {
    StateEditorView(
      model: model, session: session, mode: .close, itemTitle: itemTitle, onSaved: onSaved)
  }
}

struct RefundSummaryView: View {
  let item: ReturnItem
  private var summary: Result<RefundSummary, any Error> {
    Result(catching: { try RefundSummary(item: item) })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      switch summary {
      case .success(let summary):
        value("Expected refund", summary.expectedRefundCents, id: "refund.expected")
        value("Money received", summary.moneyCents, id: "refund.money")
        value("Store credit", summary.storeCreditCents, id: "refund.credit")
        value("Difference from expected", summary.differenceCents, id: "refund.difference")
          .padding(12)
          .background(DesignTokens.tint, in: RoundedRectangle(cornerRadius: 12))
        if summary.isExcess {
          Text("Recorded reimbursements exceed your expected refund.")
            .font(.footnote).foregroundStyle(DesignTokens.warning)
        }
      case .failure:
        Text("Recorded totals are unavailable. Reload saved data before making changes.")
          .font(.footnote).foregroundStyle(DesignTokens.warning)
      }
      Text("Based on amounts you've recorded. No bank connection.")
        .font(.footnote).foregroundStyle(DesignTokens.secondary)
    }
    .padding(16)
    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 20))
  }

  private func value(_ label: String, _ cents: Int?, id: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        Text(label).foregroundStyle(DesignTokens.secondary)
        Spacer()
        Text(DetailFormatting.amount(cents)).fontWeight(.semibold)
          .accessibilityIdentifier(id)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(label).foregroundStyle(DesignTokens.secondary)
        Text(DetailFormatting.amount(cents)).fontWeight(.semibold)
          .accessibilityIdentifier(id)
      }
    }
  }
}

/// The model owns the frozen command; dismissing an alert never creates a new candidate.
struct RefundConfirmation: ViewModifier {
  @Bindable var action: RefundActionModel
  var confirm: () -> Void

  func body(content: Content) -> some View {
    content.alert(
      "Confirm recorded change",
      isPresented: Binding(
        get: { action.pendingPreview != nil }, set: { _ in }
      )
    ) {
      Button("Cancel", role: .cancel) { action.cancelPending() }
        .accessibilityIdentifier("refund.cancelConfirmation")
      Button("Confirm") { confirm() }
        .accessibilityIdentifier("refund.confirm")
    } message: {
      Text(message).accessibilityIdentifier("refund.confirmation")
    }
  }

  private var message: String {
    guard let preview = action.pendingPreview else { return "" }
    let item = preview.item
    var lines = ["State: \(DetailFormatting.state(item.state))"]
    if item.state == .closed {
      lines.append("Outcome: \(DetailFormatting.outcome(item.closureOutcome))")
      lines.append("Explanation: \(item.closureNote ?? "Not set")")
    }
    lines.append("Dropped off: \(DetailFormatting.day(item.droppedOffDate))")
    lines.append("Expected refund date: \(DetailFormatting.day(item.expectedRefundDate))")
    lines.append(DetailFormatting.summary(preview.summary))
    if case .awaitingConfirmation(.reimbursementDeletion) = action.state {
      lines.append("Delete this reimbursement entry? The return and other entries are kept.")
    }
    if preview.summary.isExcess {
      lines.append(
        "Recorded reimbursements exceed the expected refund. Save these amounts as entered?")
    }
    lines.append("This is your manual record, not confirmation from a merchant or bank.")
    return lines.joined(separator: "\n\n")
  }
}

struct RefundFailureView: View {
  let action: RefundActionModel
  let session: AppSession
  let identifier: String
  @State private var reloadError: String?

  var body: some View {
    if case .failed(let message) = action.state {
      Text(message).foregroundStyle(.red).accessibilityIdentifier(identifier)
      Button("Reload saved data") {
        Task {
          do { try await session.load() } catch {
            reloadError = "Could not reload saved data. Your draft is kept."
          }
        }
      }
      .disabled(session.activity != .idle)
      Text("Reload keeps your draft. Cancel and reopen to review the latest saved return.")
        .font(.footnote).foregroundStyle(DesignTokens.secondary)
      if let reloadError { Text(reloadError).font(.footnote).foregroundStyle(.red) }
    }
  }
}
