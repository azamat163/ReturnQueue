import Foundation

public enum Money {
  /// Strict US decimal syntax; no floating-point rounding or currency symbols.
  public static func cents(from input: String) throws -> Int {
    let bytes = Array(input.utf8)
    guard !bytes.isEmpty else { throw ReturnQueueError.invalidMoney }
    var dollars = 0
    var fraction = 0
    var fractionDigits = 0
    var dollarDigits = 0
    var hasDecimalPoint = false

    for byte in bytes {
      if byte == 46 {
        guard !hasDecimalPoint, dollarDigits > 0 else { throw ReturnQueueError.invalidMoney }
        hasDecimalPoint = true
        continue
      }
      guard (48...57).contains(byte) else { throw ReturnQueueError.invalidMoney }
      let digit = Int(byte - 48)
      if hasDecimalPoint {
        fractionDigits += 1
        guard fractionDigits <= 2 else { throw ReturnQueueError.invalidMoney }
        fraction = fraction * 10 + digit
      } else {
        dollarDigits += 1
        let (scaled, multiplyOverflow) = dollars.multipliedReportingOverflow(by: 10)
        let (next, additionOverflow) = scaled.addingReportingOverflow(digit)
        guard !multiplyOverflow, !additionOverflow else { throw ReturnQueueError.moneyOverflow }
        dollars = next
      }
    }
    guard !hasDecimalPoint || fractionDigits > 0 else { throw ReturnQueueError.invalidMoney }
    if fractionDigits == 1 { fraction *= 10 }
    let (scaled, multiplyOverflow) = dollars.multipliedReportingOverflow(by: 100)
    let (result, additionOverflow) = scaled.addingReportingOverflow(fraction)
    guard !multiplyOverflow, !additionOverflow else { throw ReturnQueueError.moneyOverflow }
    try validate(cents: result, currency: "USD", allowsZero: true)
    return result
  }

  public static func validate(cents: Int, currency: String, allowsZero: Bool = false) throws {
    guard currency == "USD" else { throw ReturnQueueError.invalidCurrency(currency) }
    guard ((allowsZero ? 0 : 1)...100_000_000).contains(cents) else {
      throw ReturnQueueError.invalidAmount
    }
  }

  /// Adds validated amounts without imposing the per-event limit on a total.
  public static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw ReturnQueueError.moneyOverflow }
    return result
  }

  public static func formatted(_ cents: Int) -> String {
    let magnitude = cents.magnitude
    let dollars = magnitude / 100
    let remainder = magnitude % 100
    let fraction = remainder < 10 ? "0\(remainder)" : String(remainder)
    return "\(cents < 0 ? "-" : "")$\(dollars).\(fraction)"
  }
}
