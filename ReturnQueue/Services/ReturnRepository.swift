import Foundation
import ReturnQueueCore

/// Draft filesystem seam only; corruption blocking and replacement are future T005 work.
public struct ReturnRepository: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// Missing data is an empty queue; malformed data is surfaced to the caller.
  public func load() throws -> [ReturnItem] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    return try ArchiveCodec.decode(Data(contentsOf: fileURL))
  }

  public func save(_ items: [ReturnItem]) throws {
    // Validate before touching disk so a failed edit preserves the last save.
    let data = try ArchiveCodec.encode(items)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
  }
}
