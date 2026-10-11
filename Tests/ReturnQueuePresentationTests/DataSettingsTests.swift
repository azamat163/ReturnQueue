import Foundation
import ReturnQueueCore
import ReturnQueuePresentation
import XCTest

@testable import ReturnQueueStorage

@MainActor
final class DataSettingsTests: XCTestCase {
  func testCancelledModelExportStillTransfersCreatedCapabilityForOwnedCleanup() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let store = ReturnStore(persistence: ReturnRepository(fileURL: fixture.archiveURL))
    let gate = PresentationGate()
    defer { gate.release.signal() }
    let receipt = fixture.directory.appendingPathComponent("owned-export.txt")
    let archive = ArchiveService(
      store: store, directory: fixture.directory.appendingPathComponent("exports"),
      exportCreatedObserver: { export in
        do {
          try Data("\(export.id.uuidString)\n\(export.url.path)".utf8).write(to: receipt)
          try gate.hold()
        } catch { XCTFail("Created export observation did not finish") }
      })
    let session = AppSession(
      store: store, recovery: RecoveryFileService(directory: fixture.recoveryDirectory),
      archive: archive)
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let original = try Data(contentsOf: fixture.archiveURL)
    let model = DataSettingsModel(session: session)
    let operation = Task { await model.exportCurrent() }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    XCTAssertEqual(model.state, .exporting)
    XCTAssertFalse(model.canClose)
    XCTAssertEqual(session.activity, .exporting)
    operation.cancel()
    gate.release.signal()
    let returned = await operation.value
    let export = try XCTUnwrap(returned)
    XCTAssertEqual(
      try String(contentsOf: receipt, encoding: .utf8),
      "\(export.id.uuidString)\n\(export.url.path)")
    XCTAssertEqual(model.state, .idle)
    XCTAssertNil(model.error)
    XCTAssertTrue(model.canClose)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), original)
    try await session.cleanupBackup(export)
    XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path))
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), original)
  }

  func testInvalidNewSelectionDiscardsOldCandidateAndPendingApproval() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let session = makeSession(fixture)
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let original = try Data(contentsOf: fixture.archiveURL)
    let source = fixture.directory.appendingPathComponent("selection.json")
    try ArchiveCodec.encode([]).write(to: source)
    let model = DataSettingsModel(session: session)
    await model.selectArchive(from: source)
    let previous = try XCTUnwrap(model.preview)
    model.requestReplacement()
    try Data("malformed replacement".utf8).write(to: source)
    await model.selectArchive(from: source)
    XCTAssertNil(model.preview)
    XCTAssertNil(model.pendingConfirmation)
    XCTAssertEqual(model.state, .idle)
    XCTAssertFalse(try XCTUnwrap(model.error).isEmpty)
    do {
      _ = try await session.restore(previous.id, confirmation: .confirmed)
      XCTFail("Invalid new selection left old approval usable")
    } catch { XCTAssertEqual(error as? SessionFailure, .archive(.invalidPreview)) }
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), original)
  }

  func testCancelledImportAfterStageAdmissionDoesNotRevivePreviewOrWriteLiveData() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let gate = PresentationGate()
    defer { gate.release.signal() }
    let store = ReturnStore(
      persistence: ReturnRepository(fileURL: fixture.archiveURL),
      restoreStageObserver: {
        do { try gate.hold() } catch { XCTFail("Admitted-stage observation timed out") }
      })
    let session = AppSession(
      store: store, recovery: RecoveryFileService(directory: fixture.recoveryDirectory),
      archive: ArchiveService(
        store: store, directory: fixture.directory.appendingPathComponent("exports")))
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let original = try Data(contentsOf: fixture.archiveURL)
    let source = fixture.directory.appendingPathComponent("selection.json")
    try ArchiveCodec.encode([]).write(to: source)
    let model = DataSettingsModel(session: session)
    let selection = Task { await model.selectArchive(from: source) }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    XCTAssertEqual(model.state, .importing)
    XCTAssertTrue(model.canClose)
    XCTAssertEqual(session.activity, .importing)
    selection.cancel()
    await model.cancelPreview()
    gate.release.signal()
    await selection.value
    XCTAssertNil(model.preview)
    XCTAssertNil(model.pendingConfirmation)
    XCTAssertNil(model.error)
    XCTAssertEqual(model.state, .idle)
    XCTAssertEqual(session.activity, .idle)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), original)
    gate.release.signal()
    await model.selectArchive(from: source)
    XCTAssertNotNil(model.preview)
    model.requestReplacement()
    await model.confirm()
    XCTAssertEqual(model.state, .succeeded(.replaced))
  }

  func testPreviewCancelAndConfirmedReplacementPublishOnlyCommittedRecords() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let session = makeSession(fixture)
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let original = try Data(contentsOf: fixture.archiveURL)
    let incoming = PresentationFixture.item()
    let source = fixture.directory.appendingPathComponent("selection.json")
    try ArchiveCodec.encode([incoming]).write(to: source)
    let model = DataSettingsModel(session: session)
    await model.selectArchive(from: source)
    let preview = try XCTUnwrap(model.preview)
    XCTAssertEqual(model.state, .idle)
    XCTAssertTrue(model.canClose)
    model.requestReplacement()
    XCTAssertEqual(model.pendingConfirmation, .replace(previewID: preview.id))
    model.cancelConfirmation()
    XCTAssertNil(model.pendingConfirmation)
    XCTAssertEqual(model.preview, preview)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), original)
    model.requestReplacement()
    await model.confirm()
    XCTAssertEqual(model.state, .succeeded(.replaced))
    XCTAssertEqual(session.snapshot?.records, [incoming])
    XCTAssertEqual(session.snapshot?.revision, before.revision + 1)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), [incoming])
    XCTAssertEqual(session.activity, .idle)
  }

  func testCancelPreviewInvalidatesItsCapabilityWithoutChangingLiveData() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let session = makeSession(fixture)
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let source = fixture.directory.appendingPathComponent("selection.json")
    try ArchiveCodec.encode([]).write(to: source)
    let model = DataSettingsModel(session: session)
    await model.selectArchive(from: source)
    let preview = try XCTUnwrap(model.preview)
    model.requestReplacement()
    await model.cancelPreview()
    XCTAssertNil(model.preview)
    XCTAssertNil(model.pendingConfirmation)
    XCTAssertEqual(model.state, .idle)
    XCTAssertEqual(session.snapshot, before)
    do {
      _ = try await session.restore(preview.id, confirmation: .confirmed)
      XCTFail("Cancelled candidate remained usable")
    } catch { XCTAssertEqual(error as? SessionFailure, .archive(.invalidPreview)) }
  }

  func testStalePreviewRetainsInspectionAndNeverSubstitutesLatestSnapshot() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let session = makeSession(fixture)
    try await session.load()
    let source = fixture.directory.appendingPathComponent("selection.json")
    try ArchiveCodec.encode([]).write(to: source)
    let model = DataSettingsModel(session: session)
    await model.selectArchive(from: source)
    let preview = try XCTUnwrap(model.preview)
    let committed = try await session.create(PresentationFixture.item())
    let bytes = try Data(contentsOf: fixture.archiveURL)
    model.requestReplacement()
    await model.confirm()
    XCTAssertEqual(model.state, .idle)
    XCTAssertEqual(model.preview, preview)
    XCTAssertFalse(try XCTUnwrap(model.error).isEmpty)
    XCTAssertFalse(try XCTUnwrap(model.error).contains(fixture.directory.path))
    XCTAssertEqual(session.snapshot, committed)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testFailedReplacementRetainsPreviewAndPriorDurableSnapshot() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let session = makeSession(
      fixture, persistence: StorageFailureRepository.make(at: fixture.archiveURL))
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let source = fixture.directory.appendingPathComponent("selection.json")
    try ArchiveCodec.encode([]).write(to: source)
    let model = DataSettingsModel(session: session)
    await model.selectArchive(from: source)
    let preview = try XCTUnwrap(model.preview)
    model.requestReplacement()
    await model.confirm()
    XCTAssertEqual(model.state, .idle)
    XCTAssertTrue(model.canClose)
    XCTAssertEqual(model.preview, preview)
    XCTAssertFalse(try XCTUnwrap(model.error).isEmpty)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    XCTAssertEqual(session.activity, .idle)
  }

  func testExportOfferPreservesSelectedPreviewAndCleanupAllowsSameTokenRestore() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let session = makeSession(fixture)
    try await session.load()
    let source = fixture.directory.appendingPathComponent("selection.json")
    try ArchiveCodec.encode([]).write(to: source)
    let model = DataSettingsModel(session: session)
    await model.selectArchive(from: source)
    let preview = try XCTUnwrap(model.preview)
    let result = await model.exportCurrent()
    let export = try XCTUnwrap(result)
    XCTAssertEqual(model.preview, preview)
    XCTAssertEqual(model.state, .idle)
    XCTAssertNil(model.error)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: export.url)), session.snapshot?.records)
    try await session.cleanupBackup(export)
    model.requestReplacement()
    await model.confirm()
    XCTAssertEqual(model.state, .succeeded(.replaced))
    XCTAssertEqual(session.snapshot?.records, [])
  }

  func testReadFailedShowsUnknownCurrentCountAndAllowsConfirmedRepairOnly() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let corrupt = Data("blocked corrupt original".utf8)
    try corrupt.write(to: fixture.archiveURL)
    let session = makeSession(fixture)
    do { try await session.load() } catch {
      XCTAssertEqual(error as? SessionFailure, .store(.readFailed))
    }
    let model = DataSettingsModel(session: session)
    XCTAssertTrue(model.canImport)
    XCTAssertFalse(model.canExport)
    XCTAssertTrue(model.canExportOriginal)
    XCTAssertFalse(model.canDeleteAll)
    let source = fixture.directory.appendingPathComponent("selection.json")
    let incoming = PresentationFixture.item()
    try ArchiveCodec.encode([incoming]).write(to: source)
    await model.selectArchive(from: source)
    XCTAssertNil(try XCTUnwrap(model.preview).currentReturnCount)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), corrupt)
    model.requestReplacement()
    await model.confirm()
    XCTAssertEqual(model.state, .succeeded(.replaced))
    XCTAssertEqual(session.snapshot?.records, [incoming])
    XCTAssertTrue(session.canEdit)
  }

  func testSavingBlocksCloseDuplicateConfirmationAndSessionIntentsThenCancelledCommitPublishes()
    async throws
  {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let gate = PresentationGate()
    defer { gate.release.signal() }
    let session = makeSession(fixture, persistence: gate.repository(at: fixture.archiveURL))
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let model = DataSettingsModel(session: session)
    model.requestDeleteAll()
    XCTAssertEqual(model.pendingConfirmation, .deleteAll(expectedRevision: before.revision))
    let confirm = Task { await model.confirm() }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    XCTAssertEqual(model.state, .saving)
    XCTAssertFalse(model.canClose)
    XCTAssertFalse(model.canImport)
    XCTAssertFalse(model.canExport)
    XCTAssertEqual(session.activity, .saving)
    await model.confirm()
    do {
      try await session.load()
      XCTFail("Load interleaved with destructive write")
    } catch { XCTAssertEqual(error as? SessionFailure, .busy) }
    XCTAssertEqual(session.snapshot, before)
    confirm.cancel()
    gate.release.signal()
    await confirm.value
    XCTAssertEqual(model.state, .succeeded(.deletedAll))
    XCTAssertTrue(model.canClose)
    XCTAssertEqual(session.snapshot?.records, [])
    XCTAssertEqual(session.snapshot?.revision, before.revision + 1)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), [])
  }

  func testFailedSingleDeleteConsumesConfirmationAndRetainsFailureLedgerAndLiveBytes() async throws
  {
    var owner = PresentationFixture.item()
    owner.reimbursements = [
      Reimbursement(
        returnItemID: owner.id, date: try CalendarDay(year: 2026, month: 10, day: 4),
        amountCents: 5_000, kind: .money, note: "Preserved cash"),
      Reimbursement(
        returnItemID: owner.id, date: try CalendarDay(year: 2026, month: 10, day: 5),
        amountCents: 3_000, kind: .storeCredit, note: "Preserved credit"),
    ]
    let sibling = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [owner, sibling])
    defer { try? fixture.remove() }
    let attempts = fixture.directory.appendingPathComponent("replacement-attempts.txt")
    let persistence = ReturnRepository(fileURL: fixture.archiveURL) { stage in
      if case .replacement = stage {
        let previous =
          FileManager.default.fileExists(atPath: attempts.path)
          ? try Data(contentsOf: attempts) : Data()
        try (previous + Data("replacement\n".utf8)).write(to: attempts)
        throw StorageFailureRepository.Failure.rejected
      }
    }
    let session = makeSession(fixture, persistence: persistence)
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let phase = session.phase
    let liveBytes = try Data(contentsOf: fixture.archiveURL)
    let model = DeleteReturnModel(
      session: session, itemID: owner.id, expectedRevision: before.revision)
    model.requestConfirmation()
    XCTAssertTrue(model.confirmationRequested)
    await model.confirm()
    guard case .failed(let message) = model.saveState else {
      return XCTFail("Actual pre-rename failure did not expose an actionable deletion error")
    }
    XCTAssertFalse(message.isEmpty)
    XCTAssertFalse(message.contains(fixture.directory.path))
    XCTAssertFalse(model.confirmationRequested, "The failed attempt must consume its approval")
    XCTAssertEqual(try Data(contentsOf: attempts), Data("replacement\n".utf8))
    XCTAssertEqual(session.phase, phase)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(session.snapshot?.revision, before.revision)
    XCTAssertEqual(session.snapshot?.records, [owner, sibling])
    XCTAssertEqual(session.snapshot?.records.first?.reimbursements, owner.reimbursements)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), liveBytes)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), [owner, sibling])
    XCTAssertEqual(session.activity, .idle)

    // A second programmatic confirmation without a new user approval must do nothing.
    await model.confirm()
    XCTAssertEqual(model.saveState, .failed(message), "Keep the actionable failure visible")
    XCTAssertFalse(model.confirmationRequested)
    XCTAssertEqual(try Data(contentsOf: attempts), Data("replacement\n".utf8))
    XCTAssertEqual(session.phase, phase)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), liveBytes)
    XCTAssertEqual(session.activity, .idle)
  }

  func testSingleDeleteCancelAndStaleCapturedRevisionNeverDeleteLatestRecord() async throws {
    let item = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = makeSession(fixture)
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let model = DeleteReturnModel(
      session: session, itemID: item.id, expectedRevision: before.revision)
    model.requestConfirmation()
    XCTAssertTrue(model.confirmationRequested)
    model.cancelConfirmation()
    XCTAssertFalse(model.confirmationRequested)
    XCTAssertEqual(session.snapshot, before)
    let changed = try await session.create(PresentationFixture.item())
    model.requestConfirmation()
    await model.confirm()
    guard case .failed(let message) = model.saveState else {
      return XCTFail("Stale single-delete did not expose an actionable failure")
    }
    XCTAssertFalse(message.isEmpty)
    XCTAssertFalse(model.confirmationRequested, "Stale approval is consumed after failure")
    XCTAssertEqual(session.snapshot, changed)
    let fresh = DeleteReturnModel(
      session: session, itemID: item.id, expectedRevision: changed.revision)
    fresh.requestConfirmation()
    await fresh.confirm()
    XCTAssertEqual(fresh.saveState, .succeeded)
    XCTAssertEqual(session.snapshot?.records, [changed.records[1]])
    XCTAssertEqual(
      try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), [changed.records[1]])
  }

  private func makeSession(
    _ fixture: PresentationFixture, persistence: (any ReturnPersistence)? = nil
  ) -> AppSession {
    let store = ReturnStore(
      persistence: persistence ?? ReturnRepository(fileURL: fixture.archiveURL))
    return AppSession(
      store: store, recovery: RecoveryFileService(directory: fixture.recoveryDirectory),
      archive: ArchiveService(
        store: store, directory: fixture.directory.appendingPathComponent("exports")))
  }
}

enum StorageFailureRepository {
  enum Failure: Error { case rejected }
  static func make(at url: URL) -> ReturnRepository {
    ReturnRepository(fileURL: url) { stage in
      if case .replacement = stage { throw Failure.rejected }
    }
  }
}
