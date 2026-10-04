import Foundation
import ReturnQueueCore
import ReturnQueueStorage
import XCTest

final class RepositoryTests: XCTestCase {
  func testMissingArchiveAndMissingParentAreAbsentWithoutCreatingAnything() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let missingParent = fixture.directory.appendingPathComponent("missing/archive.json")
    XCTAssertNil(try ReturnRepository(fileURL: fixture.fileURL).readArchiveData())
    XCTAssertNil(try ReturnRepository(fileURL: missingParent).readArchiveData())
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), [])
  }

  func testReadAcceptsLimitAndRejectsOneAdditionalByte() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let repository = ReturnRepository(fileURL: fixture.fileURL)
    try StorageFixtures.writeRepeatedBytes(
      to: fixture.fileURL, count: ArchiveCodec.maximumArchiveBytes)
    XCTAssertEqual(try repository.readArchiveData()?.count, ArchiveCodec.maximumArchiveBytes)
    let handle = try FileHandle(forWritingTo: fixture.fileURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0xA5]))
    try handle.close()
    XCTAssertThrowsError(try repository.readArchiveData()) {
      XCTAssertEqual($0 as? ReturnPersistenceFailure, .archiveTooLarge)
    }
  }

  func testDirectoryArchiveIsAnErrorRatherThanAbsence() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    XCTAssertThrowsError(try ReturnRepository(fileURL: fixture.directory).readArchiveData()) {
      XCTAssertEqual($0 as? ReturnPersistenceFailure, .readFailed)
    }
  }

  func testUnreadableArchiveIsAnErrorAndPreservesBytes() throws {
    try XCTSkipIf(
      StorageFixtures.isRoot, "UID 0 bypasses POSIX read permissions; run as a normal user.")
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let bytes = Data("do not overwrite".utf8)
    try fixture.write(bytes)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0], ofItemAtPath: fixture.fileURL.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: fixture.fileURL.path)
    }
    XCTAssertThrowsError(try ReturnRepository(fileURL: fixture.fileURL).readArchiveData()) {
      XCTAssertEqual($0 as? ReturnPersistenceFailure, .readFailed)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: fixture.fileURL.path)
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
  }

  func testAtomicWriteCreatesNestedParentAndReplacesBytes() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let target = fixture.directory.appendingPathComponent("nested/archive.json")
    let repository = ReturnRepository(fileURL: target)
    let first = try ArchiveCodec.encode([StorageFixtures.item()])
    let second = try ArchiveCodec.encode([])
    try repository.writeAtomically(first)
    XCTAssertEqual(try Data(contentsOf: target), first)
    try repository.writeAtomically(second)
    XCTAssertEqual(try Data(contentsOf: target), second)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path),
      ["archive.json"])
  }

  func testEachPrecommitFailurePreservesOriginalAndRemovesTemporaryFiles() throws {
    let stages: [ReturnRepository.WriteStage] = [.stage, .protection, .replacement]
    for stage in stages {
      let fixture = try TemporaryArchive()
      defer { try? fixture.remove() }
      let original = try ArchiveCodec.encode([StorageFixtures.item()])
      try fixture.write(original)
      let repository = StorageFixtures.failingRepository(fileURL: fixture.fileURL, stage: stage)
      XCTAssertThrowsError(try repository.writeAtomically(ArchiveCodec.encode([]))) {
        XCTAssertEqual($0 as? ReturnPersistenceFailure, .writeFailed)
      }
      XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
      XCTAssertEqual(
        try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path),
        ["archive.json"])
    }
  }

  func testRawCopyPreservesCorruptBytesAndAtomicallyReplacesDestination() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let bytes = Data([0xFF, 0xFE, 0x00, 0x01])
    try fixture.write(bytes)
    let destination = fixture.directory.appendingPathComponent("recovery.bin")
    try Data("previous recovery".utf8).write(to: destination)
    try ReturnRepository(fileURL: fixture.fileURL).copyRawArchive(to: destination)
    XCTAssertEqual(try Data(contentsOf: destination), bytes)
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
    XCTAssertEqual(
      Set(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)),
      ["archive.json", "recovery.bin"])
  }

  func testRawCopyStreamsOversizedSourceThatNormalReadRejects() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    try StorageFixtures.writeRepeatedBytes(
      to: fixture.fileURL, count: ArchiveCodec.maximumArchiveBytes + 1)
    let repository = ReturnRepository(fileURL: fixture.fileURL)
    XCTAssertThrowsError(try repository.readArchiveData())
    let destination = fixture.directory.appendingPathComponent("recovery.bin")
    try repository.copyRawArchive(to: destination)
    try StorageFixtures.assertSameBytes(fixture.fileURL, destination)
    let size =
      try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
    XCTAssertEqual(size?.intValue, ArchiveCodec.maximumArchiveBytes + 1)
  }

  func testRawCopyRejectsSourceDestinationWithoutChangingBytes() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let bytes = Data("corrupt but recoverable".utf8)
    try fixture.write(bytes)
    XCTAssertThrowsError(
      try ReturnRepository(fileURL: fixture.fileURL).copyRawArchive(to: fixture.fileURL)
    ) {
      XCTAssertEqual($0 as? ReturnPersistenceFailure, .invalidDestination)
    }
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
  }

  func testRawCopyMissingSourceDoesNotReplaceExistingDestination() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let destination = fixture.directory.appendingPathComponent("recovery.bin")
    let old = Data("previous recovery".utf8)
    try old.write(to: destination)
    XCTAssertThrowsError(
      try ReturnRepository(fileURL: fixture.fileURL).copyRawArchive(to: destination)
    ) {
      XCTAssertEqual($0 as? ReturnPersistenceFailure, .sourceMissing)
    }
    XCTAssertEqual(try Data(contentsOf: destination), old)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
  }

  func testRawCopyRejectsSymlinkAndHardlinkAliases() throws {
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let bytes = Data("recoverable source".utf8)
    try fixture.write(bytes)
    let symbolic = fixture.directory.appendingPathComponent("symbolic.json")
    let hard = fixture.directory.appendingPathComponent("hard.json")
    try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: fixture.fileURL)
    try FileManager.default.linkItem(at: fixture.fileURL, to: hard)
    let repository = ReturnRepository(fileURL: fixture.fileURL)
    for destination in [symbolic, hard] {
      XCTAssertThrowsError(try repository.copyRawArchive(to: destination)) {
        XCTAssertEqual($0 as? ReturnPersistenceFailure, .invalidDestination)
      }
      XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
      XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }
  }

  func testRawCopyUnwritableDirectoryPreservesSourceAndDestination() throws {
    try XCTSkipIf(
      StorageFixtures.isRoot, "UID 0 bypasses directory write permissions; run as a normal user.")
    let fixture = try TemporaryArchive()
    defer { try? fixture.remove() }
    let source = Data("recoverable corrupt source".utf8)
    try fixture.write(source)
    let protectedDirectory = fixture.directory.appendingPathComponent("protected")
    try FileManager.default.createDirectory(
      at: protectedDirectory, withIntermediateDirectories: false)
    let destination = protectedDirectory.appendingPathComponent("recovery.bin")
    let old = Data("previous recovery".utf8)
    try old.write(to: destination)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: protectedDirectory.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: protectedDirectory.path)
    }
    XCTAssertThrowsError(
      try ReturnRepository(fileURL: fixture.fileURL).copyRawArchive(to: destination)
    ) {
      XCTAssertEqual($0 as? ReturnPersistenceFailure, .rawCopyFailed)
    }
    XCTAssertEqual(try Data(contentsOf: destination), old)
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), source)
  }
}
