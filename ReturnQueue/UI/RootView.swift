import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI
import UIKit

struct RootView: View {
  let session: AppSession
  @State private var queueModel: QueueViewModel
  @Environment(\.scenePhase) private var scenePhase
  var prepare: @Sendable () async throws -> Void = {}
  var prepareRetry: @Sendable () async throws -> Void = {}
  @State private var editor: EditorPresentation?
  @State private var confirmExport = false
  @State private var share: RecoveryShare?
  @State private var cleanupURL: URL?
  @State private var cleanupInProgress = false
  @State private var exportInProgress = false
  @State private var operationError: String?
  @State private var initializationFailed = false

  init(
    session: AppSession, prepare: @escaping @Sendable () async throws -> Void = {},
    prepareRetry: @escaping @Sendable () async throws -> Void = {}
  ) {
    self.session = session
    self.prepare = prepare
    self.prepareRetry = prepareRetry
    _queueModel = State(initialValue: QueueViewModel(session: session))
  }

  var body: some View {
    NavigationStack {
      List {
        statusSection
        cleanupSection
        QueueView(model: queueModel)
      }
      .accessibilityIdentifier("queue.list")
      .scrollContentBackground(.hidden)
      .background(DesignTokens.background)
      .overlay {
        if case .ready(let snapshot) = session.phase, queueModel.groups.isEmpty, cleanupURL == nil {
          ContentUnavailableView(
            snapshot.records.isEmpty ? "No returns yet" : "No items to return",
            systemImage: "shippingbox",
            description: Text("Add an item and where you bought it to start your queue.")
          )
          .accessibilityIdentifier("queue.empty")
        }
      }
      .navigationTitle("Return Queue")
      .navigationDestination(for: UUID.self) { itemID in
        ReturnDetailView(session: session, itemID: itemID)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add return", systemImage: "plus") {
            editor = EditorPresentation(model: ReturnEditorModel(session: session))
          }
          .disabled(!session.canEdit || initializationFailed)
          .accessibilityIdentifier("queue.add")
        }
      }
      .sheet(item: $editor) { presentation in
        ReturnEditorView(model: presentation.model, session: session)
      }
      .sheet(item: $share, onDismiss: cleanup) { recovery in
        RecoveryShareView(url: recovery.url)
      }
      .alert("Export original data?", isPresented: $confirmExport) {
        Button("Cancel", role: .cancel) {}
        Button("Export original data") { export() }
          .disabled(!canExport)
          .accessibilityIdentifier("recovery.confirm")
      } message: {
        Text(
          "This file may be damaged and contains personal purchase details and notes. Share it only with someone you trust."
        )
      }
      .alert(
        "Operation unavailable",
        isPresented: Binding(
          get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )
      ) {
        if cleanupURL != nil {
          Button("Retry cleanup") {
            operationError = nil
            cleanup()
          }
          .disabled(cleanupInProgress)
        }
        Button("OK", role: .cancel) { operationError = nil }
      } message: {
        Text(operationError ?? "")
      }
      .onAppear { queueModel.refreshToday() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { queueModel.refreshToday() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
        queueModel.refreshToday()
      }
      .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
        queueModel.refreshToday()
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
      ) { _ in
        queueModel.refreshToday()
      }
      .task {
        guard case .notLoaded = session.phase else { return }
        do {
          try await prepare()
          try await session.load()
        } catch {
          if case .notLoaded = session.phase {
            initializationFailed = true
            operationError = "Saved data could not be prepared. Retry loading."
          }
        }
      }
    }
  }

  @ViewBuilder private var statusSection: some View {
    switch session.phase {
    case .notLoaded:
      Section {
        if initializationFailed {
          Text("Saved data is unavailable.")
          retryButton
        } else {
          ProgressView("Loading saved returns…")
        }
      }
    case .loading:
      Section { ProgressView("Loading saved returns…") }
    case .loadFailed:
      Section {
        Text("Saved data could not be loaded.").font(.headline)
        Text(
          "Your original data has not been replaced. Changes are blocked until it loads successfully."
        )
        .font(.subheadline).foregroundStyle(DesignTokens.secondary)
        retryButton
        Button("Export original data") { confirmExport = true }
          .disabled(!canExport)
          .accessibilityIdentifier("load.export")
      }
    case .ready:
      if session.activity == .exporting {
        Section { ProgressView("Preparing recovery copy…") }
      }
    }
  }

  private var canExport: Bool {
    session.activity == .idle && cleanupURL == nil && !cleanupInProgress && !exportInProgress
  }

  @ViewBuilder private var cleanupSection: some View {
    if cleanupURL != nil {
      Section("Temporary recovery copy") {
        if cleanupInProgress {
          ProgressView("Removing temporary copy…")
        } else {
          Text("Remove the previous temporary copy before exporting again.")
            .font(.footnote)
            .foregroundStyle(DesignTokens.secondary)
          Button("Retry cleanup") { cleanup() }
            .accessibilityIdentifier("recovery.cleanup")
        }
      }
    }
  }

  private var retryButton: some View {
    Button("Retry") {
      Task {
        do {
          try await prepareRetry()
          try await session.load()
          initializationFailed = false
        } catch {
          if case .notLoaded = session.phase {
            operationError = "Saved data could not be loaded. Try again."
          }
        }
      }
    }
    .disabled(session.activity != .idle)
    .accessibilityIdentifier("load.retry")
  }

  private func export() {
    guard canExport else { return }
    // Reserve the UI's copy slot before actor entry, through publication of its owned URL.
    exportInProgress = true
    Task {
      defer { exportInProgress = false }
      do {
        let url = try await session.exportOriginal()
        cleanupURL = url
        share = RecoveryShare(url: url)
      } catch {
        operationError = "Could not copy the original data. Try exporting again."
      }
    }
  }

  private func cleanup() {
    guard !cleanupInProgress, let url = cleanupURL else { return }
    // Retain ownership until deletion succeeds; only one cleanup can be in flight.
    cleanupInProgress = true
    Task {
      defer { cleanupInProgress = false }
      do {
        try await session.cleanupRecovery(url)
        if cleanupURL == url { cleanupURL = nil }
      } catch {
        operationError = "Could not remove the temporary recovery copy. Retry cleanup."
      }
    }
  }
}
