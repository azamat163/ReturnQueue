import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI

struct StateEditorView: View {
  @Bindable var model: StateEditorModel
  let session: AppSession
  let mode: StateEditorMode
  let itemTitle: String
  var onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss

  private var isSaving: Bool { model.action.state == .saving }
  private var title: String {
    switch mode {
    case .dropOff: return "Mark as dropped off"
    case .keep: return "Keep item"
    case .close: return "Close return"
    case .correct: return "Correct state"
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(itemTitle).font(.headline)
          if mode == .correct {
            Picker("State", selection: $model.draft.state) {
              ForEach(ReturnState.allCases, id: \.self) { state in
                Text(DetailFormatting.state(state)).tag(state)
              }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("state.target")
          } else {
            Text(DetailFormatting.state(model.draft.state))
          }
          if model.draft.state == .droppedOff {
            field("Dropped off", .droppedOffDate, text: $model.draft.droppedOffDate)
            field(
              "Expected refund date (optional)", .expectedRefundDate,
              text: $model.draft.expectedRefundDate)
            Text(
              "Drop-off is your record. It does not confirm acceptance by the merchant. The expected refund date is separate and entered by you."
            )
            .font(.footnote).foregroundStyle(DesignTokens.secondary)
          }
          if model.draft.state == .closed {
            Picker("Outcome", selection: $model.draft.closureOutcome) {
              Text("Choose an outcome").tag(nil as ClosureOutcome?)
              ForEach(ClosureOutcome.allCases, id: \.self) { outcome in
                Text(DetailFormatting.outcome(outcome)).tag(outcome as ClosureOutcome?)
              }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("state.outcome")
            if let error = model.fieldErrors[.closureOutcome] {
              Text(error).font(.footnote).foregroundStyle(.red)
            }
            field(
              "Closure explanation", .closureNote, text: $model.draft.closureNote, multiline: true)
            Text(
              "Choose the outcome yourself. Explain any known difference, including excess. Replacing an earlier explanation preserves it in Notes. If Notes is full, edit Notes before trying again."
            )
            .font(.footnote).foregroundStyle(DesignTokens.secondary)
          }
          if model.draft.state == .kept || model.draft.state == .planned {
            Text("Recorded reimbursements, dates and earlier closure explanations are kept.")
              .font(.footnote).foregroundStyle(DesignTokens.secondary)
          }
        }
        Section {
          RefundFailureView(action: model.action, session: session, identifier: "state.error")
          if isSaving { ProgressView("Saving…") }
        }
      }
      .disabled(isSaving)
      .accessibilityIdentifier("state.form")
      .scrollContentBackground(.hidden)
      .background(DesignTokens.background)
      .foregroundStyle(DesignTokens.ink)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") {
            model.cancelPending()
            dismiss()
          }
          .labelStyle(.iconOnly).disabled(isSaving)
          .accessibilityIdentifier("state.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", systemImage: "checkmark") {
            Task { if await model.save() { finish() } }
          }
          .labelStyle(.iconOnly).buttonStyle(.borderedProminent)
          .disabled(isSaving || !session.canEdit || model.action.state == .saved)
          .accessibilityIdentifier("state.save")
        }
      }
      .interactiveDismissDisabled(isSaving)
      .modifier(
        RefundConfirmation(action: model.action) {
          Task { if await model.confirmPending() { finish() } }
        })
    }
  }

  private func finish() {
    dismiss()
    onSaved()
  }

  private func field(
    _ label: String, _ field: StateEditorField, text: Binding<String>, multiline: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.footnote).foregroundStyle(DesignTokens.secondary)
      TextField(
        label, text: text, prompt: Text(multiline ? "Add an explanation" : "YYYY-MM-DD"),
        axis: multiline ? .vertical : .horizontal
      )
      .autocorrectionDisabled()
      .accessibilityIdentifier(
        field == .closureNote ? "state.closureNote" : "state.\(field.rawValue)")
      if let error = model.fieldErrors[field] {
        Text(error).font(.footnote).foregroundStyle(.red)
      }
    }
    .padding(.vertical, 4)
    .listRowBackground(DesignTokens.surface)
  }
}
