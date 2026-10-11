import Foundation
import ReturnQueueCore
import XCTest

@testable import ReturnQueueStorage

@MainActor
final class ArchiveServiceTests: XCTestCase {
  func testAdmittedExportReturnsExactOwnedCapabilityAfterCancellation() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let records = try US4ArchiveFixture.records()
    try ArchiveCodec.encode(records).write(to: fixture.live)
    let store = fixture.store()
    let before = try await store.load()
    let original = try Data(contentsOf: fixture.live)
    let gate = US4TransactionGate()
    defer { gate.release.signal() }
    let receipt = fixture.directory.appendingPathComponent("export-capability.txt")
    let service = ArchiveService(
      store: store, directory: fixture.exports,
      exportCreatedObserver: { export in
        do {
          try Data("\(export.id.uuidString)\n\(export.url.path)".utf8).write(to: receipt)
          try gate.hold()
        } catch { XCTFail("Export observation could not record or release the created capability") }
      })
    let operation = Task { try await service.exportValidated() }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    let registered = try String(contentsOf: receipt, encoding: .utf8)
    operation.cancel()
    gate.release.signal()
    let export = try await operation.value
    XCTAssertEqual(registered, "\(export.id.uuidString)\n\(export.url.path)")
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: export.url)), records)
    await us4AssertState(store, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), original)
    try await service.removeExport(export)
    XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path))
    XCTAssertEqual(try Data(contentsOf: fixture.live), original)
  }

  func testValidatedExportOwnsExactFullSnapshotWithoutChangingLiveArchive() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let records = try US4ArchiveFixture.records()
    try ArchiveCodec.encode(records).write(to: fixture.live)
    let store = fixture.store()
    let before = try await store.load()
    let bytes = try Data(contentsOf: fixture.live)
    let service = fixture.service(store)
    let export = try await service.exportValidated()
    XCTAssertNotEqual(export.url, fixture.live)
    XCTAssertEqual(
      export.url.deletingLastPathComponent().standardizedFileURL.path,
      fixture.exports.standardizedFileURL.path)
    XCTAssertTrue(export.url.lastPathComponent.hasPrefix("ReturnQueue-backup-"))
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: export.url)), records)
    XCTAssertEqual(try records[0].moneyReceivedCents(), 5_000)
    XCTAssertEqual(try records[0].storeCreditCents(), 3_000)
    await us4AssertState(store, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), bytes)
    try await service.removeExport(export)
    XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path))
    XCTAssertEqual(try Data(contentsOf: fixture.live), bytes)
  }

  func testEmptyReadyExportIsValidWithoutCreatingLiveDatabase() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let store = fixture.store()
    let before = try await store.load()
    let service = fixture.service(store)
    let export = try await service.exportValidated()
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: export.url)), [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.live.path))
    await us4AssertState(store, .ready(before))
    try await service.removeExport(export)
  }

  func testBlockedExportNeverSubstitutesLastCommittedSnapshot() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    try ArchiveCodec.encode(try US4ArchiveFixture.records()).write(to: fixture.live)
    let store = fixture.store()
    let before = try await store.load()
    let corrupt = Data("private original malformed archive".utf8)
    try corrupt.write(to: fixture.live)
    do { _ = try await store.load() } catch {
      XCTAssertEqual(error as? ReturnStoreFailure, .readFailed)
    }
    let service = fixture.service(store)
    do {
      _ = try await service.exportValidated()
      XCTFail("Blocked data exported as a valid current snapshot")
    } catch { XCTAssertEqual(error as? ReturnStoreFailure, .readBlocked) }
    await us4AssertState(store, .readFailed(.readFailed, lastCommitted: before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), corrupt)
    let raw = fixture.directory.appendingPathComponent("raw.json")
    try await store.copyRawArchive(to: raw)
    XCTAssertEqual(try Data(contentsOf: raw), corrupt)
  }

  func testPreviewCountsAndImmutableSelectionSurviveSourceModificationAndRemoval() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let original = StorageFixtures.item()
    try ArchiveCodec.encode([original]).write(to: fixture.live)
    let records = try US4ArchiveFixture.records()
    try ArchiveCodec.encode(records).write(to: fixture.selected)
    let store = fixture.store()
    let before = try await store.load()
    let bytes = try Data(contentsOf: fixture.live)
    let service = fixture.service(store)
    let preview = try await service.previewImport(from: fixture.selected)
    XCTAssertEqual(preview.returnCount, 2)
    XCTAssertEqual(preview.reimbursementCount, 3)
    XCTAssertEqual(preview.currentReturnCount, 1)
    await us4AssertState(store, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), bytes)
    try ArchiveCodec.encode([]).write(to: fixture.selected)
    try FileManager.default.removeItem(at: fixture.selected)
    let committed = try await service.restore(preview.id, confirmation: .confirmed)
    XCTAssertEqual(committed.records, records)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.live)), records)
  }

  func testMalformedAndOversizedSelectionsPreserveLiveBytesAndState() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    try ArchiveCodec.encode([StorageFixtures.item()]).write(to: fixture.live)
    let store = fixture.store()
    let before = try await store.load()
    let original = try Data(contentsOf: fixture.live)
    let service = fixture.service(store)
    let valid = try ArchiveCodec.encode(try US4ArchiveFixture.records())
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    object["version"] = 2
    let badVersion = try JSONSerialization.data(withJSONObject: object)
    var duplicate = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    let records = try XCTUnwrap(duplicate["records"] as? [[String: Any]])
    duplicate["records"] = [records[0], records[0]]
    let badDuplicates = try JSONSerialization.data(withJSONObject: duplicate)
    var invalidDay = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    var dayRecords = try XCTUnwrap(invalidDay["records"] as? [[String: Any]])
    dayRecords[0]["returnBy"] = "2026-02-30"
    invalidDay["records"] = dayRecords
    var invalidParent = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    var parentRecords = try XCTUnwrap(invalidParent["records"] as? [[String: Any]])
    var events = try XCTUnwrap(parentRecords[0]["reimbursements"] as? [[String: Any]])
    events[0]["returnItemID"] = UUID().uuidString
    parentRecords[0]["reimbursements"] = events
    invalidParent["records"] = parentRecords
    let badDay = try JSONSerialization.data(withJSONObject: invalidDay)
    let badParent = try JSONSerialization.data(withJSONObject: invalidParent)
    for invalid in [
      Data("broken".utf8), badVersion, badDuplicates, badDay, badParent, valid + Data([0xFF]),
    ] {
      try invalid.write(to: fixture.selected)
      do {
        _ = try await service.previewImport(from: fixture.selected)
        XCTFail("Invalid input produced a replacement capability")
      } catch { XCTAssertEqual(error as? ArchiveFailure, .invalidArchive) }
      await us4AssertState(store, .ready(before))
      XCTAssertEqual(try Data(contentsOf: fixture.live), original)
    }
    try StorageFixtures.writeRepeatedBytes(to: fixture.selected, count: 20 * 1_024 * 1_024 + 1)
    do {
      _ = try await service.previewImport(from: fixture.selected)
      XCTFail("Oversized selection accepted")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .archiveTooLarge) }
    await us4AssertState(store, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), original)
  }

  func testExactlyBoundedEmptyArchiveAndMissingNonregularSources() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let store = fixture.store()
    let before = try await store.load()
    let service = fixture.service(store)
    var bounded = try ArchiveCodec.encode([])
    bounded.append(Data(repeating: 0x20, count: 20 * 1_024 * 1_024 - bounded.count))
    try bounded.write(to: fixture.selected)
    let preview = try await service.previewImport(from: fixture.selected)
    XCTAssertEqual(preview.returnCount, 0)
    await service.discardPreview(preview.id)
    try FileManager.default.removeItem(at: fixture.selected)
    for source in [fixture.selected, fixture.directory] {
      do {
        _ = try await service.previewImport(from: source)
        XCTFail("Unavailable or nonregular source accepted")
      } catch { XCTAssertEqual(error as? ArchiveFailure, .sourceUnavailable) }
    }
    await us4AssertState(store, .ready(before))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.live.path))
  }

  func testExportCleanupRejectsForgedCapabilitiesAndPreservesUserCopy() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    try ArchiveCodec.encode([StorageFixtures.item()]).write(to: fixture.live)
    let store = fixture.store()
    _ = try await store.load()
    let service = fixture.service(store)
    let export = try await service.exportValidated()
    try FileManager.default.copyItem(at: export.url, to: fixture.selected)
    let saved = try Data(contentsOf: fixture.selected)
    for forged in [
      ArchiveExport(id: UUID(), url: export.url),
      ArchiveExport(id: export.id, url: fixture.live),
      ArchiveExport(id: export.id, url: fixture.selected),
    ] {
      do {
        try await service.removeExport(forged)
        XCTFail("Unowned export cleanup accepted")
      } catch { XCTAssertEqual(error as? ArchiveFailure, .invalidExport) }
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: export.url.path))
    XCTAssertEqual(try Data(contentsOf: fixture.selected), saved)
    try FileManager.default.removeItem(at: export.url)
    try await service.removeExport(export)
    XCTAssertEqual(try Data(contentsOf: fixture.selected), saved)
    XCTAssertEqual(try Data(contentsOf: fixture.live), saved)
  }

  func testActualCleanupPermissionFailureRetainsCapabilityForExplicitRetry() async throws {
    XCTAssertFalse(StorageFixtures.isRoot, "Native permission oracle requires a non-root account")
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let store = fixture.store()
    _ = try await store.load()
    let service = fixture.service(store)
    let export = try await service.exportValidated()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: fixture.exports.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: fixture.exports.path)
    }
    do {
      try await service.removeExport(export)
      XCTFail("Read-only directory unexpectedly allowed owned cleanup")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .cleanupFailed) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: export.url.path))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: fixture.exports.path)
    try await service.removeExport(export)
    XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path))
  }

  func testExportDestinationFailurePreservesLiveArchiveAndUnrelatedExistingFile() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let original = try ArchiveCodec.encode(US4ArchiveFixture.records())
    try original.write(to: fixture.live)
    let unrelated = Data("unrelated user file".utf8)
    try unrelated.write(to: fixture.exports)
    let store = fixture.store()
    let before = try await store.load()
    let service = fixture.service(store)
    do {
      _ = try await service.exportValidated()
      XCTFail("Existing regular file accepted as export directory")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .exportFailed) }
    await us4AssertState(store, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), original)
    XCTAssertEqual(try Data(contentsOf: fixture.exports), unrelated)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted(),
      ["exports", "live.json"])
  }
}

struct US4ArchiveFixture {
  let directory: URL
  let live: URL
  let selected: URL
  let exports: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    live = directory.appendingPathComponent("live.json")
    selected = directory.appendingPathComponent("selection.json")
    exports = directory.appendingPathComponent("exports")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func store() -> ReturnStore { ReturnStore(persistence: ReturnRepository(fileURL: live)) }
  func service(_ store: ReturnStore) -> ArchiveService {
    ArchiveService(store: store, directory: exports)
  }
  func remove() throws { try FileManager.default.removeItem(at: directory) }

  static func records() throws -> [ReturnItem] {
    let day = try CalendarDay(iso8601: "2026-10-01")
    var partial = ReturnItem(
      title: "Imported jacket", merchant: "Example Store", dropOffLocation: "UPS",
      returnBy: day, purchaseDate: day, droppedOffDate: day, expectedRefundDate: day,
      purchasePriceCents: 15_000, expectedRefundCents: 10_000, state: .closed,
      closureOutcome: .partialRefund, closureNote: "Accepted return fee", notes: "Retained note",
      policyReference: "Receipt terms", createdAt: StorageFixtures.instant)
    partial.reimbursements = [
      Reimbursement(
        returnItemID: partial.id, date: day, amountCents: 5_000, kind: .money, note: "Cash"),
      Reimbursement(returnItemID: partial.id, date: day, amountCents: 3_000, kind: .storeCredit),
    ]
    var kept = ReturnItem(
      title: "Imported kept shoes", merchant: "Other Store", state: .kept,
      closureNote: "Prior denied closure", createdAt: StorageFixtures.instant)
    kept.reimbursements = [
      Reimbursement(returnItemID: kept.id, date: day, amountCents: 125, kind: .storeCredit)
    ]
    return try [partial.validated(), kept.validated()]
  }
}
