import Foundation
import Observation
import ReturnQueueStorage

public enum DataSettingsState: Equatable, Sendable {
  case idle, importing, exporting, saving
  case succeeded(DataChange)
}

public enum DataChange: Equatable, Sendable { case replaced, deletedAll }

public enum DataSettingsConfirmation: Equatable, Sendable {
  case replace(previewID: UUID)
  case deleteAll(expectedRevision: UInt64)
}

@MainActor @Observable
public final class DataSettingsModel {
  public private(set) var state: DataSettingsState = .idle
  public private(set) var preview: RestorePreview?
  public private(set) var pendingConfirmation: DataSettingsConfirmation?
  public private(set) var error: String?
  private let session: AppSession
  private var importIntent = UUID()

  public init(session: AppSession) { self.session = session }

  public var canImport: Bool {
    guard state == .idle, session.activity == .idle else { return false }
    switch session.phase {
    case .ready, .loadFailed: return true
    case .notLoaded, .loading: return false
    }
  }

  public var canExport: Bool { state == .idle && session.canEdit }

  public var canExportOriginal: Bool {
    guard state == .idle, session.activity == .idle else { return false }
    if case .loadFailed = session.phase { return true }
    return false
  }

  public var canDeleteAll: Bool {
    canExport && !(session.snapshot?.records.isEmpty ?? true)
  }

  public var canClose: Bool {
    switch state {
    case .saving, .exporting: return false
    case .idle, .importing, .succeeded: return true
    }
  }

  public func selectArchive(from url: URL) async {
    guard !Task.isCancelled else { return }
    guard canImport else {
      error = "Another operation is in progress. Wait and select the backup again."
      return
    }
    let intent = UUID()
    importIntent = intent
    let previous = preview
    preview = nil
    pendingConfirmation = nil
    error = nil
    state = .importing
    if let previous { await session.cancelRestore(previous.id) }
    guard importIntent == intent, !Task.isCancelled else {
      if importIntent == intent { state = .idle }
      return
    }
    do {
      let result = try await session.previewRestore(from: url)
      guard importIntent == intent, !Task.isCancelled else {
        await session.cancelRestore(result.id)
        if importIntent == intent { state = .idle }
        return
      }
      preview = result
      state = .idle
    } catch {
      guard importIntent == intent else { return }
      state = .idle
      if !Task.isCancelled, !(error is CancellationError) {
        self.error = dataFailureMessage(error)
      }
    }
  }

  public func cancelPreview() async {
    guard state != .saving, state != .exporting else { return }
    importIntent = UUID()
    let previous = preview
    preview = nil
    pendingConfirmation = nil
    error = nil
    state = .idle
    if let previous { await session.cancelRestore(previous.id) }
  }

  public func requestReplacement() {
    guard canImport, let preview else { return }
    pendingConfirmation = .replace(previewID: preview.id)
    error = nil
  }

  public func requestDeleteAll() {
    guard canDeleteAll, let snapshot = session.snapshot else { return }
    pendingConfirmation = .deleteAll(expectedRevision: snapshot.revision)
    error = nil
  }

  public func cancelConfirmation() {
    guard state == .idle else { return }
    pendingConfirmation = nil
  }

  public func confirm() async {
    guard !Task.isCancelled, state == .idle, let pendingConfirmation else { return }
    state = .saving
    error = nil
    do {
      switch pendingConfirmation {
      case .replace(let id):
        _ = try await session.restore(id, confirmation: .confirmed)
        self.pendingConfirmation = nil
        preview = nil
        state = .succeeded(.replaced)
      case .deleteAll(let revision):
        _ = try await session.deleteAll(expectedRevision: revision, confirmation: .confirmed)
        self.pendingConfirmation = nil
        preview = nil
        state = .succeeded(.deletedAll)
      }
    } catch {
      state = .idle
      if !(error is CancellationError) { self.error = dataFailureMessage(error) }
    }
  }

  public func exportCurrent() async -> ArchiveExport? {
    guard !Task.isCancelled, canExport else { return nil }
    state = .exporting
    error = nil
    defer { state = .idle }
    do {
      // An admitted resource must reach its owner even after task cancellation.
      return try await session.exportBackup()
    } catch {
      if !(error is CancellationError) { self.error = dataFailureMessage(error) }
      return nil
    }
  }

  public func exportOriginal() async -> URL? {
    guard !Task.isCancelled, canExportOriginal else { return nil }
    state = .exporting
    error = nil
    defer { state = .idle }
    do {
      return try await session.exportOriginal()
    } catch {
      if !(error is CancellationError) { self.error = dataFailureMessage(error) }
      return nil
    }
  }
}

func dataFailureMessage(_ error: any Error) -> String {
  switch error {
  case ArchiveFailure.invalidArchive, SessionFailure.archive(.invalidArchive):
    return
      "This backup is invalid or uses an unsupported format. Choose a valid Return Queue backup."
  case ArchiveFailure.archiveTooLarge, SessionFailure.archive(.archiveTooLarge):
    return "This backup is too large. Choose a backup of 20 MiB or less."
  case ArchiveFailure.sourceUnavailable, SessionFailure.archive(.sourceUnavailable):
    return "Could not read this file. Check access in Files and choose the backup again."
  case ArchiveFailure.stalePreview, SessionFailure.archive(.stalePreview):
    return
      "Saved data changed. Select the backup again and review the new preview before replacing."
  case ArchiveFailure.invalidPreview, SessionFailure.archive(.invalidPreview):
    return "This preview is no longer available. Select the backup again."
  case SessionFailure.store(.staleRevision):
    return "Saved data changed. Cancel and reopen this action to review the latest saved data."
  case SessionFailure.store(.missingRecord):
    return "This return is no longer saved. Close this action and reload saved data."
  case SessionFailure.store(.writeFailed):
    return
      "Could not save. Your previous data and selected backup are preserved. Try again or Cancel."
  case SessionFailure.busy:
    return "Another operation is in progress. Wait and try again."
  case SessionFailure.notReady, SessionFailure.store(.notLoaded),
    SessionFailure.store(.readBlocked):
    return "Load saved data first, or select a valid backup to replace unreadable data."
  case ArchiveFailure.exportFailed, SessionFailure.archive(.exportFailed):
    return "Could not create a backup. Your saved data is unchanged. Try Export again."
  case ArchiveFailure.cleanupFailed, SessionFailure.archive(.cleanupFailed):
    return "Could not remove the temporary copy. Retry cleanup before continuing."
  default:
    return
      "Could not complete this action. Your previous saved data is preserved. Try again or Cancel."
  }
}
