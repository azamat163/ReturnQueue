import Foundation

public enum QueueLocationID: Hashable, Sendable {
  case named(String)
  case notSet
}

public struct ReturnQueueGroup: Identifiable, Equatable, Sendable {
  public let id: QueueLocationID
  public let displayName: String
  public let representativeItemID: UUID
  public let items: [ReturnItem]

  public init(
    id: QueueLocationID, displayName: String, representativeItemID: UUID, items: [ReturnItem]
  ) {
    self.id = id
    self.displayName = displayName
    self.representativeItemID = representativeItemID
    self.items = items
  }
}

/// Derives the planned queue without changing any committed records or calendar days.
public enum ReturnQueueSelector {
  public static func groups(from records: [ReturnItem]) -> [ReturnQueueGroup] {
    let grouped = Dictionary(grouping: records.filter { $0.state == .planned }) { item in
      let location = item.dropOffLocation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !location.isEmpty else { return QueueLocationID.notSet }
      let key = location.folding(
        options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")
      )
      .precomposedStringWithCanonicalMapping
      return .named(key)
    }
    return grouped.keys.sorted(by: locationPrecedes).compactMap { key in
      guard let items = grouped[key], let representative = items.min(by: creationPrecedes) else {
        return nil
      }
      let displayName: String
      switch key {
      case .notSet: displayName = "Location not set"
      case .named:
        displayName =
          representative.dropOffLocation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      }
      return ReturnQueueGroup(
        id: key, displayName: displayName, representativeItemID: representative.id,
        items: items.sorted(by: itemPrecedes))
    }
  }

  public static func isPastEnteredDate(_ returnBy: CalendarDay?, today: CalendarDay) -> Bool {
    returnBy.map { $0 < today } ?? false
  }

  private static func locationPrecedes(_ lhs: QueueLocationID, _ rhs: QueueLocationID) -> Bool {
    switch (lhs, rhs) {
    case (.named(let a), .named(let b)): return a.utf8.lexicographicallyPrecedes(b.utf8)
    case (.named, .notSet): return true
    case (.notSet, _): return false
    }
  }

  private static func creationPrecedes(_ lhs: ReturnItem, _ rhs: ReturnItem) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id.uuidString.utf8.lexicographicallyPrecedes(rhs.id.uuidString.utf8)
  }

  private static func itemPrecedes(_ lhs: ReturnItem, _ rhs: ReturnItem) -> Bool {
    switch (lhs.returnBy, rhs.returnBy) {
    case (.some(let a), .some(let b)) where a != b: return a < b
    case (.some, .none): return true
    case (.none, .some): return false
    default: return creationPrecedes(lhs, rhs)
    }
  }
}
