import Foundation
import XCTest

@testable import ReturnQueueCore

final class ArchiveTests: XCTestCase {
  func testHandwrittenP1FixtureDecodesWithoutDependingOnTheEncoder() throws {
    let decoded = try ArchiveCodec.decode(Data(CoreFixtures.archiveJSON.utf8))
    var expected = CoreFixtures.item()
    expected.reimbursements = [CoreFixtures.event()]
    XCTAssertEqual(decoded, [expected])
    XCTAssertNil(decoded[0].expectedRefundCents)
    XCTAssertEqual(decoded[0].state, .planned)
  }

  func testAllP1FieldsAndSeparateLedgerRoundTrip() throws {
    var value = CoreFixtures.item()
    value.dropOffLocation = "Main Street counter"
    value.returnBy = try CalendarDay(iso8601: "2026-10-06")
    value.purchaseDate = try CalendarDay(iso8601: "2026-09-20")
    value.droppedOffDate = try CalendarDay(iso8601: "2026-10-01")
    value.expectedRefundDate = try CalendarDay(iso8601: "2026-10-10")
    value.purchasePriceCents = 12_999
    value.expectedRefundCents = 10_000
    value.state = .closed
    value.closureOutcome = .partialRefund
    value.closureNote = "Accepted a return fee"
    value.notes = "Keep the shipping confirmation"
    value.policyReference = "https://example.com/order/123"
    value.updatedAt = value.createdAt.addingTimeInterval(-60)
    var money = CoreFixtures.event()
    money.note = "First installment"
    var credit = CoreFixtures.event(
      id: CoreFixtures.secondEventID, cents: 3_000, kind: .storeCredit)
    credit.date = try CalendarDay(iso8601: "2026-10-02")
    credit.note = "Store credit issued"
    value.reimbursements = [money, credit]
    let normalized = try value.validated()
    let data = try ArchiveCodec.encode([value])
    XCTAssertEqual(try ArchiveCodec.decode(data), [normalized])
    XCTAssertEqual(try ArchiveCodec.decode(ArchiveCodec.encode([])), [])
  }

  func testEncoderWritesEveryNullableKeyAsExplicitNullAndIntegerMilliseconds() throws {
    let data = try ArchiveCodec.encode([CoreFixtures.item()])
    let document = try object(from: data)
    XCTAssertEqual(document["format"] as? String, "com.azamat163.returnqueue.p1")
    XCTAssertEqual(document["version"] as? Int, 1)
    let records = try XCTUnwrap(document["records"] as? [[String: Any]])
    let record = try XCTUnwrap(records.first)
    XCTAssertEqual(record.count, 19)
    for key in [
      "dropOffLocation", "returnBy", "purchaseDate", "droppedOffDate", "expectedRefundDate",
      "purchasePriceCents", "expectedRefundCents", "closureOutcome", "closureNote",
      "policyReference",
    ] {
      XCTAssertTrue(record[key] is NSNull, key)
    }
    XCTAssertEqual((record["createdAt"] as? NSNumber)?.int64Value, 1_800_000_000_123)
    XCTAssertEqual((record["updatedAt"] as? NSNumber)?.int64Value, 1_800_000_000_123)
    XCTAssertEqual(try ArchiveCodec.decode(data), [try CoreFixtures.item().validated()])
  }

  func testEncoderNormalizesFormInputButDecoderRejectsUnnormalizedImport() throws {
    var value = CoreFixtures.item()
    value.title = "  Running shoes\n"
    value.dropOffLocation = " \t"
    value.notes = "  Bring the box  "
    let data = try ArchiveCodec.encode([value])
    XCTAssertEqual(try ArchiveCodec.decode(data), [try value.validated()])
    for (field, text) in [
      ("title", " Running shoes"), ("merchant", "Example Store "),
      ("dropOffLocation", ""), ("policyReference", " \t"), ("closureNote", ""),
      ("notes", " Leading space"),
    ] {
      let malformed = try recordData { $0[field] = text }
      XCTAssertThrowsError(try ArchiveCodec.decode(malformed), field)
    }
    let eventData = try reimbursementData { $0["note"] = " Trailing and leading " }
    XCTAssertThrowsError(try ArchiveCodec.decode(eventData))
  }

  func testEveryEnvelopeRecordAndEventKeyIsRequiredEvenWhenNullable() throws {
    let envelope = try fixtureObject()
    for key in envelope.keys.sorted() {
      var missing = envelope
      missing.removeValue(forKey: key)
      XCTAssertThrowsError(try ArchiveCodec.decode(data(from: missing)), key)
    }
    let records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
    for key in records[0].keys.sorted() {
      let missing = try recordData { $0.removeValue(forKey: key) }
      XCTAssertThrowsError(try ArchiveCodec.decode(missing), key)
    }
    let events = try XCTUnwrap(records[0]["reimbursements"] as? [[String: Any]])
    for key in events[0].keys.sorted() {
      let missing = try reimbursementData { $0.removeValue(forKey: key) }
      XCTAssertThrowsError(try ArchiveCodec.decode(missing), key)
    }
  }

  func testUnknownAndP2KeysAreRejectedAtEveryLevel() throws {
    var envelope = try fixtureObject()
    envelope["settings"] = [:] as [String: String]
    XCTAssertThrowsError(try ArchiveCodec.decode(data(from: envelope)))
    for key in ["attachment", "reminder", "summary", "unknownField"] {
      let unknown = try recordData { $0[key] = NSNull() }
      XCTAssertThrowsError(try ArchiveCodec.decode(unknown), key)
    }
    let unknown = try reimbursementData { $0["bankConfirmed"] = true }
    XCTAssertThrowsError(try ArchiveCodec.decode(unknown))
  }

  func testWrongMarkersVersionsAndLegacyDraftAreNeverImported() {
    for json in [
      "{\"format\":\"different\",\"version\":1,\"records\":[]}",
      "{\"format\":\"com.azamat163.returnqueue.p1\",\"version\":2,\"records\":[]}",
      "{\"format\":\"com.azamat163.returnqueue.p1\",\"version\":0,\"records\":[]}",
      "{\"version\":1,\"items\":[]}", "[]", "{}", "null",
    ] {
      XCTAssertThrowsError(try ArchiveCodec.decode(Data(json.utf8)), json)
    }
  }

  func testIntegerFieldsRejectStringsBooleansFractionsAndExponents() {
    let fields = [
      ("\"version\":1", "\"version\":"),
      ("\"createdAt\":1800000000123", "\"createdAt\":"),
      ("\"purchasePriceCents\":null", "\"purchasePriceCents\":"),
      ("\"amountCents\":5000", "\"amountCents\":"),
    ]
    for (original, prefix) in fields {
      for token in ["\"1\"", "true", "false", "1.0", "1.5", "1e0", "1E+0"] {
        let json = CoreFixtures.archiveJSON.replacingOccurrences(of: original, with: prefix + token)
        XCTAssertThrowsError(try ArchiveCodec.decode(Data(json.utf8)), original + " -> " + token)
      }
    }
  }

  func testWrongJSONTypesDoNotMasqueradeAsOptionalValues() throws {
    let invalid: [(String, Any)] = [
      ("title", 42), ("merchant", NSNull()), ("dropOffLocation", false),
      ("returnBy", 1), ("purchaseDate", [:] as [String: String]),
      ("notes", NSNull()), ("policyReference", [] as [String]),
      ("state", true), ("closureOutcome", 1), ("currency", NSNull()),
      ("reimbursements", [:] as [String: String]),
    ]
    for (key, invalidValue) in invalid {
      let malformed = try recordData { $0[key] = invalidValue }
      XCTAssertThrowsError(try ArchiveCodec.decode(malformed), key)
    }
    for key in ["id", "returnItemID", "date", "kind", "note", "amountCents"] {
      let malformed = try reimbursementData { $0[key] = NSNull() }
      XCTAssertThrowsError(try ArchiveCodec.decode(malformed), key)
    }
  }

  func testDuplicateKeysIncludingEscapedEquivalentKeysAreRejected() {
    let replacements = [
      ("\"version\":1", "\"version\":1,\"version\":1"),
      ("\"title\":\"Running shoes\"", "\"title\":\"Running shoes\",\"title\":\"Other\""),
      ("\"title\":\"Running shoes\"", "\"title\":\"Running shoes\",\"\\u0074itle\":\"Other\""),
      ("\"amountCents\":5000", "\"amountCents\":5000,\"amountCents\":5000"),
    ]
    for (original, replacement) in replacements {
      let json = CoreFixtures.archiveJSON.replacingOccurrences(of: original, with: replacement)
      XCTAssertThrowsError(try ArchiveCodec.decode(Data(json.utf8)), replacement)
    }
  }

  func testMalformedTrailingAndInvalidUTF8InputIsRejected() {
    for json in [
      "{", "{\"format\":}", "{\"format\":\"unterminated}",
      "{\"format\":\"com.azamat163.returnqueue.p1\",\"version\":01,\"records\":[]}",
      CoreFixtures.archiveJSON + " garbage", CoreFixtures.archiveJSON + "{}",
      CoreFixtures.archiveJSON + " // comment",
    ] {
      XCTAssertThrowsError(try ArchiveCodec.decode(Data(json.utf8)))
    }
    XCTAssertThrowsError(try ArchiveCodec.decode(Data([0xFF, 0xFE, 0x80])))
    var embeddedInvalidUTF8 = Data(CoreFixtures.archiveJSON.utf8)
    embeddedInvalidUTF8.insert(0xFF, at: embeddedInvalidUTF8.count / 2)
    XCTAssertThrowsError(try ArchiveCodec.decode(embeddedInvalidUTF8))
  }

  func testExcessiveNestingIsRejectedWithoutUnboundedRecursion() throws {
    // Exercise the syntax scanner before archive schema checks can reject the wrapper.
    func scanner(arrayDepth: Int) throws -> ArchiveJSONScanner {
      let json =
        "{\"nested\":" + String(repeating: "[", count: arrayDepth) + "0"
        + String(repeating: "]", count: arrayDepth) + "}"
      return try ArchiveJSONScanner(data: Data(json.utf8))
    }
    var atLimit = try scanner(arrayDepth: 63)
    XCTAssertNoThrow(try atLimit.validate())
    var overLimit = try scanner(arrayDepth: 64)
    XCTAssertThrowsError(try overLimit.validate())
  }

  func testInvalidCalendarDaysAndUnknownEnumsRejectTheWholeArchive() throws {
    for key in ["returnBy", "purchaseDate", "droppedOffDate", "expectedRefundDate"] {
      let malformed = try recordData { $0[key] = "2026-02-30" }
      XCTAssertThrowsError(try ArchiveCodec.decode(malformed), key)
    }
    let invalidEventDate = try reimbursementData { $0["date"] = "1900-02-29" }
    XCTAssertThrowsError(try ArchiveCodec.decode(invalidEventDate))
    for (key, value) in [("state", "refunded"), ("closureOutcome", "approved")] {
      let malformed = try recordData { $0[key] = value }
      XCTAssertThrowsError(try ArchiveCodec.decode(malformed), key)
    }
    let invalidKind = try reimbursementData { $0["kind"] = "bankTransfer" }
    XCTAssertThrowsError(try ArchiveCodec.decode(invalidKind))
  }

  func testImportedAmountsCurrenciesAndTimestampBoundsAreValidated() throws {
    for key in ["purchasePriceCents", "expectedRefundCents"] {
      for amount in [-1, 100_000_001, Int.max] {
        let malformed = try recordData { $0[key] = amount }
        XCTAssertThrowsError(try ArchiveCodec.decode(malformed), key)
      }
    }
    for amount in [0, -1, 100_000_001, Int.max] {
      let malformed = try reimbursementData { $0["amountCents"] = amount }
      XCTAssertThrowsError(try ArchiveCodec.decode(malformed))
    }
    let nonUSD = try recordData { $0["currency"] = "EUR" }
    XCTAssertThrowsError(try ArchiveCodec.decode(nonUSD))
    for key in ["createdAt", "updatedAt"] {
      for value: Int64 in [-62_135_596_800_001, 253_402_300_800_000] {
        let malformed = try recordData { $0[key] = value }
        XCTAssertThrowsError(try ArchiveCodec.decode(malformed), key)
      }
    }
  }

  func testImportedTextMustRespectGraphemeLimits() throws {
    for (field, limit) in [
      ("title", 120), ("merchant", 120), ("dropOffLocation", 200), ("notes", 4_000),
      ("policyReference", 1_000), ("closureNote", 1_000),
    ] {
      let malformed = try recordData { $0[field] = String(repeating: "x", count: limit + 1) }
      XCTAssertThrowsError(try ArchiveCodec.decode(malformed), field)
    }
    let malformed = try reimbursementData { $0["note"] = String(repeating: "x", count: 1_001) }
    XCTAssertThrowsError(try ArchiveCodec.decode(malformed))
  }

  func testImportRequiresValidManualClosureAndRetainsReopenedHistory() throws {
    let missingOutcome = try recordData { $0["state"] = "closed" }
    XCTAssertThrowsError(try ArchiveCodec.decode(missingOutcome))
    let unexpectedOutcome = try recordData { $0["closureOutcome"] = "fullRefund" }
    XCTAssertThrowsError(try ArchiveCodec.decode(unexpectedOutcome))
    for expected in [4_000, 10_000] {
      let missingNote = try recordData {
        $0["state"] = "closed"
        $0["closureOutcome"] = "partialRefund"
        $0["expectedRefundCents"] = expected
      }
      XCTAssertThrowsError(try ArchiveCodec.decode(missingNote))
    }
    let reopened = try recordData {
      $0["closureNote"] = "Previous closure explanation"
      $0["state"] = "droppedOff"
    }
    let value = try XCTUnwrap(ArchiveCodec.decode(reopened).first)
    XCTAssertEqual(value.closureNote, "Previous closure explanation")
    XCTAssertNil(value.closureOutcome)
    XCTAssertEqual(value.reimbursements, [CoreFixtures.event()])
  }

  func testUUIDsMustUseStandardFormAndMatchingParents() throws {
    for uuid in [
      "not-a-uuid", "00000000000000000000000000000001", "{00000000-0000-0000-0000-000000000001}",
    ] {
      let invalidRecord = try recordData { $0["id"] = uuid }
      XCTAssertThrowsError(try ArchiveCodec.decode(invalidRecord))
      let invalidEvent = try reimbursementData { $0["id"] = uuid }
      XCTAssertThrowsError(try ArchiveCodec.decode(invalidEvent))
    }
    let wrongParent = try reimbursementData {
      $0["returnItemID"] = CoreFixtures.secondRecordID.uuidString
    }
    XCTAssertThrowsError(try ArchiveCodec.decode(wrongParent))
  }

  func testUUIDCaseIsIdentityInsensitiveAndRecordEventNamespacesAreSeparate() throws {
    let uppercase = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    let lowercase = uppercase.lowercased()
    let data = try recordData {
      $0["id"] = uppercase
      var events = try XCTUnwrap($0["reimbursements"] as? [[String: Any]])
      events[0]["returnItemID"] = lowercase
      events[0]["id"] = lowercase
      $0["reimbursements"] = events
    }
    let value = try XCTUnwrap(ArchiveCodec.decode(data).first)
    XCTAssertEqual(value.id, value.reimbursements[0].id)
    XCTAssertEqual(value.id, value.reimbursements[0].returnItemID)
  }

  func testRecordIDsAndEventIDsAreUniqueAcrossTheArchive() throws {
    let first = CoreFixtures.item()
    XCTAssertThrowsError(try ArchiveCodec.encode([first, first]))
    var duplicateDocument = try fixtureObject()
    let record = try XCTUnwrap((duplicateDocument["records"] as? [[String: Any]])?.first)
    duplicateDocument["records"] = [record, record]
    XCTAssertThrowsError(try ArchiveCodec.decode(data(from: duplicateDocument)))
    var one = CoreFixtures.item()
    one.reimbursements = [CoreFixtures.event()]
    var two = CoreFixtures.item(id: CoreFixtures.secondRecordID)
    two.reimbursements = [CoreFixtures.event(parentID: two.id)]
    XCTAssertThrowsError(try ArchiveCodec.encode([one, two]))
    var secondObject = record
    secondObject["id"] = CoreFixtures.secondRecordID.uuidString
    var events = try XCTUnwrap(secondObject["reimbursements"] as? [[String: Any]])
    events[0]["returnItemID"] = CoreFixtures.secondRecordID.uuidString
    secondObject["reimbursements"] = events
    duplicateDocument["records"] = [record, secondObject]
    XCTAssertThrowsError(try ArchiveCodec.decode(data(from: duplicateDocument)))
  }

  func testRecordLimitAcceptsTenThousandAndRejectsOneMore() throws {
    var records = (1...10_000).map { CoreFixtures.item(id: CoreFixtures.numberedID($0)) }
    let valid = try ArchiveCodec.encode(records)
    XCTAssertEqual(try ArchiveCodec.decode(valid).count, 10_000)
    records.append(CoreFixtures.item(id: CoreFixtures.numberedID(10_001)))
    XCTAssertThrowsError(try ArchiveCodec.encode(records)) { error in
      XCTAssertEqual(error as? ReturnQueueError, .tooManyRecords)
    }
    var envelope = try object(from: valid)
    var objects = try XCTUnwrap(envelope["records"] as? [[String: Any]])
    var extra = objects[0]
    extra["id"] = CoreFixtures.numberedID(10_001).uuidString
    objects.append(extra)
    envelope["records"] = objects
    XCTAssertThrowsError(try ArchiveCodec.decode(data(from: envelope))) { error in
      XCTAssertEqual(error as? ReturnQueueError, .tooManyRecords)
    }
  }

  func testEventLimitIsGlobalRatherThanOnlyPerRecord() throws {
    var one = CoreFixtures.item()
    var two = CoreFixtures.item(id: CoreFixtures.secondRecordID)
    one.reimbursements = (1...5_000).map {
      CoreFixtures.event(id: CoreFixtures.numberedID($0), parentID: one.id, cents: 1)
    }
    two.reimbursements = (5_001...10_000).map {
      CoreFixtures.event(id: CoreFixtures.numberedID($0), parentID: two.id, cents: 1)
    }
    let valid = try ArchiveCodec.encode([one, two])
    XCTAssertEqual(try ArchiveCodec.decode(valid).flatMap(\.reimbursements).count, 10_000)
    two.reimbursements.append(
      CoreFixtures.event(id: CoreFixtures.numberedID(10_001), parentID: two.id, cents: 1))
    XCTAssertThrowsError(try ArchiveCodec.encode([one, two])) { error in
      XCTAssertEqual(error as? ReturnQueueError, .tooManyEvents)
    }
    var envelope = try object(from: valid)
    var records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
    var events = try XCTUnwrap(records[1]["reimbursements"] as? [[String: Any]])
    var extra = events[0]
    extra["id"] = CoreFixtures.numberedID(10_001).uuidString
    events.append(extra)
    records[1]["reimbursements"] = events
    envelope["records"] = records
    XCTAssertThrowsError(try ArchiveCodec.decode(data(from: envelope))) { error in
      XCTAssertEqual(error as? ReturnQueueError, .tooManyEvents)
    }
  }

  func testByteLimitAcceptsTheBoundaryAndRejectsOneMoreBeforeParsing() throws {
    let limit = 20 * 1_024 * 1_024
    var valid = try ArchiveCodec.encode([])
    valid.append(Data(repeating: 0x20, count: limit - valid.count))
    XCTAssertEqual(try ArchiveCodec.decode(valid), [])
    valid.append(0x20)
    XCTAssertThrowsError(try ArchiveCodec.decode(valid)) { error in
      XCTAssertEqual(error as? ReturnQueueError, .archiveTooLarge)
    }
    XCTAssertThrowsError(try ArchiveCodec.decode(Data(repeating: 0xFF, count: limit + 1))) {
      error in
      XCTAssertEqual(error as? ReturnQueueError, .archiveTooLarge)
    }
  }

  func testEncoderAlsoRejectsOversizedValidDomainContent() {
    let notes = String(repeating: "👨‍👩‍👧‍👦", count: 4_000)
    let records = (1...230).map { number in
      var item = CoreFixtures.item(id: CoreFixtures.numberedID(number))
      item.notes = notes
      return item
    }
    XCTAssertThrowsError(try ArchiveCodec.encode(records)) { error in
      XCTAssertEqual(error as? ReturnQueueError, .archiveTooLarge)
    }
  }

  private func fixtureObject() throws -> [String: Any] {
    try object(from: Data(CoreFixtures.archiveJSON.utf8))
  }

  private func object(from data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func data(from object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private func recordData(_ mutate: (inout [String: Any]) throws -> Void) throws -> Data {
    var envelope = try fixtureObject()
    var records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
    try mutate(&records[0])
    envelope["records"] = records
    return try data(from: envelope)
  }

  private func reimbursementData(_ mutate: (inout [String: Any]) throws -> Void) throws -> Data {
    try recordData { record in
      var events = try XCTUnwrap(record["reimbursements"] as? [[String: Any]])
      try mutate(&events[0])
      record["reimbursements"] = events
    }
  }
}
