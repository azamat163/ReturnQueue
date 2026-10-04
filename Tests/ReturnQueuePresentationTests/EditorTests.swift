import Foundation
import ReturnQueueCore
import ReturnQueuePresentation
import ReturnQueueStorage
import XCTest

@MainActor
final class EditorTests: XCTestCase {
  func testMinimalSaveTrimsRequiredInputsAndKeepsOptionalUnknowns() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let editor = ReturnEditorModel(session: session, now: { PresentationFixture.instant })
    editor.draft.title = "  Running shoes\n"
    editor.draft.merchant = " Example Store "
    let saved = await editor.save()
    XCTAssertTrue(saved)
    XCTAssertEqual(editor.saveState, .saved)
    let item = try XCTUnwrap(session.snapshot?.records.first)
    XCTAssertEqual(item.title, "Running shoes")
    XCTAssertEqual(item.merchant, "Example Store")
    XCTAssertEqual(item.currency, "USD")
    XCTAssertEqual(item.createdAt, PresentationFixture.instant)
    XCTAssertNil(item.returnBy)
    XCTAssertNil(item.purchaseDate)
    XCTAssertNil(item.expectedRefundDate)
    XCTAssertNil(item.purchasePriceCents)
    XCTAssertNil(item.expectedRefundCents)
    XCTAssertNil(item.dropOffLocation)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), [item])
  }

  func testOptionalZeroUSDAndGregorianDatesRoundTrip() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let editor = ReturnEditorModel(session: session)
    editor.draft.title = "Shoes"
    editor.draft.merchant = "Store"
    editor.draft.purchasePrice = "0"
    editor.draft.expectedRefund = "19.99"
    editor.draft.purchaseDate = "2000-02-29"
    editor.draft.returnBy = "2026-10-06"
    editor.draft.expectedRefundDate = "2026-10-15"
    let saved = await editor.save()
    XCTAssertTrue(saved)
    let item = try XCTUnwrap(session.snapshot?.records.first)
    XCTAssertEqual(item.purchasePriceCents, 0)
    XCTAssertEqual(item.expectedRefundCents, 1_999)
    XCTAssertEqual(item.purchaseDate, try CalendarDay(iso8601: "2000-02-29"))
    XCTAssertEqual(item.returnBy, try CalendarDay(iso8601: "2026-10-06"))
    XCTAssertEqual(item.expectedRefundDate, try CalendarDay(iso8601: "2026-10-15"))
    let restarted = fixture.session()
    try await restarted.load()
    XCTAssertEqual(restarted.snapshot?.records, [item])
  }

  func testInvalidInputsReportTheirFieldsBeforeAnyArchiveIsWritten() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = session.snapshot
    let cases: [(ReturnEditorField, String)] = [
      (.title, " \n"), (.merchant, "\t"), (.title, String(repeating: "👨‍👩‍👧", count: 121)),
      (.merchant, String(repeating: "x", count: 121)),
      (.dropOffLocation, String(repeating: "x", count: 201)),
      (.policyReference, String(repeating: "x", count: 1_001)),
      (.notes, String(repeating: "x", count: 4_001)),
      (.returnBy, "2026-02-30"), (.purchaseDate, "1900-02-29"),
      (.expectedRefundDate, "10/06/2026"), (.purchasePrice, "1.234"),
      (.expectedRefund, "$10"), (.expectedRefund, "1000000.01"),
      (.purchasePrice, "-1"),
    ]
    for (field, value) in cases {
      let editor = ReturnEditorModel(session: session)
      editor.draft.title = "Shoes"
      editor.draft.merchant = "Store"
      switch field {
      case .title: editor.draft.title = value
      case .merchant: editor.draft.merchant = value
      case .dropOffLocation: editor.draft.dropOffLocation = value
      case .returnBy: editor.draft.returnBy = value
      case .purchaseDate: editor.draft.purchaseDate = value
      case .expectedRefundDate: editor.draft.expectedRefundDate = value
      case .purchasePrice: editor.draft.purchasePrice = value
      case .expectedRefund: editor.draft.expectedRefund = value
      case .policyReference: editor.draft.policyReference = value
      case .notes: editor.draft.notes = value
      }
      let draft = editor.draft
      let saved = await editor.save()
      XCTAssertFalse(saved, field.rawValue)
      XCTAssertNotNil(editor.fieldErrors[field], field.rawValue)
      XCTAssertEqual(editor.draft, draft)
      XCTAssertEqual(session.snapshot, before)
      XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archiveURL.path))
    }
  }

  func testGraphemeBoundaryAndBlankOptionalInputsAreNormalized() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let editor = ReturnEditorModel(session: session)
    let title = String(repeating: "👨‍👩‍👧", count: 120)
    editor.draft.title = " \(title) "
    editor.draft.merchant = " Store "
    editor.draft.dropOffLocation = " \t"
    editor.draft.purchasePrice = " "
    editor.draft.expectedRefund = "\t"
    editor.draft.returnBy = " "
    editor.draft.policyReference = " \n"
    let saved = await editor.save()
    XCTAssertTrue(saved)
    let item = try XCTUnwrap(session.snapshot?.records.first)
    XCTAssertEqual(item.title, title)
    XCTAssertNil(item.dropOffLocation)
    XCTAssertNil(item.purchasePriceCents)
    XCTAssertNil(item.expectedRefundCents)
    XCTAssertNil(item.returnBy)
    XCTAssertNil(item.policyReference)
  }

  func testDiscardingUnsavedEditLeavesSharedSnapshotAndDiskUntouched() async throws {
    let original = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [original])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    var editor: ReturnEditorModel? = ReturnEditorModel(
      session: session, item: original, revision: before.revision)
    editor?.draft.title = "Unsaved title"
    editor?.draft.expectedRefund = "500.00"
    editor = nil
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testEditPreservesLedgerStateClosureIdentityAndCreationInstant() async throws {
    var original = PresentationFixture.item()
    let day = try CalendarDay(iso8601: "2026-10-01")
    original.state = .closed
    original.closureOutcome = .fullRefund
    original.closureNote = "Confirmed manually"
    original.droppedOffDate = day
    original.expectedRefundCents = 8_000
    original.reimbursements = [
      Reimbursement(returnItemID: original.id, date: day, amountCents: 5_000, kind: .money),
      Reimbursement(returnItemID: original.id, date: day, amountCents: 3_000, kind: .storeCredit),
    ]
    let fixture = try PresentationFixture(records: [original])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let updateInstant = original.createdAt.addingTimeInterval(60)
    let editor = ReturnEditorModel(
      session: session, item: original, revision: before.revision, now: { updateInstant })
    editor.draft.title = "Edited shoes"
    editor.draft.notes = "Edited notes"
    let saved = await editor.save()
    XCTAssertTrue(saved)
    let item = try XCTUnwrap(session.snapshot?.records.first)
    XCTAssertEqual(item.title, "Edited shoes")
    XCTAssertEqual(item.notes, "Edited notes")
    XCTAssertEqual(item.updatedAt, updateInstant)
    XCTAssertEqual(item.id, original.id)
    XCTAssertEqual(item.createdAt, original.createdAt)
    XCTAssertEqual(item.state, original.state)
    XCTAssertEqual(item.reimbursements, original.reimbursements)
    XCTAssertEqual(item.droppedOffDate, original.droppedOffDate)
    XCTAssertEqual(item.closureOutcome, original.closureOutcome)
    XCTAssertEqual(item.closureNote, original.closureNote)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), [item])
  }

  func testFailedSaveKeepsDraftOldBytesAndStableCreationIdentityForRetry() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let gateURL = fixture.directory.appendingPathComponent("fail-write")
    try Data().write(to: gateURL)
    let candidateURL = fixture.directory.appendingPathComponent("candidate.json")
    let repository = ReturnRepository(fileURL: fixture.archiveURL) { stage in
      if case .replacement = stage, FileManager.default.fileExists(atPath: gateURL.path) {
        throw PresentationGateFailure.timedOut
      }
    }
    let persistence = RecordingPersistence(repository: repository, candidateURL: candidateURL)
    let session = fixture.session(persistence: persistence)
    try await session.load()
    let before = session.snapshot
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let editor = ReturnEditorModel(session: session, now: { PresentationFixture.instant })
    editor.draft.title = "Draft sneakers"
    editor.draft.merchant = "Store"
    let draft = editor.draft
    let saved = await editor.save()
    XCTAssertFalse(saved)
    guard case .failed = editor.saveState else { return XCTFail("Save failure not surfaced") }
    XCTAssertEqual(editor.draft, draft)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    let failedCandidate = try XCTUnwrap(ArchiveCodec.decode(Data(contentsOf: candidateURL)).last)
    try FileManager.default.removeItem(at: gateURL)
    let retried = await editor.save()
    XCTAssertTrue(retried)
    let committed = try XCTUnwrap(session.snapshot?.records.last)
    XCTAssertEqual(committed.id, failedCandidate.id)
    XCTAssertEqual(committed.createdAt, failedCandidate.createdAt)
    XCTAssertEqual(committed.title, draft.title)
  }

  func testStaleEditorRetainsDraftAndOriginalRevisionAfterSharedReload() async throws {
    let original = PresentationFixture.item()
    let fixture = try PresentationFixture(records: [original])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let revision = try XCTUnwrap(session.snapshot?.revision)
    let editor = ReturnEditorModel(session: session, item: original, revision: revision)
    editor.draft.title = "Stale title"
    _ = try await session.create(PresentationFixture.item())
    let latest = session.snapshot
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let firstSave = await editor.save()
    XCTAssertFalse(firstSave)
    XCTAssertEqual(editor.draft.title, "Stale title")
    XCTAssertEqual(session.snapshot, latest)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    try await session.load()
    let afterReload = session.snapshot
    let secondSave = await editor.save()
    XCTAssertFalse(secondSave)
    XCTAssertEqual(session.snapshot, afterReload)
    XCTAssertEqual(editor.draft.title, "Stale title")
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testDuplicateSaveDoesNotPublishEarlyOrCommitTwice() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let gate = PresentationGate()
    defer { gate.release.signal() }
    let session = fixture.session(persistence: gate.repository(at: fixture.archiveURL))
    try await session.load()
    let before = session.snapshot
    let editor = ReturnEditorModel(session: session)
    editor.draft.title = "Shoes"
    editor.draft.merchant = "Store"
    let first = Task { await editor.save() }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    XCTAssertEqual(editor.saveState, .saving)
    XCTAssertEqual(session.snapshot, before)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archiveURL.path))
    let duplicate = await editor.save()
    XCTAssertFalse(duplicate)
    XCTAssertEqual(editor.saveState, .saving)
    gate.release.signal()
    let saved = await first.value
    XCTAssertTrue(saved)
    XCTAssertEqual(session.snapshot?.records.count, 1)
    XCTAssertEqual(session.snapshot?.revision, try XCTUnwrap(before?.revision) + 1)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)).count, 1)
  }
}
