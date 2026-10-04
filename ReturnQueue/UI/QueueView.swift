import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI

/// Group sections are hosted by RootView's List, retaining its navigation and recovery.
struct QueueView: View {
  let model: QueueViewModel

  var body: some View {
    let groups = model.groups
    if !groups.isEmpty {
      Section {
        let count = groups.reduce(0) { $0 + $1.items.count }
        Text("\(count) \(count == 1 ? "item" : "items") to return")
          .font(.subheadline)
          .foregroundStyle(DesignTokens.secondary)
          .listRowBackground(Color.clear)
      }
    }
    ForEach(groups) { group in
      Section {
        ForEach(group.items) { item in
          NavigationLink(value: item.id) {
            card(item)
          }
          .listRowBackground(DesignTokens.surface)
          .accessibilityIdentifier("queue.item.\(item.id.uuidString)")
        }
      } header: {
        HStack(spacing: 8) {
          Image("QueueGroupPin")
            .frame(width: 16, height: 16)
            .accessibilityLabel("Drop-off location")
          Text(group.displayName)
            .font(.footnote)
            .foregroundStyle(DesignTokens.secondary)
            .accessibilityIdentifier("queue.group.\(group.representativeItemID.uuidString)")
        }
        .textCase(nil)
      }
    }
  }

  private func card(_ item: ReturnItem) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title).font(.headline).foregroundStyle(DesignTokens.ink)
        Text(item.merchant).font(.footnote).foregroundStyle(DesignTokens.secondary)
      }
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 8) {
          deadline(item)
          Spacer(minLength: 8)
          expectedAmount(item)
        }
        VStack(alignment: .leading, spacing: 4) {
          deadline(item)
          expectedAmount(item)
        }
      }
      if model.isPastEnteredDate(item.returnBy) {
        Text("Past your entered date")
          .font(.footnote)
          .foregroundStyle(DesignTokens.warning)
      }
    }
    .padding(.vertical, 8)
  }

  private func deadline(_ item: ReturnItem) -> some View {
    Text("Return by: \(DetailFormatting.day(item.returnBy))")
      .font(.footnote)
      .foregroundStyle(
        model.isPastEnteredDate(item.returnBy) ? DesignTokens.warning : DesignTokens.accent)
  }

  private func expectedAmount(_ item: ReturnItem) -> some View {
    Text(
      item.expectedRefundCents.map { "Expected \(DetailFormatting.amount($0))" }
        ?? "Expected amount not set"
    )
    .font(.footnote)
    .foregroundStyle(DesignTokens.secondary)
  }
}
