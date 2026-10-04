import Foundation
import Observation
import ReturnQueueCore

@MainActor @Observable
public final class QueueViewModel {
  public private(set) var today: CalendarDay?
  private let session: AppSession
  private let now: @MainActor @Sendable () -> Date
  private let timeZone: @MainActor @Sendable () -> TimeZone

  public init(
    session: AppSession,
    now: @escaping @MainActor @Sendable () -> Date = { Date() },
    timeZone: @escaping @MainActor @Sendable () -> TimeZone = { .current }
  ) {
    self.session = session
    self.now = now
    self.timeZone = timeZone
    refreshToday()
  }

  public var groups: [ReturnQueueGroup] {
    ReturnQueueSelector.groups(from: session.snapshot?.records ?? [])
  }

  public func refreshToday() {
    let instant = now()
    let zone = timeZone()
    let seconds = instant.timeIntervalSince1970
    // Broad UTC bounds allow a boundary day in a local zone, while rejecting extreme
    // injected instants before passing them into Foundation's calendar calculations.
    guard seconds.isFinite, (-62_135_769_600...253_402_473_600).contains(seconds) else {
      today = nil
      return
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = zone
    let components = calendar.dateComponents([.era, .year, .month, .day], from: instant)
    guard components.era == 1, let year = components.year, let month = components.month,
      let day = components.day
    else {
      today = nil
      return
    }
    do {
      today = try CalendarDay(year: year, month: month, day: day)
    } catch {
      today = nil
    }
  }

  public func isPastEnteredDate(_ returnBy: CalendarDay?) -> Bool {
    guard let today else { return false }
    return ReturnQueueSelector.isPastEnteredDate(returnBy, today: today)
  }
}
