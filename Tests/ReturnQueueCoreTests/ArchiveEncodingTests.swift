import Foundation
import XCTest

@testable import ReturnQueueCore

final class ArchiveEncodingTests: XCTestCase {
  func testSmallSlashUnicodeArchiveKeepsExactLegacyPrettyBytes() throws {
    var item = CoreFixtures.item()
    item.title = "Receipt 🧾"
    item.merchant = "Fixture café"
    item.notes = "https://example.com/返金\nQuote \" and backslash \\"
    item.policyReference = "https://example.com/terms"
    let legacyEncoder = JSONEncoder()
    legacyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let legacy = try legacyEncoder.encode(ReturnArchive(records: [item]))
    XCTAssertLessThan(legacy.count, ArchiveCodec.maximumArchiveBytes)
    XCTAssertTrue(String(decoding: legacy, as: UTF8.self).contains(#"https:\/\/"#))
    let encoded = try ArchiveCodec.encode([item])
    XCTAssertEqual(encoded, legacy, "The ordinary branch must retain every legacy output byte")
    XCTAssertEqual(try ArchiveCodec.decode(encoded), [try item.validated()])
  }

  func testLegalCompactSlashArchiveEncodesWithinFrozenCapWithoutLosingValues() throws {
    let records = (0..<3000).map { index in
      ReturnItem(
        id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", Int32(index)))!,
        title: "Item \(index)", merchant: "Fixture merchant",
        notes: String(repeating: "/", count: 4000), createdAt: Date(timeIntervalSince1970: 0))
    }
    let compactEncoder = JSONEncoder()
    compactEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let compact = try compactEncoder.encode(ReturnArchive(records: records))
    XCTAssertEqual(compact.count, 13_240_955, "Keep the measured compatible input reproducible")
    XCTAssertLessThan(compact.count, ArchiveCodec.maximumArchiveBytes)
    let decoded = try ArchiveCodec.decode(compact)
    XCTAssertEqual(decoded, records)
    let legacyEncoder = JSONEncoder()
    legacyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let legacy = try legacyEncoder.encode(ReturnArchive(records: decoded))
    XCTAssertEqual(legacy.count, 25_807_974)
    XCTAssertGreaterThan(legacy.count, ArchiveCodec.maximumArchiveBytes)

    let encoded = try ArchiveCodec.encode(decoded)
    XCTAssertLessThanOrEqual(encoded.count, ArchiveCodec.maximumArchiveBytes)
    XCTAssertEqual(try ArchiveCodec.decode(encoded), records)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertEqual(object["format"] as? String, "com.azamat163.returnqueue.p1")
    XCTAssertEqual(object["version"] as? Int, 1)
    let objects = try XCTUnwrap(object["records"] as? [[String: Any]])
    XCTAssertEqual(objects.count, 3000)
    for record in objects {
      XCTAssertEqual(record.count, 19)
      for key in [
        "dropOffLocation", "returnBy", "purchaseDate", "droppedOffDate", "expectedRefundDate",
        "purchasePriceCents", "expectedRefundCents", "closureOutcome", "closureNote",
        "policyReference",
      ] {
        XCTAssertTrue(record[key] is NSNull, "Missing explicit null: \(key)")
      }
      XCTAssertEqual((record["createdAt"] as? NSNumber)?.int64Value, 0)
      XCTAssertEqual((record["updatedAt"] as? NSNumber)?.int64Value, 0)
    }
  }
}
