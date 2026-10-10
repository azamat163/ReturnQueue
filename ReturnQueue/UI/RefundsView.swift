import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI

/// Waiting rows are a live projection of the shared committed snapshot.
struct RefundsView: View {
  let model: RefundsViewModel

  var body: some View {
    Section {
      Text("\(model.waitingCount) returns · Add reimbursements as they arrive.")
        .font(.footnote).foregroundStyle(DesignTokens.secondary)
        .accessibilityIdentifier("waiting.count")
        .listRowBackground(Color.clear)
      ForEach(model.waitingItems) { item in
        NavigationLink(value: item.id) {
          VStack(alignment: .leading, spacing: 12) {
            Text(item.title).font(.headline).foregroundStyle(DesignTokens.ink)
            Text("\(item.merchant) · Dropped off: \(DetailFormatting.day(item.droppedOffDate))")
              .font(.footnote).foregroundStyle(DesignTokens.secondary)
            RefundAmounts(item: item)
          }
          .padding(.vertical, 8)
        }
        .accessibilityIdentifier("waiting.item.\(item.id.uuidString)")
        .listRowBackground(DesignTokens.surface)
      }
    } footer: {
      if !model.waitingItems.isEmpty {
        Text("Your manual records. No bank connection.")
      }
    }
  }
}

struct RefundAmounts: View {
  let item: ReturnItem
  private var summary: Result<RefundSummary, any Error> {
    Result(catching: { try RefundSummary(item: item) })
  }

  var body: some View {
    switch summary {
    case .success(let summary):
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 24) {
          total("Money received", summary.moneyCents)
          total("Store credit", summary.storeCreditCents)
        }
        VStack(alignment: .leading, spacing: 8) {
          total("Money received", summary.moneyCents)
          total("Store credit", summary.storeCreditCents)
        }
      }
      Text("Expected refund: \(DetailFormatting.amount(summary.expectedRefundCents))")
        .font(.footnote).foregroundStyle(DesignTokens.secondary)
      Text("Difference from expected: \(DetailFormatting.amount(summary.differenceCents))")
        .font(.footnote).foregroundStyle(DesignTokens.accent)
      if summary.isExcess {
        Text("Recorded amounts exceed expectation.")
          .font(.footnote).foregroundStyle(DesignTokens.warning)
      }
    case .failure:
      Text("Recorded totals unavailable. Reload saved data.")
        .font(.footnote).foregroundStyle(DesignTokens.warning)
    }
  }

  private func total(_ label: String, _ cents: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.footnote).foregroundStyle(DesignTokens.secondary)
      Text(DetailFormatting.amount(cents)).font(.headline).foregroundStyle(DesignTokens.ink)
    }
  }
}
