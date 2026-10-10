import Foundation
import Observation
import ReturnQueueCore

@MainActor @Observable
public final class RefundsViewModel {
  private let session: AppSession

  public init(session: AppSession) { self.session = session }

  public var waitingItems: [ReturnItem] {
    (session.snapshot?.records ?? []).filter { $0.state == .droppedOff }.sorted {
      if $0.droppedOffDate != $1.droppedOffDate {
        switch ($0.droppedOffDate, $1.droppedOffDate) {
        case (.some(let lhs), .some(let rhs)): return lhs < rhs
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): break
        }
      }
      if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  public var historyItems: [ReturnItem] {
    (session.snapshot?.records ?? []).filter { $0.state == .closed || $0.state == .kept }.sorted {
      if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  public var waitingCount: Int { waitingItems.count }
  public var historyCount: Int { historyItems.count }
}
