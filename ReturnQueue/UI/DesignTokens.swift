import ReturnQueueCore
import SwiftUI

/// File-owned Figma tokens. Native controls inherit AccentColor from the asset catalog.
enum DesignTokens {
  static let background = Color("ColorBackground")
  static let surface = Color("ColorSurface")
  static let ink = Color("ColorInk")
  static let secondary = Color("ColorSecondary")
  static let tint = Color("ColorTint")
  static let accent = Color("ColorAccent")
  static let line = Color("ColorLine")
  static let warning = Color("ColorWarning")
  static let success = Color("ColorSuccess")
}

enum DetailFormatting {
  static func day(_ day: CalendarDay?) -> String {
    guard let day else { return "Not set" }
    let months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    return "\(months[day.month - 1]) \(day.day), \(day.year)"
  }

  static func amount(_ cents: Int?) -> String { cents.map(Money.formatted) ?? "Not set" }

  static func state(_ state: ReturnState) -> String {
    switch state {
    case .planned: return "To return"
    case .droppedOff: return "Waiting for refund"
    case .closed: return "Closed"
    case .kept: return "Keeping item"
    }
  }

  static func outcome(_ outcome: ClosureOutcome?) -> String {
    guard let outcome else { return "Not set" }
    switch outcome {
    case .fullRefund: return "Refund received"
    case .partialRefund: return "Partial refund"
    case .denied: return "Denied"
    case .cancelled: return "Cancelled"
    }
  }

  static func kind(_ kind: ReimbursementKind) -> String {
    kind == .money ? "Money" : "Store credit"
  }

  static func timestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
    return formatter.string(from: date)
  }

  static func summary(_ summary: RefundSummary) -> String {
    "Money: \(amount(summary.moneyCents))\nStore credit: \(amount(summary.storeCreditCents))\nExpected refund: \(amount(summary.expectedRefundCents))\nDifference from expected: \(amount(summary.differenceCents))"
  }
}
