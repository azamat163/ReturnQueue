import Foundation
import ReturnQueueCore
import XCTest

final class RecordTests: XCTestCase {
  func testMinimalRecordNeedsOnlyTitleAndMerchantAndPreservesUnknowns() throws {
    let value = try CoreFixtures.item().validated()
    XCTAssertEqual(value.state, .planned)
    XCTAssertEqual(value.currency, "USD")
    XCTAssertNil(value.returnBy)
    XCTAssertNil(value.purchaseDate)
    XCTAssertNil(value.droppedOffDate)
    XCTAssertNil(value.expectedRefundDate)
    XCTAssertNil(value.dropOffLocation)
    XCTAssertNil(value.purchasePriceCents)
    XCTAssertNil(value.expectedRefundCents)
    XCTAssertNil(value.closureOutcome)
    XCTAssertTrue(value.reimbursements.isEmpty)
    XCTAssertEqual(value.updatedAt, value.createdAt)
  }

  func testValidationTrimsInputsWithoutMutatingTheDraft() throws {
    var draft = CoreFixtures.item()
    draft.title = " \nRunning shoes\t"
    draft.merchant = "\tExample Store \n"
    draft.dropOffLocation = "  Main Street counter  "
    draft.policyReference = "  Order confirmation  "
    draft.notes = " \nBring the box\t"
    var event = CoreFixtures.event()
    event.note = " \nFirst installment\t"
    draft.reimbursements = [event]
    let value = try draft.validated()
    XCTAssertEqual(value.title, "Running shoes")
    XCTAssertEqual(value.merchant, "Example Store")
    XCTAssertEqual(value.dropOffLocation, "Main Street counter")
    XCTAssertEqual(value.policyReference, "Order confirmation")
    XCTAssertEqual(value.notes, "Bring the box")
    XCTAssertEqual(value.reimbursements[0].note, "First installment")
    XCTAssertEqual(draft.title, " \nRunning shoes\t")
  }

  func testRequiredFieldsRejectBlankValuesAndCountGraphemesAfterTrim() throws {
    let family = "👨‍👩‍👧‍👦"
    XCTAssertEqual(family.count, 1)
    for field in [\ReturnItem.title, \ReturnItem.merchant] {
      for blank in ["", " ", "\n\t"] {
        var value = CoreFixtures.item()
        value[keyPath: field] = blank
        XCTAssertThrowsError(try value.validated())
      }
      var value = CoreFixtures.item()
      value[keyPath: field] = " \n" + String(repeating: family, count: 120) + "\t"
      XCTAssertEqual(try value.validated()[keyPath: field].count, 120)
      value[keyPath: field] = String(repeating: family, count: 121)
      XCTAssertThrowsError(try value.validated())
    }
  }

  func testOptionalTextBecomesNilAndRejectsOverlongValues() throws {
    let fields: [(WritableKeyPath<ReturnItem, String?>, Int)] = [
      (\ReturnItem.dropOffLocation, 200), (\ReturnItem.policyReference, 1_000),
      (\ReturnItem.closureNote, 1_000),
    ]
    for (field, limit) in fields {
      var value = CoreFixtures.item()
      value[keyPath: field] = " \n\t"
      XCTAssertNil(try value.validated()[keyPath: field])
      value[keyPath: field] = " " + String(repeating: "é", count: limit) + " "
      XCTAssertEqual(try value.validated()[keyPath: field]?.count, limit)
      value[keyPath: field] = String(repeating: "é", count: limit + 1)
      XCTAssertThrowsError(try value.validated())
    }
    var value = CoreFixtures.item()
    value.notes = String(repeating: "x", count: 4_000)
    XCTAssertNoThrow(try value.validated())
    value.notes += "x"
    XCTAssertThrowsError(try value.validated())
  }

  func testUnknownAndZeroPricesAreDistinctValidValues() throws {
    var value = CoreFixtures.item()
    XCTAssertNil(try value.validated().expectedRefundCents)
    XCTAssertNil(try value.unresolvedDifferenceCents())
    value.expectedRefundCents = 0
    value.purchasePriceCents = 0
    let zero = try value.validated()
    XCTAssertEqual(zero.expectedRefundCents, 0)
    XCTAssertEqual(zero.purchasePriceCents, 0)
    XCTAssertEqual(try zero.unresolvedDifferenceCents(), 0)
  }

  func testPricesEnforceUSDBoundsIndependently() {
    for field in [\ReturnItem.purchasePriceCents, \ReturnItem.expectedRefundCents] {
      var value = CoreFixtures.item()
      value[keyPath: field] = 100_000_000
      XCTAssertNoThrow(try value.validated())
      for amount in [-1, Int.min, 100_000_001, Int.max] {
        value[keyPath: field] = amount
        XCTAssertThrowsError(try value.validated())
      }
    }
    var value = CoreFixtures.item()
    value.currency = "EUR"
    XCTAssertThrowsError(try value.validated())
  }

  func testEventAmountsAndNotesHaveIndependentBounds() throws {
    var event = CoreFixtures.event(cents: 1)
    event.note = " " + String(repeating: "x", count: 1_000) + " "
    XCTAssertEqual(try event.validated().note.count, 1_000)
    event.note = String(repeating: "x", count: 1_001)
    XCTAssertThrowsError(try event.validated())
    event.note = ""
    event.amountCents = 100_000_000
    XCTAssertNoThrow(try event.validated())
    for cents in [0, -1, Int.min, 100_000_001, Int.max] {
      event.amountCents = cents
      XCTAssertThrowsError(try event.validated())
    }
  }

  func testGregorianLeapYearsAndMonthBoundaries() throws {
    for year in [4, 2_000, 2_024, 2_400] {
      XCTAssertNoThrow(try CalendarDay(year: year, month: 2, day: 29))
    }
    for year in [1, 1_900, 2_023, 2_100] {
      XCTAssertThrowsError(try CalendarDay(year: year, month: 2, day: 29))
    }
    let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    for (index, lastDay) in lengths.enumerated() {
      XCTAssertNoThrow(try CalendarDay(year: 2_026, month: index + 1, day: lastDay))
      XCTAssertThrowsError(try CalendarDay(year: 2_026, month: index + 1, day: lastDay + 1))
    }
    for (year, month, day) in [
      (0, 1, 1), (10_000, 1, 1), (2_026, 0, 1), (2_026, 13, 1),
      (2_026, 1, 0),
    ] {
      XCTAssertThrowsError(try CalendarDay(year: year, month: month, day: day))
    }
    XCTAssertEqual(try CalendarDay(year: 1, month: 1, day: 1).iso8601, "0001-01-01")
    XCTAssertEqual(try CalendarDay(year: 9_999, month: 12, day: 31).iso8601, "9999-12-31")
  }

  func testCalendarDayRejectsNoncanonicalAndNonASCIIInput() {
    for input in [
      "2026-1-01", "26-01-01", "2026-01-1", "0000-01-01", "10000-01-01", "2026/01/01",
      " 2026-01-01", "2026-01-01 ", "2026-01-01T00:00:00Z", "２０２６-０１-０１",
      "2026–01–01", "2026-02-30",
    ] {
      XCTAssertThrowsError(try CalendarDay(iso8601: input), input)
    }
  }

  func testCalendarDayComparisonUsesCalendarOrder() throws {
    let ordered = try ["0001-01-01", "2025-12-31", "2026-01-01", "2026-01-02", "9999-12-31"]
      .map { try CalendarDay(iso8601: $0) }
    XCTAssertEqual(ordered.reversed().sorted(), ordered)
  }

  func testCalendarDayRoundTripDoesNotBecomeALocalTimestamp() throws {
    let day = try CalendarDay(iso8601: "2026-10-03")
    for offset in [-43_200, 0, 50_400] {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: offset)
      formatter.dateFormat = "yyyy-MM-dd"
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .formatted(formatter)
      let data = try encoder.encode(day)
      XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-10-03\"")
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .formatted(formatter)
      XCTAssertEqual(try decoder.decode(CalendarDay.self, from: data), day)
    }
    for json in ["42", "null", "{\"year\":2026,\"month\":10,\"day\":3}"] {
      XCTAssertThrowsError(try JSONDecoder().decode(CalendarDay.self, from: Data(json.utf8)))
    }
  }

  func testLedgerSeparatesCashCreditAndPreservesUnknownExpectation() throws {
    var value = CoreFixtures.item()
    value.expectedRefundCents = 10_000
    value.reimbursements = [
      CoreFixtures.event(cents: 5_000),
      CoreFixtures.event(id: CoreFixtures.secondEventID, cents: 3_000, kind: .storeCredit),
    ]
    XCTAssertEqual(try value.moneyReceivedCents(), 5_000)
    XCTAssertEqual(try value.storeCreditCents(), 3_000)
    XCTAssertEqual(try value.unresolvedDifferenceCents(), 2_000)
    value.expectedRefundCents = nil
    XCTAssertNil(try value.unresolvedDifferenceCents())
    XCTAssertEqual(try value.moneyReceivedCents(), 5_000)
  }

  func testExcessIsAllowedAndHasANegativeDifference() throws {
    var value = CoreFixtures.item()
    value.expectedRefundCents = 4_000
    value.reimbursements = [CoreFixtures.event(cents: 5_000)]
    XCTAssertEqual(try value.unresolvedDifferenceCents(), -1_000)
    XCTAssertNoThrow(try value.validated())
  }

  func testEventsMustBelongToTheirRecordAndCannotRepeatWithinIt() {
    var value = CoreFixtures.item()
    value.reimbursements = [CoreFixtures.event(parentID: CoreFixtures.secondRecordID)]
    XCTAssertThrowsError(try value.validated())
    XCTAssertThrowsError(try value.moneyReceivedCents())
    let event = CoreFixtures.event()
    value.reimbursements = [event, event]
    XCTAssertThrowsError(try value.validated())
  }

  func testFullLedgerDoesNotCloseAnOpenRecordAutomatically() throws {
    var value = CoreFixtures.item()
    value.expectedRefundCents = 5_000
    value.reimbursements = [CoreFixtures.event()]
    for state in [ReturnState.planned, .droppedOff, .kept] {
      value.state = state
      let validated = try value.validated()
      XCTAssertEqual(validated.state, state)
      XCTAssertNil(validated.closureOutcome)
      XCTAssertEqual(validated.reimbursements, value.reimbursements)
    }
  }

  func testManualClosureRequiresOutcomeAndNoteForAnyKnownDifference() throws {
    var value = CoreFixtures.item()
    value.state = .closed
    XCTAssertThrowsError(try value.validated())
    value.closureOutcome = .partialRefund
    value.reimbursements = [CoreFixtures.event(cents: 5_000)]
    for expected in [4_000, 10_000] {
      value.expectedRefundCents = expected
      value.closureNote = nil
      XCTAssertThrowsError(try value.validated())
      value.closureNote = " \n\t"
      XCTAssertThrowsError(try value.validated())
      value.closureNote = "  Accepted the difference  "
      XCTAssertEqual(try value.validated().closureNote, "Accepted the difference")
    }
    value.expectedRefundCents = 5_000
    value.closureNote = nil
    value.closureOutcome = .fullRefund
    XCTAssertNoThrow(try value.validated())
  }

  func testUnknownExpectationCanCloseWithoutInventingFullnessOrMoney() throws {
    var value = CoreFixtures.item()
    value.state = .closed
    value.reimbursements = [CoreFixtures.event(cents: 3_000)]
    for outcome in [ClosureOutcome.fullRefund, .partialRefund, .denied, .cancelled] {
      value.closureOutcome = outcome
      let validated = try value.validated()
      XCTAssertNil(validated.expectedRefundCents)
      XCTAssertNil(try validated.unresolvedDifferenceCents())
      XCTAssertEqual(try validated.moneyReceivedCents(), 3_000)
      XCTAssertEqual(validated.closureOutcome, outcome)
    }
  }

  func testNonclosedOutcomeIsRejectedAndReopeningRetainsNotesAndLedger() throws {
    var value = CoreFixtures.item()
    value.closureOutcome = .partialRefund
    for state in [ReturnState.planned, .droppedOff, .kept] {
      value.state = state
      XCTAssertThrowsError(try value.validated())
    }
    value.state = .closed
    value.expectedRefundCents = 10_000
    value.closureNote = "Accepted a return fee"
    value.reimbursements = [CoreFixtures.event(cents: 8_000)]
    let closed = try value.validated()
    value = closed
    value.state = .droppedOff
    value.closureOutcome = nil
    let reopened = try value.validated()
    XCTAssertEqual(reopened.closureNote, closed.closureNote)
    XCTAssertEqual(reopened.reimbursements, closed.reimbursements)
    XCTAssertNil(reopened.closureOutcome)
  }

  func testTimestampsNormalizeToNearestMillisecondsAndPermitClockCorrection() throws {
    var value = CoreFixtures.item()
    value.createdAt = Date(timeIntervalSince1970: 1_000.00049)
    value.updatedAt = Date(timeIntervalSince1970: 1_000.00051)
    let normalized = try value.validated()
    XCTAssertEqual(normalized.createdAt.timeIntervalSince1970, 1_000, accuracy: 0.000001)
    XCTAssertEqual(normalized.updatedAt.timeIntervalSince1970, 1_000.001, accuracy: 0.000001)
    value.createdAt = CoreFixtures.instant
    value.updatedAt = CoreFixtures.instant.addingTimeInterval(-60)
    XCTAssertNoThrow(try value.validated())
  }

  func testTimestampBoundsRejectNonfiniteAndOutOfRangeInstants() {
    for field in [\ReturnItem.createdAt, \ReturnItem.updatedAt] {
      for seconds in [-62_135_596_800.0, 253_402_300_799.999] {
        var value = CoreFixtures.item()
        value[keyPath: field] = Date(timeIntervalSince1970: seconds)
        XCTAssertNoThrow(try value.validated())
      }
      for seconds in [Double.nan, .infinity, -.infinity, -62_135_596_801, 253_402_300_800] {
        var value = CoreFixtures.item()
        value[keyPath: field] = Date(timeIntervalSince1970: seconds)
        XCTAssertThrowsError(try value.validated())
      }
    }
  }
}
