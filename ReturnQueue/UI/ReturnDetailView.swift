import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI

struct ReturnDetailView: View {
  let session: AppSession
  let itemID: UUID
  @State private var editor: EditorPresentation?

  private var item: ReturnItem? {
    session.snapshot?.records.first { $0.id == itemID }
  }

  var body: some View {
    Group {
      if let item {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            Text(item.title)
              .font(.largeTitle.bold())
              .foregroundStyle(DesignTokens.ink)
            Text("\(item.merchant) · \(DetailFormatting.state(item.state))")
              .font(.footnote)
              .foregroundStyle(DesignTokens.accent)
            HStack(alignment: .top, spacing: 12) {
              Image("DetailPin")
                .frame(width: 24, height: 24)
                .accessibilityLabel("Drop-off location")
              VStack(alignment: .leading, spacing: 4) {
                Text(item.dropOffLocation ?? "Not set").font(.headline)
                Text("Drop-off location").font(.footnote).foregroundStyle(DesignTokens.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 20))
            infoRow("Return by", DetailFormatting.day(item.returnBy))
            infoRow("Expected refund", DetailFormatting.amount(item.expectedRefundCents))
            infoRow("Purchase price", DetailFormatting.amount(item.purchasePriceCents))
            Text("Return date entered by you.")
              .font(.footnote)
              .foregroundStyle(DesignTokens.secondary)
            note("Notes", item.notes.isEmpty ? "Not set" : item.notes)
            infoRow("Purchase date", DetailFormatting.day(item.purchaseDate))
            infoRow("Expected refund date", DetailFormatting.day(item.expectedRefundDate))
            note("Policy reference", item.policyReference ?? "Not set")
            sessionStatus
          }
          .padding(.horizontal, 20)
          .padding(.vertical)
        }
        .background(DesignTokens.background)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Edit") {
              if let snapshot = session.snapshot {
                editor = EditorPresentation(
                  model: ReturnEditorModel(
                    session: session, item: item, revision: snapshot.revision))
              }
            }
            .disabled(!session.canEdit)
            .accessibilityIdentifier("detail.edit")
          }
        }
      } else {
        ContentUnavailableView("Return unavailable", systemImage: "shippingbox")
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editor) { presentation in
      ReturnEditorView(model: presentation.model, session: session)
    }
  }

  @ViewBuilder private var sessionStatus: some View {
    switch session.phase {
    case .notLoaded:
      Text("Load saved data before making changes.")
        .font(.footnote)
        .foregroundStyle(DesignTokens.secondary)
    case .loading:
      ProgressView("Loading saved data…")
    case .loadFailed:
      Text("Changes are blocked because saved data could not be loaded. Return to Queue and retry.")
        .font(.footnote)
        .foregroundStyle(DesignTokens.secondary)
    case .ready:
      switch session.activity {
      case .saving: ProgressView("Saving…")
      case .exporting: ProgressView("Preparing recovery copy…")
      case .loading: ProgressView("Loading saved data…")
      case .idle: EmptyView()
      }
    }
  }

  private func infoRow(_ label: String, _ value: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        Text(label).foregroundStyle(DesignTokens.secondary)
        Spacer()
        Text(value).fontWeight(.semibold)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(label).foregroundStyle(DesignTokens.secondary)
        Text(value).fontWeight(.semibold)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .foregroundStyle(DesignTokens.ink)
    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .combine)
  }

  private func note(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.footnote).foregroundStyle(DesignTokens.secondary)
      Text(value).font(.body).foregroundStyle(DesignTokens.ink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 20))
  }
}
