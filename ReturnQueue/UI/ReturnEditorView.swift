import ReturnQueuePresentation
import SwiftUI

struct EditorPresentation: Identifiable {
  let id = UUID()
  let model: ReturnEditorModel
}

struct ReturnEditorView: View {
  @Bindable var model: ReturnEditorModel
  let session: AppSession
  @Environment(\.dismiss) private var dismiss
  @State private var optionalIsExpanded = false
  @State private var reloadError: String?

  private var isSaving: Bool { model.saveState == .saving }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Start with the item and where you bought it.")
            .font(.footnote)
            .foregroundStyle(DesignTokens.secondary)
            .listRowBackground(Color.clear)
          field("Item name", .title, text: $model.draft.title)
          field("Merchant", .merchant, text: $model.draft.merchant)
        }
        Section {
          DisclosureGroup(isExpanded: $optionalIsExpanded) {
            field("Drop-off location", .dropOffLocation, text: $model.draft.dropOffLocation)
            field("Return by", .returnBy, text: $model.draft.returnBy, prompt: "YYYY-MM-DD")
            field(
              "Purchase date", .purchaseDate, text: $model.draft.purchaseDate, prompt: "YYYY-MM-DD")
            field(
              "Expected refund date", .expectedRefundDate,
              text: $model.draft.expectedRefundDate, prompt: "YYYY-MM-DD")
            field(
              "Purchase price (USD)", .purchasePrice, text: $model.draft.purchasePrice,
              prompt: "19.99"
            )
            .keyboardType(.decimalPad)
            field(
              "Expected refund (USD)", .expectedRefund, text: $model.draft.expectedRefund,
              prompt: "19.99"
            )
            .keyboardType(.decimalPad)
            field("Policy reference", .policyReference, text: $model.draft.policyReference)
            field("Notes", .notes, text: $model.draft.notes, multiline: true)
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text("Optional details").font(.headline)
                .accessibilityIdentifier("editor.optional")
              Text("Location, dates, amounts and notes")
                .font(.footnote)
                .foregroundStyle(DesignTokens.secondary)
            }
          }
        } footer: {
          Text("Only item name and merchant are required. Dates are entered by you.")
        }
        if case .failed(let message) = model.saveState {
          Section {
            Text(message)
              .foregroundStyle(.red)
              .accessibilityIdentifier("editor.error")
            Button("Reload saved data") {
              Task {
                do { try await session.load() } catch {
                  reloadError = "Could not reload saved data. Your draft is kept."
                }
              }
            }
            .disabled(session.activity != .idle)
            .accessibilityIdentifier("editor.reload")
            Text("Reload keeps this draft. Cancel and reopen to edit the latest saved version.")
              .font(.footnote)
              .foregroundStyle(DesignTokens.secondary)
          }
        }
        if isSaving {
          Section { ProgressView("Saving…") }
        }
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Image("AddHeroPackage")
              .frame(width: 28, height: 28)
              .accessibilityLabel("Package")
            Text("A small habit. One less loose end.")
              .font(.title3.weight(.semibold))
            Text("Add the details you know. You can fill in the rest later.")
              .font(.body)
              .foregroundStyle(DesignTokens.secondary)
          }
          .padding(.vertical, 8)
          .listRowBackground(DesignTokens.tint)
        }
      }
      .disabled(isSaving)
      .accessibilityIdentifier("editor.form")
      .scrollContentBackground(.hidden)
      .background(DesignTokens.background)
      .foregroundStyle(DesignTokens.ink)
      .navigationTitle(model.isEditing ? "Edit return" : "Add return")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
            .disabled(isSaving)
            .accessibilityIdentifier("editor.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", systemImage: "checkmark") {
            Task {
              if await model.save() {
                dismiss()
              } else if model.fieldErrors.keys.contains(where: { $0 != .title && $0 != .merchant })
              {
                optionalIsExpanded = true
              }
            }
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderedProminent)
          .disabled(isSaving || !session.canEdit || model.saveState == .saved)
          .accessibilityIdentifier("editor.save")
        }
      }
      .interactiveDismissDisabled(isSaving)
      .alert(
        "Reload failed",
        isPresented: Binding(
          get: { reloadError != nil }, set: { if !$0 { reloadError = nil } }
        )
      ) {
        Button("OK") { reloadError = nil }
      } message: {
        Text(reloadError ?? "")
      }
    }
  }

  private func field(
    _ label: String, _ field: ReturnEditorField, text: Binding<String>,
    prompt: String = "Not set", multiline: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.footnote).foregroundStyle(DesignTokens.secondary)
      TextField(label, text: text, prompt: Text(prompt), axis: multiline ? .vertical : .horizontal)
        .font(.body)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.sentences)
        .accessibilityIdentifier("editor.\(field.rawValue)")
      if let error = model.fieldErrors[field] {
        Text(error).font(.footnote).foregroundStyle(.red)
      }
    }
    .padding(.vertical, 4)
    .listRowBackground(DesignTokens.surface)
  }
}
