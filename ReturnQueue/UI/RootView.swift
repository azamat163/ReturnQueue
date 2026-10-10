import ReturnQueueCore
import ReturnQueuePresentation
import SwiftUI
import UIKit

struct RootView: View {
  let session: AppSession
  @State private var queueModel: QueueViewModel
  @State private var refundsModel: RefundsViewModel
  @State private var selectedTab: ReturnTab = .toReturn
  @State private var queuePath: [UUID] = []
  @State private var waitingPath: [UUID] = []
  @State private var historyPath: [UUID] = []
  @State private var pendingRoute: CommittedRoute?
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
    _refundsModel = State(initialValue: RefundsViewModel(session: session))
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      navigation(.toReturn, path: $queuePath)
        .tabItem {
          Label {
            Text("To return")
          } icon: {
            Image("QueueTabIcon").renderingMode(.template).frame(width: 22, height: 22)
          }
          .accessibilityIdentifier("tab.toReturn")
        }
        .tag(ReturnTab.toReturn)
      navigation(.waiting, path: $waitingPath)
        .tabItem {
          Label {
            Text("Waiting for refund")
          } icon: {
            Image("WaitingTabIcon").renderingMode(.template).frame(width: 22, height: 22)
          }
          .accessibilityIdentifier("tab.waiting")
        }
        .tag(ReturnTab.waiting)
      navigation(.history, path: $historyPath)
        .tabItem {
          Label {
            Text("History")
          } icon: {
            Image("HistoryTabIcon").renderingMode(.template).frame(width: 22, height: 22)
          }
          .accessibilityIdentifier("tab.history")
        }
        .tag(ReturnTab.history)
    }
    .sheet(item: $editor) { presentation in
      ReturnEditorView(model: presentation.model, session: session)
    }
    .background {
      RecoveryShareView(share: share) { id in
        // UIKit has dismissed this exact activity before ownership can be released.
        guard share?.id == id else { return }
        share = nil
        cleanup()
      }
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
        .disabled(cleanupInProgress || share != nil)
      }
      Button("OK", role: .cancel) { operationError = nil }
    } message: {
      Text(operationError ?? "")
    }
    .onAppear { queueModel.refreshToday() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { queueModel.refreshToday() }
    }
    .onChange(of: selectedTab) { _, tab in
      if let route = pendingRoute, route.tab != tab { cancelPendingRoute() }
    }
    .onChange(of: session.phase) { _, _ in
      if let route = pendingRoute, !isCurrent(route) { cancelPendingRoute() }
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

  private func navigation(_ tab: ReturnTab, path: Binding<[UUID]>) -> some View {
    NavigationStack(path: committedPath(in: tab, stored: path)) {
      List {
        statusSection
        cleanupSection
        switch tab {
        case .toReturn: QueueView(model: queueModel)
        case .waiting: RefundsView(model: refundsModel)
        case .history: HistoryView(model: refundsModel)
        }
      }
      .accessibilityIdentifier(tab.listIdentifier)
      .scrollContentBackground(.hidden)
      .background(DesignTokens.background)
      .overlay { emptyState(tab) }
      .navigationTitle(tab.title)
      .navigationDestination(for: UUID.self) { itemID in
        ReturnDetailView(session: session, itemID: itemID) { routeCommitted(itemID) }
          .onAppear { destinationArrived(itemID, in: tab, path: path) }
      }
      .toolbar {
        if tab == .toReturn {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Add return", systemImage: "plus") {
              editor = EditorPresentation(model: ReturnEditorModel(session: session))
            }
            .disabled(!session.canEdit || initializationFailed)
            .accessibilityIdentifier("queue.add")
          }
        }
      }
    }
  }

  @ViewBuilder private func emptyState(_ tab: ReturnTab) -> some View {
    if case .ready(let snapshot) = session.phase, cleanupURL == nil {
      switch tab {
      case .toReturn:
        if queueModel.groups.isEmpty {
          ContentUnavailableView(
            snapshot.records.isEmpty ? "No returns yet" : "No items to return",
            systemImage: "shippingbox",
            description: Text("Add an item and where you bought it to start your queue.")
          )
          .accessibilityIdentifier("queue.empty")
        }
      case .waiting:
        if refundsModel.waitingItems.isEmpty {
          ContentUnavailableView(
            "No returns waiting", systemImage: "clock",
            description: Text("Items you mark as dropped off appear here.")
          ).accessibilityIdentifier("waiting.empty")
        }
      case .history:
        if refundsModel.historyItems.isEmpty {
          ContentUnavailableView(
            "No completed returns", systemImage: "clock.arrow.circlepath",
            description: Text("Returns you close or choose to keep appear here.")
          ).accessibilityIdentifier("history.empty")
        }
      }
    }
  }

  private func routeCommitted(_ itemID: UUID) {
    guard case .ready(let snapshot) = session.phase,
      let item = snapshot.records.first(where: { $0.id == itemID })
    else { return }
    let destination = ReturnTab.destination(for: item.state)
    if selectedTab == destination, storedPath(in: destination) == [itemID] {
      // A same-state correction keeps the visible detail; it has no new arrival lifecycle.
      pendingRoute = nil
      return
    }
    pendingRoute = CommittedRoute(tab: destination, itemID: itemID)
    queuePath = destination == .toReturn ? [itemID] : []
    waitingPath = destination == .waiting ? [itemID] : []
    historyPath = destination == .history ? [itemID] : []
    selectedTab = destination
  }

  private func storedPath(in tab: ReturnTab) -> [UUID] {
    switch tab {
    case .toReturn: queuePath
    case .waiting: waitingPath
    case .history: historyPath
    }
  }

  private func committedPath(in tab: ReturnTab, stored: Binding<[UUID]>) -> Binding<[UUID]> {
    Binding(
      get: {
        if let route = pendingRoute, selectedTab == tab, route.tab == tab, isCurrent(route) {
          return [route.itemID]
        }
        return stored.wrappedValue
      },
      set: { path in
        if let route = pendingRoute, selectedTab == tab, route.tab == tab, isCurrent(route) {
          // A cached stack can reset its binding before the committed destination is rendered.
          if path.isEmpty { return }
          if path != [route.itemID] { pendingRoute = nil }
        }
        stored.wrappedValue = path
      })
  }

  private func destinationArrived(_ itemID: UUID, in tab: ReturnTab, path: Binding<[UUID]>) {
    guard let route = pendingRoute, route.itemID == itemID, route.tab == tab,
      selectedTab == tab, isCurrent(route)
    else { return }
    path.wrappedValue = [itemID]
    pendingRoute = nil
  }

  private func isCurrent(_ route: CommittedRoute) -> Bool {
    guard case .ready(let snapshot) = session.phase,
      let item = snapshot.records.first(where: { $0.id == route.itemID })
    else { return false }
    return ReturnTab.destination(for: item.state) == route.tab
  }

  private func cancelPendingRoute() {
    guard let route = pendingRoute else { return }
    switch route.tab {
    case .toReturn: queuePath = []
    case .waiting: waitingPath = []
    case .history: historyPath = []
    }
    pendingRoute = nil
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
            .disabled(share != nil)
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
    guard share == nil, !cleanupInProgress, let url = cleanupURL else { return }
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

private struct CommittedRoute {
  let tab: ReturnTab
  let itemID: UUID
}

private enum ReturnTab: Hashable {
  case toReturn, waiting, history

  static func destination(for state: ReturnState) -> ReturnTab {
    switch state {
    case .planned: .toReturn
    case .droppedOff: .waiting
    case .closed, .kept: .history
    }
  }

  var title: String {
    switch self {
    case .toReturn: return "Return Queue"
    case .waiting: return "Waiting for refund"
    case .history: return "History"
    }
  }

  var listIdentifier: String {
    switch self {
    case .toReturn: return "queue.list"
    case .waiting: return "waiting.list"
    case .history: return "history.list"
    }
  }
}
