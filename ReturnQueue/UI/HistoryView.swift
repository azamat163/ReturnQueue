import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI

struct HistoryView: View {
  let model: RefundsViewModel

  var body: some View {
    Section {
      Text("\(model.historyCount) returns · Your completed records.")
        .font(.footnote).foregroundStyle(DesignTokens.secondary)
        .accessibilityIdentifier("history.count")
        .listRowBackground(Color.clear)
      ForEach(model.historyItems) { item in
        NavigationLink(value: item.id) {
          VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(.headline).foregroundStyle(DesignTokens.ink)
            Text(item.merchant).font(.footnote).foregroundStyle(DesignTokens.secondary)
            Text("Last updated: \(DetailFormatting.timestamp(item.updatedAt))")
              .font(.footnote).foregroundStyle(DesignTokens.secondary)
            Text(
              item.state == .kept ? "Keeping item" : DetailFormatting.outcome(item.closureOutcome)
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(outcomeColor(item))
            RefundAmounts(item: item)
          }
          .padding(.vertical, 8)
        }
        .accessibilityIdentifier("history.item.\(item.id.uuidString)")
        .listRowBackground(DesignTokens.surface)
      }
    }
  }

  private func outcomeColor(_ item: ReturnItem) -> Color {
    if item.state == .kept || item.closureOutcome == .fullRefund
      || item.closureOutcome == .partialRefund
    {
      return DesignTokens.success
    }
    return DesignTokens.secondary
  }
}
