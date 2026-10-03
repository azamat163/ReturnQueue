import Foundation

public struct ReturnArchive: Codable, Sendable {
  public var version: Int
  public var items: [ReturnItem]

  public init(items: [ReturnItem]) {
    self.version = 1
    self.items = items
  }
}

public enum ArchiveCodec {
  public static func encode(_ items: [ReturnItem]) throws -> Data {
    let validatedItems = try validate(items)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    return try encoder.encode(ReturnArchive(items: validatedItems))
  }

  public static func decode(_ data: Data) throws -> [ReturnItem] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let archive = try decoder.decode(ReturnArchive.self, from: data)
    guard archive.version == 1 else {
      throw ReturnQueueError.unsupportedArchiveVersion(archive.version)
    }
    return try validate(archive.items)
  }

  private static func validate(_ items: [ReturnItem]) throws -> [ReturnItem] {
    var ids = Set<UUID>()
    return try items.map { item in
      guard ids.insert(item.id).inserted else { throw ReturnQueueError.duplicateID }
      return try item.validated()
    }
  }
}

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
