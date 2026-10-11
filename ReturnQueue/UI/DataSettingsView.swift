import ReturnQueuePresentation
import ReturnQueueStorage
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DataSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model: DataSettingsModel
  @State private var importerPresented = false
  @State private var confirmationPresented = false
  @State private var originalExportConfirmationPresented = false
  @State private var importTask: Task<Void, Never>?
  @State private var importTaskID: UUID?
  @State private var operationTask: Task<Void, Never>?
  @State private var exportReserved = false
  @State private var commitReserved = false
  @State private var ownedCopy: OwnedDataCopy?
  @State private var share: RecoveryShare?
  @State private var cleanupInProgress = false
  @State private var cleanupError: String?
  @State private var cleanupAlertPresented = false
  @State private var selectionError: String?
  @State private var reportedCommit = false
  @State private var closing = false
  private let session: AppSession
  private let onCommitted: @MainActor (DataChange) -> Void

  init(session: AppSession, onCommitted: @escaping @MainActor (DataChange) -> Void) {
    self.session = session
    self.onCommitted = onCommitted
    _model = State(initialValue: DataSettingsModel(session: session))
  }

  private var ownsCopy: Bool {
    exportReserved || ownedCopy != nil || share != nil || cleanupInProgress
  }

  private var canClose: Bool {
    model.canClose && !ownsCopy && !commitReserved && !importerPresented
      && !originalExportConfirmationPresented && !closing
  }

  private var canAct: Bool {
    !ownsCopy && !importerPresented && !commitReserved && !originalExportConfirmationPresented
      && !closing
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(alignment: .top, spacing: 12) {
            Image("DataShield24")
              .frame(width: 24, height: 24)
              .accessibilityHidden(true)
            Text("Stored on this iPhone. No account or sync.")
              .font(.body)
              .foregroundStyle(DesignTokens.secondary)
          }
        }
        Section {
          Button {
            beginExport(original: false)
          } label: {
            Text("Export backup").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canAct || !model.canExport)
          .accessibilityIdentifier("data.export")

          Button("Restore backup") { importerPresented = true }
            .buttonStyle(.bordered)
            .disabled(!canAct || !model.canImport)
            .accessibilityIdentifier("data.restore")

          if case .loadFailed = session.phase {
            Button("Export original data") { requestOriginalExport() }
              .disabled(!canAct || !model.canExportOriginal)
              .accessibilityIdentifier("data.exportOriginal")
            Text(
              "Saved data could not be read. A valid backup can replace it after your confirmation."
            )
            .foregroundStyle(DesignTokens.secondary)
          }
        } footer: {
          Text("Backups may contain purchase details and personal information.")
        }

        if let preview = model.preview { previewSection(preview) }

        if let message = cleanupError ?? selectionError ?? model.error {
          Section {
            Text(message)
              .foregroundStyle(.red)
              .accessibilityIdentifier("data.error")
            if ownedCopy != nil, cleanupError != nil {
              Button("Retry cleanup") { beginCleanup() }
                .disabled(share != nil || cleanupInProgress || exportReserved)
                .accessibilityIdentifier("data.retryCleanup")
            }
          }
        }

        if model.state != .idle {
          Section {
            switch model.state {
            case .importing: ProgressView("Reading backup…")
            case .exporting: ProgressView("Preparing copy…")
            case .saving: ProgressView("Saving changes…")
            case .succeeded:
              Text("Saved data updated.").accessibilityIdentifier("data.success")
            case .idle: EmptyView()
            }
          }
        }

        Section {
          Button(role: .destructive) {
            guard canAct else { return }
            model.requestDeleteAll()
            confirmationPresented = model.pendingConfirmation != nil
          } label: {
            HStack {
              Image("DataTrash20")
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
              Text("Delete all data")
            }
          }
          .disabled(!canAct || !model.canDeleteAll)
          .accessibilityIdentifier("data.deleteAll")
        }
      }
      .accessibilityIdentifier("data.form")
      .scrollContentBackground(.hidden)
      .background(DesignTokens.background)
      .navigationTitle("Data & backups")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            close()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close")
          .accessibilityIdentifier("data.close")
          .disabled(!canClose)
        }
      }
      .fileImporter(
        isPresented: $importerPresented, allowedContentTypes: [.json],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          guard urls.count == 1, let url = urls.first else {
            selectionError = "Choose one Return Queue backup."
            return
          }
          beginImport(url)
        case .failure(let error):
          if (error as? CocoaError)?.code != .userCancelled, !(error is CancellationError) {
            selectionError = "Could not select this file. Check access in Files and try again."
          }
        }
      }
      .alert(confirmationTitle, isPresented: $confirmationPresented) {
        Button(confirmationAction, role: .destructive) { confirmChange() }
          .accessibilityIdentifier(confirmationID)
        Button("Cancel", role: .cancel) { model.cancelConfirmation() }
          .accessibilityIdentifier(cancellationID)
      } message: {
        Text(confirmationMessage)
      }
      .alert("Export original unreadable data?", isPresented: $originalExportConfirmationPresented)
      {
        Button("Export original data") {
          originalExportConfirmationPresented = false
          beginExport(original: true)
        }
        .accessibilityIdentifier("data.originalConfirm")
        Button("Cancel", role: .cancel) { originalExportConfirmationPresented = false }
          .accessibilityIdentifier("data.originalCancel")
      } message: {
        Text(
          "This is the original unreadable file, not a validated backup. It may contain purchase details and personal information."
        )
      }
      .alert("Temporary copy needs cleanup", isPresented: $cleanupAlertPresented) {
        Button("Retry cleanup") { beginCleanup() }
          .disabled(share != nil || cleanupInProgress || exportReserved)
        Button("OK", role: .cancel) {}
      } message: {
        Text("Retry cleanup before closing this screen or starting another data action.")
      }
    }
    .interactiveDismissDisabled(!canClose)
    .background {
      RecoveryShareView(share: share) { id in
        guard share?.id == id, ownedCopy?.id == id else { return }
        share = nil
        beginCleanup()
      }
      .frame(width: 0, height: 0)
    }
    .onChange(of: model.state) { _, state in
      guard case .succeeded(let change) = state, !reportedCommit else { return }
      reportedCommit = true
      // The retained sheet reports durable success before its actual dismissal resets Root paths.
      onCommitted(change)
      dismiss()
    }
    .onDisappear {
      guard !reportedCommit, canClose else { return }
      importTask?.cancel()
      Task { await model.cancelPreview() }
    }
  }

  @ViewBuilder
  private func previewSection(_ preview: RestorePreview) -> some View {
    Section {
      Text("Restore preview")
        .font(.headline)
        .accessibilityIdentifier("restore.preview")
      Text("\(preview.returnCount) returns")
        .accessibilityIdentifier("restore.returnCount")
      Text("\(preview.reimbursementCount) reimbursements")
        .accessibilityIdentifier("restore.eventCount")
      if let current = preview.currentReturnCount {
        Text("\(current) returns currently on this iPhone.")
      } else {
        Text("Current return count is unknown because saved data could not be read.")
      }
      Text("This replaces the returns currently on this iPhone.")
      if case .loadFailed = session.phase {
        Button("Export original data") { requestOriginalExport() }
          .disabled(!canAct || !model.canExportOriginal)
          .accessibilityIdentifier("restore.exportOriginal")
      } else {
        Button("Export current backup") { beginExport(original: false) }
          .disabled(!canAct || !model.canExport)
          .accessibilityIdentifier("restore.exportCurrent")
      }
      Button("Replace current data", role: .destructive) {
        guard canAct else { return }
        model.requestReplacement()
        confirmationPresented = model.pendingConfirmation != nil
      }
      .disabled(!canAct || !model.canImport)
      .accessibilityIdentifier("restore.replace")
      Button("Cancel preview") {
        guard canAct else { return }
        importTask?.cancel()
        Task { await model.cancelPreview() }
      }
      .disabled(!canAct || model.state != .idle)
      .accessibilityIdentifier("restore.cancel")
    }
  }

  private var isDeleteConfirmation: Bool {
    if case .deleteAll = model.pendingConfirmation { return true }
    return false
  }

  private var confirmationTitle: String {
    isDeleteConfirmation ? "Delete all data?" : "Replace current data?"
  }

  private var confirmationAction: String {
    isDeleteConfirmation ? "Delete all data" : "Replace current data"
  }

  private var confirmationID: String {
    isDeleteConfirmation ? "delete.allConfirm" : "restore.confirm"
  }

  private var cancellationID: String {
    isDeleteConfirmation ? "delete.allCancel" : "restore.confirmCancel"
  }

  private var confirmationMessage: String {
    isDeleteConfirmation
      ? "This removes all saved returns and their reimbursements from this iPhone."
      : "This replaces all current returns and reimbursements with the selected backup."
  }

  private func close() {
    guard canClose else { return }
    // Reserve dismissal before an await can make the model idle and admit another action.
    closing = true
    importTask?.cancel()
    Task {
      await model.cancelPreview()
      dismiss()
    }
  }

  private func beginImport(_ url: URL) {
    guard !closing, !ownsCopy, !commitReserved, model.canImport else { return }
    selectionError = nil
    importTask?.cancel()
    let id = UUID()
    importTaskID = id
    importTask = Task {
      await model.selectArchive(from: url)
      if importTaskID == id { importTask = nil }
    }
  }

  private func confirmChange() {
    guard canAct, model.state == .idle else { return }
    commitReserved = true
    operationTask = Task {
      await model.confirm()
      commitReserved = false
    }
  }

  private func requestOriginalExport() {
    guard canAct, model.canExportOriginal else { return }
    originalExportConfirmationPresented = true
  }

  private func beginExport(original: Bool) {
    guard canAct, original ? model.canExportOriginal : model.canExport else { return }
    exportReserved = true
    selectionError = nil
    operationTask = Task {
      let copy: OwnedDataCopy?
      if original {
        let url = await model.exportOriginal()
        copy = url.map { .raw(id: UUID(), url: $0) }
      } else {
        let export = await model.exportCurrent()
        copy = export.map(OwnedDataCopy.validated)
      }
      // Never drop ownership of a created resource because its awaiting task was cancelled.
      ownedCopy = copy
      exportReserved = false
      guard let copy else { return }
      if Task.isCancelled {
        beginCleanup()
      } else {
        share = RecoveryShare(id: copy.id, url: copy.url)
      }
    }
  }

  private func beginCleanup() {
    guard !exportReserved, share == nil, !cleanupInProgress, let copy = ownedCopy else { return }
    cleanupInProgress = true
    operationTask = Task {
      do {
        switch copy {
        case .raw(_, let url): try await session.cleanupRecovery(url)
        case .validated(let export): try await session.cleanupBackup(export)
        }
        if ownedCopy?.id == copy.id {
          ownedCopy = nil
          cleanupError = nil
        }
      } catch {
        cleanupError = "Could not remove the temporary copy. Retry cleanup before continuing."
        cleanupAlertPresented = true
      }
      cleanupInProgress = false
    }
  }
}

private enum OwnedDataCopy {
  case raw(id: UUID, url: URL)
  case validated(ArchiveExport)

  var id: UUID {
    switch self {
    case .raw(let id, _): return id
    case .validated(let export): return export.id
    }
  }

  var url: URL {
    switch self {
    case .raw(_, let url): return url
    case .validated(let export): return export.url
    }
  }
}
