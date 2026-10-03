import ReturnQueueCore
import XCTest

final class MoneyTests: XCTestCase {
  func testDecimalInputPreservesExactCentsIncludingTheSupportedBoundary() throws {
    let inputs = [
      "0": 0, "0.00": 0, "0.01": 1, "19.9": 1_990, "19.99": 1_999,
      "1000000": 100_000_000, "1000000.00": 100_000_000,
    ]
    for (input, expected) in inputs {
      XCTAssertEqual(try Money.cents(from: input), expected, input)
    }
  }

  func testDecimalInputRejectsRoundingLocaleSymbolsAndNonASCIIDigits() {
    for input in [
      "", " ", " 12.99", "12.99 ", "$12", "1,200", "-1", "+1", "1e2", ".50", "1.",
      "1.001", "1.2.3", "NaN", "Infinity", "１２", "١٢", "12\n", "1_000",
    ] {
      XCTAssertThrowsError(try Money.cents(from: input), input)
    }
  }

  func testDecimalInputRejectsAmountsAboveTheDomainLimitAndIntegerOverflow() {
    for input in [
      "1000000.01", "1000001", String(Int.max),
      "\(Int.max / 100).\(Int.max % 100)", String(repeating: "9", count: 10_000),
    ] {
      XCTAssertThrowsError(try Money.cents(from: input), String(input.prefix(60)))
    }
  }

  func testCurrencyAndZeroRulesDistinguishOptionalPricesFromPositiveEvents() {
    XCTAssertNoThrow(try Money.validate(cents: 0, currency: "USD", allowsZero: true))
    XCTAssertNoThrow(try Money.validate(cents: 1, currency: "USD", allowsZero: false))
    XCTAssertNoThrow(try Money.validate(cents: 100_000_000, currency: "USD"))
    XCTAssertThrowsError(try Money.validate(cents: 0, currency: "USD"))
    for value in [Int.min, -1, 100_000_001, Int.max] {
      XCTAssertThrowsError(try Money.validate(cents: value, currency: "USD", allowsZero: true))
    }
    for currency in ["EUR", "usd", " USD ", "", "CAD"] {
      XCTAssertThrowsError(try Money.validate(cents: 1, currency: currency))
    }
  }

  func testCheckedAdditionAllowsTotalsAboveOneEventButRejectsOverflow() throws {
    XCTAssertEqual(try Money.adding(100_000_000, 100_000_000), 200_000_000)
    XCTAssertEqual(try Money.adding(Int.max - 1, 1), Int.max)
    XCTAssertEqual(try Money.adding(Int.min + 1, -1), Int.min)
    XCTAssertEqual(try Money.adding(30, -50), -20)
    XCTAssertThrowsError(try Money.adding(Int.max, 1))
    XCTAssertThrowsError(try Money.adding(Int.min, -1))
  }

  func testFormattingPreservesCentsAndNegativeDifferencesWithoutOverflow() {
    XCTAssertEqual(Money.formatted(0), "$0.00")
    XCTAssertEqual(Money.formatted(1), "$0.01")
    XCTAssertEqual(Money.formatted(1_999), "$19.99")
    XCTAssertEqual(Money.formatted(-1), "-$0.01")
    XCTAssertEqual(Money.formatted(Int.min), "-$92233720368547758.08")
  }
}
