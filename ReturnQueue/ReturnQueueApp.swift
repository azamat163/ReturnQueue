import ReturnQueuePresentation
import ReturnQueueStorage
import SwiftUI

@main
struct ReturnQueueApp: App {
  @State private var session: AppSession
  private let prepare: @Sendable () async throws -> Void
  private let prepareRetry: @Sendable () async throws -> Void

  init() {
    var directory = URL.applicationSupportDirectory.appendingPathComponent(
      "ReturnQueue", isDirectory: true)
    var failsReplacement = false
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      var fixture: UITestFixtureService?
      if arguments.contains("-rq-ui-testing"),
        let index = arguments.firstIndex(of: "-rq-test-root"), index + 1 < arguments.count,
        let identifier = UUID(uuidString: arguments[index + 1])
      {
        directory = directory.appendingPathComponent("UITests", isDirectory: true)
          .appendingPathComponent(identifier.uuidString, isDirectory: true)
        failsReplacement = arguments.contains("-rq-test-write-failure")
        fixture = UITestFixtureService(
          directory: directory, corruptOnLaunch: arguments.contains("-rq-test-corrupt"),
          repairOnRetry: arguments.contains("-rq-test-repair-on-retry"))
      }
      let selectedFixture = fixture
      prepare = { try await selectedFixture?.prepare() }
      prepareRetry = { try await selectedFixture?.repairForRetry() }
    #else
      prepare = {}
      prepareRetry = {}
    #endif
    let selectedFailure = failsReplacement
    let repository = ReturnRepository(fileURL: directory.appendingPathComponent("returns.json")) {
      stage in
      if selectedFailure, stage == .replacement { throw ReturnPersistenceFailure.writeFailed }
    }
    let store = ReturnStore(persistence: repository)
    let recovery = RecoveryFileService(
      directory: URL.temporaryDirectory.appendingPathComponent(
        "ReturnQueueRecovery", isDirectory: true))
    _session = State(initialValue: AppSession(store: store, recovery: recovery))
  }

  var body: some Scene {
    WindowGroup {
      RootView(session: session, prepare: prepare, prepareRetry: prepareRetry)
        .preferredColorScheme(.light)
    }
  }
}
