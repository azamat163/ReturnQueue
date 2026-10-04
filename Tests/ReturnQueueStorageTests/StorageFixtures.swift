import Foundation
import ReturnQueueCore
import ReturnQueueStorage
import XCTest

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct TemporaryArchive {
  let directory: URL
  let fileURL: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    fileURL = directory.appendingPathComponent("archive.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func remove() throws {
    try FileManager.default.removeItem(at: directory)
  }

  func write(_ data: Data) throws {
    try data.write(to: fileURL)
  }
}

enum StorageFixtures {
  enum InjectedFailure: Error { case precommit }

  static let instant = Date(timeIntervalSince1970: 1_800_000_000.123)
  static var isRoot: Bool { getuid() == 0 }

  static func item(id: UUID = UUID()) -> ReturnItem {
    ReturnItem(id: id, title: "Running shoes", merchant: "Example Store", createdAt: instant)
  }

  static func failingRepository(
    fileURL: URL, stage: ReturnRepository.WriteStage
  ) -> ReturnRepository {
    ReturnRepository(fileURL: fileURL) { requested in
      switch (requested, stage) {
      case (.stage, .stage), (.protection, .protection), (.replacement, .replacement):
        throw InjectedFailure.precommit
      default: break
      }
    }
  }

  /// Builds a large corrupt recovery fixture without keeping the entire source in memory.
  static func writeRepeatedBytes(to url: URL, count: Int) throws {
    XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    let chunk = Data(repeating: 0xA5, count: 64 * 1_024)
    var remaining = count
    while remaining > 0 {
      let amount = min(remaining, chunk.count)
      try handle.write(contentsOf: chunk.prefix(amount))
      remaining -= amount
    }
  }

  static func assertSameBytes(
    _ original: URL, _ copy: URL, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let left = try FileHandle(forReadingFrom: original)
    let right = try FileHandle(forReadingFrom: copy)
    defer {
      try? left.close()
      try? right.close()
    }
    while true {
      let a = try left.read(upToCount: 64 * 1_024) ?? Data()
      let b = try right.read(upToCount: 64 * 1_024) ?? Data()
      guard a == b else {
        XCTFail("Raw copy bytes differ", file: file, line: line)
        return
      }
      if a.isEmpty { return }
    }
  }
}
