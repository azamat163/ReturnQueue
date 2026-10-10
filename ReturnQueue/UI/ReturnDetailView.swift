import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI

struct ReturnDetailView: View {
  let session: AppSession
  let itemID: UUID
  var onStateSaved: () -> Void = {}
  @State private var editor: EditorPresentation?
  @State private var stateEditor: StatePresentation?
  @State private var stateChangeCommitted = false
  @State private var reimbursementEditor: ReimbursementPresentation?
  @State private var deletion: RefundActionModel?

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
            RefundSummaryView(item: item)
            infoRow(
              "Dropped off", DetailFormatting.day(item.droppedOffDate), id: "refund.droppedOffDate")
            infoRow("Expected refund date", DetailFormatting.day(item.expectedRefundDate))
            if item.state == .closed {
              infoRow(
                "Outcome", DetailFormatting.outcome(item.closureOutcome), id: "refund.outcome")
            } else if item.state == .kept {
              infoRow("Outcome", "Keeping item", id: "refund.outcome")
            }
            if item.state == .closed || item.closureNote != nil {
              note(
                item.state == .closed ? "Closure explanation" : "Earlier closure explanation",
                item.closureNote ?? "Not set", id: "refund.closureNote")
            }
            actions(item)
            ledger(item)
            if let deletion {
              RefundFailureView(
                action: deletion, session: session, identifier: "reimbursement.error")
              if deletion.state == .saving { ProgressView("Saving…") }
            }
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
    .sheet(item: $stateEditor, onDismiss: routeCommittedStateChange) { presentation in
      if presentation.mode == .close {
        ClosureView(
          model: presentation.model, session: session, itemTitle: presentation.title,
          onSaved: { stateChangeCommitted = true })
      } else {
        StateEditorView(
          model: presentation.model, session: session, mode: presentation.mode,
          itemTitle: presentation.title, onSaved: { stateChangeCommitted = true })
      }
    }
    .sheet(item: $reimbursementEditor) { presentation in
      ReimbursementEditor(
        model: presentation.model, session: session, itemTitle: presentation.title,
        merchant: presentation.merchant, isEditing: presentation.isEditing)
    }
    .alert(
      "Delete reimbursement?",
      isPresented: Binding(get: { deletion?.pendingPreview != nil }, set: { _ in })
    ) {
      Button("Cancel", role: .cancel) {
        deletion?.cancelPending()
        deletion = nil
      }.accessibilityIdentifier("refund.cancelConfirmation")
      Button("Delete reimbursement", role: .destructive) {
        Task {
          if let deletion, await deletion.confirmPending() { self.deletion = nil }
        }
      }.accessibilityIdentifier("refund.confirm")
    } message: {
      if let preview = deletion?.pendingPreview {
        Text(
          DetailFormatting.summary(preview.summary)
            + "\n\nThese are the resulting recorded totals. The return and other entries are kept."
        ).accessibilityIdentifier("refund.confirmation")
      }
    }
  }

  private func routeCommittedStateChange() {
    guard stateChangeCommitted else { return }
    stateChangeCommitted = false
    onStateSaved()
  }

  @ViewBuilder private func actions(_ item: ReturnItem) -> some View {
    VStack(spacing: 12) {
      if item.state == .planned {
        actionButton("Mark as dropped off", id: "detail.dropOff", prominent: true) {
          openState(item, mode: .dropOff)
        }
      }
      actionButton(
        "Record reimbursement", id: "detail.addReimbursement", prominent: item.state != .planned
      ) {
        openReimbursement(item)
      }
      if item.state == .droppedOff {
        actionButton("Close return", id: "detail.close") { openState(item, mode: .close) }
      }
      if item.state == .planned || item.state == .droppedOff {
        actionButton("Keep item", id: "detail.keep") { openState(item, mode: .keep) }
      }
      actionButton("Correct state", id: "detail.correctState") { openState(item, mode: .correct) }
      Text("Drop-off is your record, not confirmation of acceptance by the merchant.")
        .font(.footnote).foregroundStyle(DesignTokens.secondary)
    }
    .disabled(!session.canEdit)
  }

  private func actionButton(
    _ label: String, id: String, prominent: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(label).font(.headline)
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .foregroundStyle(prominent ? DesignTokens.surface : DesignTokens.accent)
        .background(
          prominent ? DesignTokens.accent : DesignTokens.tint,
          in: RoundedRectangle(cornerRadius: 20))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  @ViewBuilder private func ledger(_ item: ReturnItem) -> some View {
    Text("Recorded reimbursements").font(.subheadline).foregroundStyle(DesignTokens.secondary)
    if item.reimbursements.isEmpty {
      Text("No reimbursements recorded").font(.footnote).foregroundStyle(DesignTokens.secondary)
    }
    ForEach(
      item.reimbursements.sorted {
        $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
      }
    ) { event in
      VStack(alignment: .leading, spacing: 8) {
        Button {
          openReimbursement(item, event: event)
        } label: {
          HStack(spacing: 12) {
            if event.kind == .money {
              Image("ReimbursementMoney").frame(width: 22, height: 22).accessibilityHidden(true)
            }
            Text(DetailFormatting.kind(event.kind)).font(.headline)
            Spacer()
            Text(DetailFormatting.amount(event.amountCents)).font(.headline)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!session.canEdit)
        .accessibilityIdentifier("reimbursement.edit.\(event.id.uuidString)")
        Text("\(DetailFormatting.day(event.date)) · Date received · Tap to edit")
          .font(.footnote).foregroundStyle(DesignTokens.secondary)
          .accessibilityIdentifier("reimbursement.item.\(event.id.uuidString)")
        if !event.note.isEmpty { Text(event.note).font(.footnote) }
        Button("Delete entry", role: .destructive) {
          guard let snapshot = session.snapshot else { return }
          let action = RefundActionModel(session: session, item: item, revision: snapshot.revision)
          deletion = action
          Task { _ = await action.submit(.deleteReimbursement(event.id), updatedAt: Date()) }
        }
        .disabled(!session.canEdit)
        .accessibilityIdentifier("reimbursement.delete.\(event.id.uuidString)")
      }
      .padding(16)
      .foregroundStyle(DesignTokens.ink)
      .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 20))
    }
  }

  private func openState(_ item: ReturnItem, mode: StateEditorMode) {
    guard session.canEdit, let snapshot = session.snapshot else { return }
    stateEditor = StatePresentation(
      model: StateEditorModel(
        session: session, item: item, revision: snapshot.revision, mode: mode),
      mode: mode, title: item.title)
  }

  private func openReimbursement(_ item: ReturnItem, event: Reimbursement? = nil) {
    guard session.canEdit, let snapshot = session.snapshot else { return }
    reimbursementEditor = ReimbursementPresentation(
      model: ReimbursementEditorModel(
        session: session, item: item, revision: snapshot.revision, event: event),
      title: item.title, merchant: item.merchant, isEditing: event != nil)
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

  private func infoRow(_ label: String, _ value: String, id: String? = nil) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        Text(label).foregroundStyle(DesignTokens.secondary)
        Spacer()
        valueText(value, id: id).fontWeight(.semibold)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(label).foregroundStyle(DesignTokens.secondary)
        valueText(value, id: id).fontWeight(.semibold)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .foregroundStyle(DesignTokens.ink)
    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 20))
  }

  private func note(_ label: String, _ value: String, id: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.footnote).foregroundStyle(DesignTokens.secondary)
      valueText(value, id: id).font(.body).foregroundStyle(DesignTokens.ink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 20))
  }

  @ViewBuilder private func valueText(_ value: String, id: String?) -> some View {
    if let id { Text(value).accessibilityIdentifier(id) } else { Text(value) }
  }
}

private struct StatePresentation: Identifiable {
  let id = UUID()
  let model: StateEditorModel
  let mode: StateEditorMode
  let title: String
}

private struct ReimbursementPresentation: Identifiable {
  let id = UUID()
  let model: ReimbursementEditorModel
  let title: String
  let merchant: String
  let isEditing: Bool
}
