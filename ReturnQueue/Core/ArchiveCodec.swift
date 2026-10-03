import Foundation

public struct ReturnArchive: Codable, Equatable, Sendable {
  public var format: String
  public var version: Int
  public var records: [ReturnItem]

  public init(records: [ReturnItem]) {
    format = "com.azamat163.returnqueue.p1"
    version = 1
    self.records = records
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case format, version, records
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    format = try container.decode(String.self, forKey: .format)
    version = try container.decode(Int.self, forKey: .version)
    guard format == "com.azamat163.returnqueue.p1" else {
      throw ReturnQueueError.unsupportedArchiveFormat(format)
    }
    guard version == 1 else { throw ReturnQueueError.unsupportedArchiveVersion(version) }
    records = try container.decode([ReturnItem].self, forKey: .records)
    _ = try ArchiveCodec.validatedRecords(records)
  }

  public func encode(to encoder: any Encoder) throws {
    guard format == "com.azamat163.returnqueue.p1" else {
      throw ReturnQueueError.unsupportedArchiveFormat(format)
    }
    guard version == 1 else { throw ReturnQueueError.unsupportedArchiveVersion(version) }
    let values = try ArchiveCodec.validatedRecords(records)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(format, forKey: .format)
    try container.encode(version, forKey: .version)
    try container.encode(values, forKey: .records)
  }

}

/// Portable P1 JSON boundary. It performs no filesystem access or partial imports.
public enum ArchiveCodec {
  public static let maximumArchiveBytes = 20 * 1_024 * 1_024
  public static let maximumRecords = 10_000
  public static let maximumEvents = 10_000

  public static func encode(_ records: [ReturnItem]) throws -> Data {
    let records = try validatedRecords(records)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data: Data
    do {
      data = try encoder.encode(ReturnArchive(records: records))
    } catch let error as ReturnQueueError {
      throw error
    } catch {
      throw ReturnQueueError.malformedArchive("Cannot encode archive")
    }
    guard data.count <= maximumArchiveBytes else { throw ReturnQueueError.archiveTooLarge }
    return data
  }

  public static func decode(_ data: Data) throws -> [ReturnItem] {
    guard data.count <= maximumArchiveBytes else { throw ReturnQueueError.archiveTooLarge }
    var scanner = try ArchiveJSONScanner(data: data)
    try scanner.validate()
    do {
      return try JSONDecoder().decode(ReturnArchive.self, from: data).records
    } catch let error as ReturnQueueError {
      throw error
    } catch {
      throw ReturnQueueError.malformedArchive("Invalid archive values")
    }
  }

  static func validatedRecords(_ records: [ReturnItem]) throws -> [ReturnItem] {
    guard records.count <= maximumRecords else { throw ReturnQueueError.tooManyRecords }
    var recordIDs = Set<UUID>()
    var eventIDs = Set<UUID>()
    var eventCount = 0
    return try records.map { record in
      guard recordIDs.insert(record.id).inserted else { throw ReturnQueueError.duplicateID }
      eventCount += record.reimbursements.count
      guard eventCount <= maximumEvents else { throw ReturnQueueError.tooManyEvents }
      for event in record.reimbursements {
        guard eventIDs.insert(event.id).inserted else { throw ReturnQueueError.duplicateEventID }
      }
      return try record.validated()
    }
  }
}
