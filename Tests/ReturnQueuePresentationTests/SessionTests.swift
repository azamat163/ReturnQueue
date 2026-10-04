import Foundation
import ReturnQueueCore
import ReturnQueuePresentation
import ReturnQueueStorage
import XCTest

@MainActor
final class SessionTests: XCTestCase {
  func testFailedReloadKeepsLastCommittedAndBlocksChanges() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = try XCTUnwrap(session.snapshot)
    let corrupt = Data("corrupt original".utf8)
    try corrupt.write(to: fixture.archiveURL)
    do {
      try await session.load()
      XCTFail("Corrupt load succeeded")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .store(.readFailed))
    }
    XCTAssertEqual(session.phase, .loadFailed(.readFailed, lastCommitted: before))
    XCTAssertEqual(session.snapshot, before)
    XCTAssertEqual(session.activity, .idle)
    XCTAssertFalse(session.canEdit)
    do {
      _ = try await session.create(PresentationFixture.item())
      XCTFail("Mutation succeeded while read blocked")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .notReady)
    }
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), corrupt)
  }

  func testCentralGateRejectsConcurrentIntentsDuringActualDelayedRead() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let gate = PresentationGate()
    defer { gate.release.signal() }
    let persistence = DelayedReadPersistence(
      repository: ReturnRepository(fileURL: fixture.archiveURL), gate: gate)
    let session = fixture.session(persistence: persistence)
    let load = Task { try await session.load() }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    XCTAssertEqual(session.phase, .loading(lastCommitted: nil))
    XCTAssertEqual(session.activity, .loading)
    XCTAssertFalse(session.canEdit)
    do {
      try await session.load()
      XCTFail("Concurrent load accepted")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .busy)
    }
    do {
      _ = try await session.create(PresentationFixture.item())
      XCTFail("Concurrent create accepted")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .busy)
    }
    do {
      _ = try await session.update(PresentationFixture.item(), expectedRevision: 0)
      XCTFail("Concurrent update accepted")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .busy)
    }
    do {
      _ = try await session.exportOriginal()
      XCTFail("Concurrent export accepted")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .busy)
    }
    gate.release.signal()
    try await load.value
    XCTAssertTrue(session.canEdit)
    XCTAssertEqual(session.snapshot?.records.count, 1)
  }

  func testSaveGatePreventsInterveningReloadAndThenSurfacesRealReadFailure() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let gate = PresentationGate()
    defer { gate.release.signal() }
    let session = fixture.session(persistence: gate.repository(at: fixture.archiveURL))
    try await session.load()
    let create = Task { try await session.create(PresentationFixture.item()) }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    XCTAssertEqual(session.activity, .saving)
    XCTAssertFalse(session.canEdit)
    do {
      try await session.load()
      XCTFail("Reload interleaved with a pending durable write")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .busy)
    }
    gate.release.signal()
    let committed = try await create.value
    XCTAssertEqual(session.phase, .ready(committed))
    let corrupt = Data("external corruption after commit".utf8)
    try corrupt.write(to: fixture.archiveURL)
    do {
      try await session.load()
      XCTFail("Corrupt reload succeeded")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .store(.readFailed))
    }
    XCTAssertEqual(session.phase, .loadFailed(.readFailed, lastCommitted: committed))
    XCTAssertFalse(session.canEdit)
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), corrupt)
  }

  func testCancellationDuringCommitStillPublishesDurableSnapshot() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let gate = PresentationGate()
    defer { gate.release.signal() }
    let session = fixture.session(persistence: gate.repository(at: fixture.archiveURL))
    try await session.load()
    let item = PresentationFixture.item()
    let operation = Task { try await session.create(item) }
    let entered = await gate.waitUntilEntered()
    XCTAssertTrue(entered)
    operation.cancel()
    gate.release.signal()
    let committed = try await operation.value
    XCTAssertEqual(session.phase, .ready(committed))
    XCTAssertEqual(session.activity, .idle)
    XCTAssertEqual(session.snapshot?.records, [item])
    XCTAssertTrue(session.canEdit)
    XCTAssertEqual(try ArchiveCodec.decode(Data(contentsOf: fixture.archiveURL)), [item])
  }

  func testRawExportWhileBlockedCopiesOriginalAndCleanupOnlyRemovesOwnedCopy() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let corrupt = Data([0xFF, 0x00, 0xA5])
    try corrupt.write(to: fixture.archiveURL)
    let session = fixture.session()
    do {
      try await session.load()
      XCTFail("Corrupt load succeeded")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .store(.readFailed))
    }
    let before = session.phase
    let copy = try await session.exportOriginal()
    XCTAssertEqual(try Data(contentsOf: copy), corrupt)
    XCTAssertEqual(session.phase, before)
    XCTAssertFalse(session.canEdit)
    try await session.cleanupRecovery(copy)
    XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), corrupt)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: fixture.recoveryDirectory.path), [])
  }

  func testRecoveryRefusesUnownedOriginalAndRemovesOnlyOwnedDestination() async throws {
    let fixture = try PresentationFixture(records: [PresentationFixture.item()])
    defer { try? fixture.remove() }
    let bytes = try Data(contentsOf: fixture.archiveURL)
    let recovery = RecoveryFileService(directory: fixture.recoveryDirectory)
    let copy = try await recovery.makeDestination()
    try bytes.write(to: copy)
    do {
      try await recovery.remove(fixture.archiveURL)
      XCTFail("Recovery cleanup deleted the original archive")
    } catch {
      XCTAssertEqual(error as? ReturnPersistenceFailure, .invalidDestination)
    }
    XCTAssertEqual(try Data(contentsOf: fixture.archiveURL), bytes)
    XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    try await recovery.remove(copy)
    XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    do {
      try await recovery.remove(copy)
      XCTFail("An unowned destination was accepted")
    } catch {
      XCTAssertEqual(error as? ReturnPersistenceFailure, .invalidDestination)
    }
  }

  func testFailedExportCleansItsOwnedDestinationAndKeepsSessionReady() async throws {
    let fixture = try PresentationFixture()
    defer { try? fixture.remove() }
    let session = fixture.session()
    try await session.load()
    let before = session.phase
    do {
      _ = try await session.exportOriginal()
      XCTFail("Missing archive was exported")
    } catch {
      XCTAssertEqual(error as? SessionFailure, .recovery(.sourceMissing))
    }
    XCTAssertEqual(session.phase, before)
    XCTAssertEqual(session.activity, .idle)
    XCTAssertTrue(session.canEdit)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archiveURL.path))
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: fixture.recoveryDirectory.path), [])
  }
}
