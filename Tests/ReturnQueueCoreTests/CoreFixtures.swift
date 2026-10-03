import Foundation
import ReturnQueueCore

enum CoreFixtures {
  static let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  static let eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  static let secondRecordID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
  static let secondEventID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
  static let instant = Date(timeIntervalSince1970: 1_800_000_000.123)
  static let eventDay = try! CalendarDay(iso8601: "2026-10-01")

  static func item(id: UUID = recordID) -> ReturnItem {
    ReturnItem(id: id, title: "Running shoes", merchant: "Example Store", createdAt: instant)
  }

  static func event(
    id: UUID = eventID, parentID: UUID = recordID, cents: Int = 5_000,
    kind: ReimbursementKind = .money
  ) -> Reimbursement {
    Reimbursement(
      id: id, returnItemID: parentID, date: eventDay, amountCents: cents, kind: kind)
  }

  static func numberedID(_ number: Int) -> UUID {
    let suffix = String(number, radix: 16)
    let padding = String(repeating: "0", count: 12 - suffix.count)
    return UUID(uuidString: "00000000-0000-0000-0000-\(padding)\(suffix)")!
  }

  // The decoder fixture is handwritten, independent of the encoder under test.
  static let archiveJSON = """
    {
      "format":"com.azamat163.returnqueue.p1",
      "version":1,
      "records":[{
        "id":"00000000-0000-0000-0000-000000000001",
        "title":"Running shoes",
        "merchant":"Example Store",
        "dropOffLocation":null,
        "returnBy":null,
        "purchaseDate":null,
        "droppedOffDate":null,
        "expectedRefundDate":null,
        "purchasePriceCents":null,
        "expectedRefundCents":null,
        "currency":"USD",
        "state":"planned",
        "closureOutcome":null,
        "closureNote":null,
        "notes":"",
        "policyReference":null,
        "createdAt":1800000000123,
        "updatedAt":1800000000123,
        "reimbursements":[{
          "id":"00000000-0000-0000-0000-000000000002",
          "returnItemID":"00000000-0000-0000-0000-000000000001",
          "date":"2026-10-01",
          "amountCents":5000,
          "kind":"money",
          "note":""
        }]
      }]
    }
    """
}
