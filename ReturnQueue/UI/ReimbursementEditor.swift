import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI

struct ReimbursementEditor: View {
  @Bindable var model: ReimbursementEditorModel
  let session: AppSession
  let itemTitle: String
  let merchant: String
  let isEditing: Bool
  @Environment(\.dismiss) private var dismiss

  private var isSaving: Bool { model.action.state == .saving }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("\(itemTitle) · \(merchant)")
            .font(.footnote).foregroundStyle(DesignTokens.secondary)
          Picker("Reimbursement type", selection: $model.draft.kind) {
            Label {
              Text("Money")
            } icon: {
              Image("ReimbursementMoneyChoice").frame(width: 20, height: 20)
            }.tag(ReimbursementKind.money)
            Label {
              Text("Store credit")
            } icon: {
              Image("ReimbursementCreditChoice").frame(width: 20, height: 20)
            }.tag(ReimbursementKind.storeCredit)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("reimbursement.kind")
          field("Amount (USD)", .amount, text: $model.draft.amount, prompt: "19.99")
            .keyboardType(.decimalPad)
          field("Date received", .date, text: $model.draft.date, prompt: "YYYY-MM-DD")
          field(
            "Note (optional)", .note, text: $model.draft.note, prompt: "Add a note", multiline: true
          )
        }
        Section {
          RefundFailureView(
            action: model.action, session: session, identifier: "reimbursement.error")
          if isSaving { ProgressView("Saving…") }
        }
        Section {
          Text("Record what you received.").font(.headline)
          Text("Choose Money for cash refunds or Store credit for credit from the merchant.")
            .foregroundStyle(DesignTokens.secondary)
        } footer: {
          Text("Dates and amounts are entered by you. You can edit or delete this entry later.")
        }
        .listRowBackground(DesignTokens.tint)
      }
      .disabled(isSaving)
      .accessibilityIdentifier("reimbursement.form")
      .scrollContentBackground(.hidden)
      .background(DesignTokens.background)
      .foregroundStyle(DesignTokens.ink)
      .navigationTitle(isEditing ? "Edit reimbursement" : "Record reimbursement")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") {
            model.cancelPending()
            dismiss()
          }
          .labelStyle(.iconOnly).disabled(isSaving)
          .accessibilityIdentifier("reimbursement.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", systemImage: "checkmark") {
            Task { if await model.save() { dismiss() } }
          }
          .labelStyle(.iconOnly).buttonStyle(.borderedProminent)
          .disabled(isSaving || !session.canEdit || model.action.state == .saved)
          .accessibilityIdentifier("reimbursement.save")
        }
      }
      .interactiveDismissDisabled(isSaving)
      .modifier(
        RefundConfirmation(action: model.action) {
          Task { if await model.confirmPending() { dismiss() } }
        })
    }
  }

  private func field(
    _ label: String, _ field: ReimbursementField, text: Binding<String>, prompt: String,
    multiline: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.footnote).foregroundStyle(DesignTokens.secondary)
      TextField(label, text: text, prompt: Text(prompt), axis: multiline ? .vertical : .horizontal)
        .autocorrectionDisabled()
        .accessibilityIdentifier("reimbursement.\(field.rawValue)")
      if let error = model.fieldErrors[field] {
        Text(error).font(.footnote).foregroundStyle(.red)
      }
    }
    .padding(.vertical, 4)
    .listRowBackground(DesignTokens.surface)
  }
}
