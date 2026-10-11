import Foundation
import ReturnQueueCore
import XCTest

@testable import ReturnQueueStorage

@MainActor
final class CompactArchiveRestoreTests: XCTestCase {
  func testCompactCapacityFallbackSurvivesRestoreReloadExportAndOrdinaryEdit() async throws {
    let fixture = try US4ArchiveFixture()
    defer { try? fixture.remove() }
    let records = (0..<3000).map { index in
      ReturnItem(
        id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", Int32(index)))!,
        title: "Item \(index)", merchant: "Fixture merchant",
        notes: String(repeating: "/", count: 4000), createdAt: Date(timeIntervalSince1970: 0))
    }
    let compactEncoder = JSONEncoder()
    compactEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let selected = try compactEncoder.encode(ReturnArchive(records: records))
    XCTAssertEqual(selected.count, 13_240_955)
    XCTAssertLessThan(selected.count, ArchiveCodec.maximumArchiveBytes)
    XCTAssertEqual(try ArchiveCodec.decode(selected), records)
    try selected.write(to: fixture.selected)
    try ArchiveCodec.encode([StorageFixtures.item()]).write(to: fixture.live)
    let store = fixture.store()
    let before = try await store.load()
    let beforeBytes = try Data(contentsOf: fixture.live)
    let service = fixture.service(store)
    let preview = try await service.previewImport(from: fixture.selected)
    XCTAssertEqual(preview.returnCount, 3000)
    XCTAssertEqual(preview.reimbursementCount, 0)
    XCTAssertEqual(preview.currentReturnCount, 1)
    await us4AssertState(store, .ready(before))
    XCTAssertEqual(try Data(contentsOf: fixture.live), beforeBytes)
    try ArchiveCodec.encode([]).write(to: fixture.selected)
    try FileManager.default.removeItem(at: fixture.selected)

    let restored = try await service.restore(preview.id, confirmation: .confirmed)
    XCTAssertEqual(restored.revision, before.revision + 1)
    XCTAssertEqual(restored.records, records)
    let restoredBytes = try Data(contentsOf: fixture.live)
    XCTAssertLessThanOrEqual(restoredBytes.count, ArchiveCodec.maximumArchiveBytes)
    XCTAssertEqual(try ArchiveCodec.decode(restoredBytes), records)
    do {
      _ = try await service.restore(preview.id, confirmation: .confirmed)
      XCTFail("A successfully consumed replacement token was reused")
    } catch { XCTAssertEqual(error as? ArchiveFailure, .invalidPreview) }
    await us4AssertState(store, .ready(restored))
    XCTAssertEqual(try Data(contentsOf: fixture.live), restoredBytes)

    let reloaded = try await store.load()
    XCTAssertEqual(reloaded.revision, restored.revision + 1)
    XCTAssertEqual(reloaded.records, records)
    let export = try await service.exportValidated()
    let exportBytes = try Data(contentsOf: export.url)
    XCTAssertLessThanOrEqual(exportBytes.count, ArchiveCodec.maximumArchiveBytes)
    XCTAssertEqual(try ArchiveCodec.decode(exportBytes), records)
    await us4AssertState(store, .ready(reloaded))

    var editedRecords = records
    editedRecords[0].title = "Edited receipt 🧾"
    editedRecords[0].updatedAt = Date(timeIntervalSince1970: 60)
    let edited = try await store.update(editedRecords[0], expectedRevision: reloaded.revision)
    XCTAssertEqual(edited.revision, reloaded.revision + 1)
    XCTAssertEqual(edited.records, editedRecords)
    XCTAssertEqual(try Data(contentsOf: export.url), exportBytes, "A later edit mutated the backup")
    XCTAssertLessThanOrEqual(
      try Data(contentsOf: fixture.live).count, ArchiveCodec.maximumArchiveBytes)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.live)), editedRecords)
    let afterEditReload = try await store.load()
    XCTAssertEqual(afterEditReload.revision, edited.revision + 1)
    XCTAssertEqual(afterEditReload.records, editedRecords)
    let afterEditExport = try await service.exportValidated()
    let afterEditExportBytes = try Data(contentsOf: afterEditExport.url)
    XCTAssertLessThanOrEqual(afterEditExportBytes.count, ArchiveCodec.maximumArchiveBytes)
    XCTAssertEqual(try ArchiveCodec.decode(afterEditExportBytes), editedRecords)
    await us4AssertState(store, .ready(afterEditReload))
    try await service.removeExport(export)
    try await service.removeExport(afterEditExport)
    XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: afterEditExport.url.path))
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.live)), editedRecords)
  }
}
