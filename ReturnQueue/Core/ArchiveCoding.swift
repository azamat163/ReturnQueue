import Foundation

struct ArchiveKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

func requireExactKeys<Key: CodingKey & CaseIterable>(
  _ decoder: any Decoder, _ type: Key.Type
) throws {
  let container = try decoder.container(keyedBy: ArchiveKey.self)
  let expected = Set(Key.allCases.map(\.stringValue))
  guard Set(container.allKeys.map(\.stringValue)) == expected else {
    throw ReturnQueueError.malformedArchive("Missing or unknown object keys")
  }
}

extension KeyedDecodingContainer {
  func decodeUUID(forKey key: Key) throws -> UUID {
    let value = try decode(String.self, forKey: key)
    let bytes = Array(value.utf8)
    let hyphens: Set<Int> = [8, 13, 18, 23]
    guard bytes.count == 36,
      bytes.enumerated().allSatisfy({ index, byte in
        hyphens.contains(index)
          ? byte == 45
          : (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }), let uuid = UUID(uuidString: value)
    else { throw ReturnQueueError.malformedArchive("Invalid UUID") }
    return uuid
  }

  func decodeTimestamp(forKey key: Key) throws -> Date {
    let value = try decode(Int64.self, forKey: key)
    guard (minimumTimestampMilliseconds...maximumTimestampMilliseconds).contains(value) else {
      throw ReturnQueueError.invalidDate
    }
    return Date(timeIntervalSince1970: Double(value) / 1_000)
  }
}

/// Checks lexical integers and duplicate keys before Foundation can coerce or discard them.
struct ArchiveJSONScanner {
  private let bytes: [UInt8]
  private var offset = 0

  init(data: Data) throws {
    guard String(data: data, encoding: .utf8) != nil else {
      throw ReturnQueueError.malformedArchive("Invalid UTF-8")
    }
    bytes = Array(data)
  }

  mutating func validate() throws {
    skipWhitespace()
    guard current == 123 else { throw malformed() }
    try parseValue(depth: 0)
    skipWhitespace()
    guard offset == bytes.count else { throw malformed() }
  }

  private var current: UInt8? { offset < bytes.count ? bytes[offset] : nil }

  private func malformed() -> ReturnQueueError {
    .malformedArchive("Invalid JSON syntax, integer token, or nesting")
  }

  private mutating func skipWhitespace() {
    while let byte = current, byte == 32 || byte == 9 || byte == 10 || byte == 13 {
      offset += 1
    }
  }

  private mutating func consume(_ expected: UInt8) throws {
    guard current == expected else { throw malformed() }
    offset += 1
  }

  private mutating func parseValue(depth: Int) throws {
    guard depth <= 64 else { throw malformed() }
    skipWhitespace()
    guard let byte = current else { throw malformed() }
    switch byte {
    case 123: try parseObject(depth: depth)
    case 91: try parseArray(depth: depth)
    case 34: _ = try parseString()
    case 116: try parseLiteral("true")
    case 102: try parseLiteral("false")
    case 110: try parseLiteral("null")
    case 45, 48...57: try parseInteger()
    default: throw malformed()
    }
  }

  private mutating func parseObject(depth: Int) throws {
    try consume(123)
    skipWhitespace()
    if current == 125 {
      offset += 1
      return
    }
    var keys = Set<String>()
    while true {
      skipWhitespace()
      let key = try parseString()
      guard keys.insert(key).inserted else {
        throw ReturnQueueError.malformedArchive("Duplicate object key")
      }
      skipWhitespace()
      try consume(58)
      try parseValue(depth: depth + 1)
      skipWhitespace()
      if current == 125 {
        offset += 1
        return
      }
      try consume(44)
    }
  }

  private mutating func parseArray(depth: Int) throws {
    try consume(91)
    skipWhitespace()
    if current == 93 {
      offset += 1
      return
    }
    while true {
      try parseValue(depth: depth + 1)
      skipWhitespace()
      if current == 93 {
        offset += 1
        return
      }
      try consume(44)
    }
  }

  private mutating func parseString() throws -> String {
    let start = offset
    try consume(34)
    while let byte = current {
      offset += 1
      if byte == 34 {
        do {
          return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset]))
        } catch {
          throw malformed()
        }
      }
      guard byte >= 32 else { throw malformed() }
      if byte == 92 {
        guard let escaped = current else { throw malformed() }
        offset += 1
        if escaped == 117 {
          for _ in 0..<4 {
            guard let hex = current,
              (48...57).contains(hex) || (65...70).contains(hex) || (97...102).contains(hex)
            else { throw malformed() }
            offset += 1
          }
        } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escaped) {
          throw malformed()
        }
      }
    }
    throw malformed()
  }

  private mutating func parseLiteral(_ literal: String) throws {
    for byte in literal.utf8 { try consume(byte) }
  }

  private mutating func parseInteger() throws {
    if current == 45 { offset += 1 }
    guard let first = current, (48...57).contains(first) else { throw malformed() }
    offset += 1
    if first != 48 {
      while let byte = current, (48...57).contains(byte) { offset += 1 }
    }
    if let byte = current, ![32, 9, 10, 13, 44, 93, 125].contains(byte) {
      throw malformed()
    }
  }
}
