import Foundation
import ReturnQueueCore
import ReturnQueuePresentation
import ReturnQueueStorage
import XCTest

@MainActor
final class QueueViewModelTests: XCTestCase {
  func testProjectsLatestDurableCreatesAndEditsWithoutKeepingItsOwnRecords() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let session = fixture.session()
    let model = QueueViewModel(session: session)
    XCTAssertEqual(model.groups, [])
    XCTAssertEqual(session.phase, .notLoaded)
    try await session.load()
    var a = PresentationFixture.item()
    a.dropOffLocation = "UPS Store A"
    a.expectedRefundCents = nil
    let first = try await session.create(a)
    XCTAssertEqual(model.groups.flatMap(\.items), first.records)
    var b = PresentationFixture.item()
    b.id = UUID()
    b.merchant = "Another merchant"
    b.dropOffLocation = "ups STORE a"
    b.expectedRefundCents = 0
    let second = try await session.create(b)
    XCTAssertEqual(model.groups.count, 1)
    XCTAssertEqual(model.groups.flatMap(\.items).count, 2)
    a.dropOffLocation = "UPS Store B"
    let updated = try await session.update(a, expectedRevision: second.revision)
    XCTAssertEqual(model.groups.map(\.id), [.named("ups store a"), .named("ups store b")])
    XCTAssertEqual(model.groups.flatMap(\.items).first { $0.id == b.id }?.expectedRefundCents, 0)
    XCTAssertNil(model.groups.flatMap(\.items).first { $0.id == a.id }?.expectedRefundCents)
    XCTAssertNil(model.groups.flatMap(\.items).first { $0.id == a.id }?.returnBy)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), updated.records)
  }

  func testQueueCountExcludesOtherStatesWhileSnapshotAndDiskKeepThem() async throws {
    let records = try ReturnState.allCases.map { state in
      var item = PresentationFixture.item()
      item.id = UUID()
      item.state = state
      item.dropOffLocation = "Same place"
      if state == .closed { item.closureOutcome = .denied }
      return try item.validated()
    }
    let fixture = try PresentationFixture(records: records)
    defer { try? fixture.remove() }
    let session = fixture.session()
    let model = QueueViewModel(session: session)
    try await session.load()
    XCTAssertEqual(model.groups.flatMap(\.items).count, 1)
    XCTAssertEqual(model.groups.flatMap(\.items).map(\.state), [.planned])
    XCTAssertEqual(session.snapshot?.records, records)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), records)
  }

  func testFailedWriteDoesNotMoveCardOrChangeCommittedProjection() async throws {
    var original = PresentationFixture.item()
    original.dropOffLocation = "Original location"
    let fixture = try PresentationFixture(records: [original])
    defer { try? fixture.remove() }
    let repository = ReturnRepository(fileURL: fixture.archiveURL) { stage in
      if stage == .replacement { throw ReturnPersistenceFailure.writeFailed }
    }
    let session = fixture.session(persistence: repository)
    let model = QueueViewModel(session: session)
    try await session.load()
    let before = model.groups
    let snapshot = try XCTUnwrap(session.snapshot)
    let bytes = try Data(contentsOf: fixture.archiveURL)
    var changed = original
    changed.dropOffLocation = "Unsaved location"
    do {
      _ = try await session.update(changed, expectedRevision: snapshot.revision)
      XCTFail("Failed durable write was reported as success")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .store(.writeFailed))
    }
    XCTAssertEqual(model.groups, before)
    XCTAssertEqual(session.snapshot, snapshot)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testReadFailureRetainsLastProjectionAndDoesNotBecomeReadyEmpty() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let session = fixture.session()
    let model = QueueViewModel(session: session)
    try await session.load()
    let before = model.groups
    let snapshot = try XCTUnwrap(session.snapshot)
    let corrupt = Data("damaged original".utf8)
    try corrupt.write(to: fixture.archiveURL)
    do {
      try await session.load()
      XCTFail("Corrupt load succeeded")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .store(.readFailed))
    }
    XCTAssertEqual(model.groups, before)
    XCTAssertEqual(session.phase, .loadFailed(.readFailed, lastCommitted: snapshot))
    XCTAssertFalse(session.canEdit)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), corrupt)
    let firstLoad = fixture.session()
    let unloadedModel = QueueViewModel(session: firstLoad)
    do { try await firstLoad.load() } catch {
      XCTAssertEqual(error as? SessionFailure, .store(.readFailed))
    }
    XCTAssertEqual(unloadedModel.groups, [])
    XCTAssertEqual(firstLoad.phase, .loadFailed(.readFailed, lastCommitted: nil))
    XCTAssertFalse(firstLoad.canEdit)
  }

  func testTimezoneAndMidnightRefreshChangeOnlyTodayAndPastBadge() async throws {
    var item = PresentationFixture.item()
    item.returnBy = try CalendarDay(iso8601: "2026-10-03")
    let fixture = try PresentationFixture(records: [item])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let clock = QueueTestClock()
    let model = QueueViewModel(session: session, now: { clock.instant }, timeZone: { clock.zone })
    let before = model.groups
    let bytes = try Data(contentsOf: fixture.archiveURL)
    XCTAssertEqual(model.today, try CalendarDay(iso8601: "2026-10-03"))
    XCTAssertFalse(model.isPastEnteredDate(item.returnBy))
    clock.zone = TimeZone(identifier: "Pacific/Kiritimati")!
    model.refreshToday()
    XCTAssertEqual(model.today, try CalendarDay(iso8601: "2026-10-04"))
    XCTAssertTrue(model.isPastEnteredDate(item.returnBy))
    XCTAssertFalse(model.isPastEnteredDate(try CalendarDay(iso8601: "2026-10-04")))
    XCTAssertFalse(model.isPastEnteredDate(nil))
    clock.zone = TimeZone(secondsFromGMT: 0)!
    clock.instant = Date(timeIntervalSince1970: 1_791_071_999)  // 2026-10-03 23:59:59 UTC
    model.refreshToday()
    XCTAssertEqual(model.today, try CalendarDay(iso8601: "2026-10-03"))
    clock.instant = clock.instant.addingTimeInterval(1)
    model.refreshToday()
    XCTAssertEqual(model.today, try CalendarDay(iso8601: "2026-10-04"))
    XCTAssertTrue(model.isPastEnteredDate(item.returnBy))
    XCTAssertEqual(model.groups, before)
    XCTAssertEqual(model.groups.flatMap(\.items).first?.returnBy, item.returnBy)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
  }

  func testUnrepresentableTodayOmitsPastRatherThanInventingDate() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let session = fixture.session()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let outOfRange = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 10_000, month: 1, day: 1)))
    let clock = QueueTestClock()
    clock.instant = outOfRange
    clock.zone = TimeZone(secondsFromGMT: 0)!
    let model = QueueViewModel(session: session, now: { clock.instant }, timeZone: { clock.zone })
    XCTAssertNil(model.today)
    XCTAssertFalse(model.isPastEnteredDate(try CalendarDay(iso8601: "2026-10-03")))
    clock.instant = try XCTUnwrap(
      calendar.date(from: DateComponents(era: 0, year: 1, month: 1, day: 1)))
    model.refreshToday()
    XCTAssertNil(model.today, "A BCE year must not become AD year 1")
    XCTAssertFalse(model.isPastEnteredDate(try CalendarDay(iso8601: "0001-01-01")))
    for interval in [TimeInterval.infinity, TimeInterval.nan] {
      clock.instant = Date(timeIntervalSince1970: interval)
      model.refreshToday()
      XCTAssertNil(model.today)
      XCTAssertFalse(model.isPastEnteredDate(try CalendarDay(iso8601: "2026-10-03")))
    }
    XCTAssertEqual(session.phase, .notLoaded)
  }
}

@MainActor
private final class QueueTestClock {
  var instant = Date(timeIntervalSince1970: 1_791_073_800)  // 2026-10-04 00:30:00 UTC
  var zone = TimeZone(identifier: "America/Los_Angeles")!
}
