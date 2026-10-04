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
}
