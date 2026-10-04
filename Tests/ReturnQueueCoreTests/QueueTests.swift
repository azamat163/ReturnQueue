import Foundation
import ReturnQueueCore
import XCTest

final class QueueTests: XCTestCase {
  func testOnlyPlannedItemsAppearWithoutChangingOtherStatesOrInput() throws {
    let records = try ReturnState.allCases.enumerated().map { index, state in
      var value = item(index + 1, location: "UPS Store")
      value.state = state
      if state == .closed { value.closureOutcome = .denied }
      return try value.validated()
    }
    let before = records
    let groups = ReturnQueueSelector.groups(from: records)
    XCTAssertEqual(
      groups.flatMap(\.items).map(\.id), records.filter { $0.state == .planned }.map(\.id))
    XCTAssertEqual(records, before)
    XCTAssertEqual(records.count, 4)
  }

  func testLocationGroupsCrossMerchantsAndSeparateAddressesOfOneMerchant() {
    let a = item(1, location: " \nUPS Store 10 Market St\t", merchant: "Store A")
    let b = item(2, location: "ups STORE 10 market st", merchant: "Store B")
    let c = item(3, location: "UPS Store 20 Market St", merchant: "Store A")
    let groups = ReturnQueueSelector.groups(from: [c, b, a])
    XCTAssertEqual(
      groups.map(\.id), [.named("ups store 10 market st"), .named("ups store 20 market st")])
    XCTAssertEqual(groups[0].items.map(\.merchant), ["Store A", "Store B"])
    XCTAssertEqual(groups[0].items.map(\.id), [a.id, b.id])
    XCTAssertEqual(groups[1].items.map(\.id), [c.id])
  }

  func testPOSIXCaseAndCanonicalUnicodeMergeWithoutErasingMeaningfulDifferences() {
    let locations = [
      "I Center", "i center", "ı center", "CAFÉ", "Cafe\u{301}", "Cafe",
      "UPS Store", "UPS  Store", "UPS Store, counter", "UPS Store 10 A", "UPS Store 20 B",
    ]
    let records = locations.enumerated().map { item($0.offset + 1, location: $0.element) }
    let groups = ReturnQueueSelector.groups(from: records.reversed())
    XCTAssertEqual(
      groups.map(\.id),
      [
        .named("cafe"), .named("café"), .named("i center"), .named("ups  store"),
        .named("ups store"), .named("ups store 10 a"), .named("ups store 20 b"),
        .named("ups store, counter"), .named("ı center"),
      ])
    XCTAssertEqual(
      groups.first { $0.id == .named("café") }?.items.map(\.id), [records[3].id, records[4].id])
    XCTAssertEqual(
      groups.first { $0.id == .named("i center") }?.items.map(\.id), [records[0].id, records[1].id])
  }

  func testMissingLocationHasTypedKeyDistinctFromLiteralDisplaySentinel() {
    let missing = item(1, location: nil, merchant: "Store A")
    let blank = item(2, location: " \n\t", merchant: "Store B")
    let literal = item(3, location: "Location not set")
    let groups = ReturnQueueSelector.groups(from: [missing, literal, blank])
    XCTAssertEqual(groups.map(\.id), [.named("location not set"), .notSet])
    XCTAssertEqual(groups.map(\.displayName), ["Location not set", "Location not set"])
    XCTAssertEqual(groups[0].items.map(\.id), [literal.id])
    XCTAssertEqual(groups[1].items.map(\.id), [missing.id, blank.id])
  }

  func testKnownDaysComeFirstThenCreationAndUUIDBreakAllTies() throws {
    let records = [
      item(1, location: "A", day: try day("2024-03-01"), created: 2),
      item(2, location: "A", day: try day("2024-02-29"), created: 4),
      item(3, location: "A", day: try day("2024-03-01"), created: 1),
      item(4, location: "A", day: try day("2024-03-01"), created: 1),
      item(5, location: "A", created: 0),
      item(6, location: "A", created: 0),
    ]
    let groups = ReturnQueueSelector.groups(from: [
      records[5], records[3], records[1], records[4], records[0], records[2],
    ])
    XCTAssertEqual(groups[0].items.map(\.id), [2, 3, 4, 1, 5, 6].map(CoreFixtures.numberedID))
    XCTAssertEqual(
      groups[0].items.compactMap(\.returnBy).map(\.iso8601),
      ["2024-02-29", "2024-03-01", "2024-03-01", "2024-03-01"])
  }

  func testAllSmallInputPermutationsKeepGroupOrderRepresentativeAndLabelsStable() throws {
    let records = [
      item(3, location: "z Place", day: try day("2026-10-01"), created: 0),
      item(2, location: " \nUPS STORE\t", day: try day("2026-10-02"), created: 1),
      item(1, location: " \nups store\t", created: 1),
      item(4, location: "A Place", created: 3),
      item(5, location: nil, created: 0),
    ]
    let expected = ReturnQueueSelector.groups(from: records)
    XCTAssertEqual(
      expected.map(\.id), [.named("a place"), .named("ups store"), .named("z place"), .notSet])
    XCTAssertEqual(expected[1].representativeItemID, records[2].id)
    XCTAssertEqual(expected[1].displayName, "ups store")
    XCTAssertEqual(expected[1].items.map(\.id), [records[1].id, records[2].id])
    for permutation in permutations(records) {
      XCTAssertEqual(ReturnQueueSelector.groups(from: permutation), expected)
    }
    XCTAssertEqual(records[1].dropOffLocation, " \nUPS STORE\t")
    XCTAssertEqual(records[2].dropOffLocation, " \nups store\t")
  }

  func testPastUsesEnteredCalendarDaysAndLeavesTodayFutureAndUnknownActive() throws {
    let today = try day("2024-03-01")
    XCTAssertTrue(ReturnQueueSelector.isPastEnteredDate(try day("2024-02-29"), today: today))
    XCTAssertFalse(ReturnQueueSelector.isPastEnteredDate(today, today: today))
    XCTAssertFalse(ReturnQueueSelector.isPastEnteredDate(try day("2024-03-02"), today: today))
    XCTAssertFalse(ReturnQueueSelector.isPastEnteredDate(nil, today: today))
    XCTAssertTrue(
      ReturnQueueSelector.isPastEnteredDate(try day("2026-12-31"), today: try day("2027-01-01")))
    let past = item(1, location: nil, day: try day("2024-02-29"))
    XCTAssertEqual(ReturnQueueSelector.groups(from: [past]).flatMap(\.items), [past])
    XCTAssertEqual(past.state, .planned)
  }

  private func item(
    _ number: Int, location: String?, merchant: String = "Store", day: CalendarDay? = nil,
    created: TimeInterval = 0
  ) -> ReturnItem {
    ReturnItem(
      id: CoreFixtures.numberedID(number), title: "Item \(number)", merchant: merchant,
      dropOffLocation: location, returnBy: day,
      createdAt: CoreFixtures.instant.addingTimeInterval(created))
  }

  private func day(_ value: String) throws -> CalendarDay { try CalendarDay(iso8601: value) }

  private func permutations(_ records: [ReturnItem]) -> [[ReturnItem]] {
    if records.isEmpty { return [[]] }
    return records.indices.flatMap { index in
      var rest = records
      let first = rest.remove(at: index)
      return permutations(rest).map { [first] + $0 }
    }
  }
}
