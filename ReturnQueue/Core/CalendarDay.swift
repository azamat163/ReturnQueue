import Foundation

/// A Gregorian calendar day, independent of any time zone or timestamp.
public struct CalendarDay: Codable, Comparable, Equatable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) throws {
    guard (1...9_999).contains(year), (1...12).contains(month) else {
      throw ReturnQueueError.invalidDate
    }
    let isLeapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    let lengths = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard (1...lengths[month - 1]).contains(day) else { throw ReturnQueueError.invalidDate }
    self.year = year
    self.month = month
    self.day = day
  }

  public init(iso8601: String) throws {
    let bytes = Array(iso8601.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
      bytes.enumerated().allSatisfy({ index, byte in
        index == 4 || index == 7 || (48...57).contains(byte)
      })
    else { throw ReturnQueueError.invalidDate }
    func number(_ range: Range<Int>) -> Int {
      range.reduce(0) { $0 * 10 + Int(bytes[$1] - 48) }
    }
    try self.init(year: number(0..<4), month: number(5..<7), day: number(8..<10))
  }

  public var iso8601: String {
    func padded(_ value: Int, width: Int) -> String {
      let digits = String(value)
      return String(repeating: "0", count: width - digits.count) + digits
    }
    return "\(padded(year, width: 4))-\(padded(month, width: 2))-\(padded(day, width: 2))"
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.year != rhs.year { return lhs.year < rhs.year }
    if lhs.month != rhs.month { return lhs.month < rhs.month }
    return lhs.day < rhs.day
  }

  public init(from decoder: any Decoder) throws {
    try self.init(iso8601: decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(iso8601)
  }
}
