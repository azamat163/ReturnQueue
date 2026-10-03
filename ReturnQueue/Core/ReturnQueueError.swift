import Foundation

public enum ReturnQueueError: Error, Equatable, LocalizedError, Sendable {
  case emptyField(String)
  case textTooLong(String, Int)
  case invalidAmount
  case invalidCurrency(String)
  case invalidDate
  case invalidMoney
  case moneyOverflow
  case missingClosureOutcome
  case unexpectedClosureOutcome
  case missingClosureNote
  case invalidEventParent
  case unsupportedArchiveFormat(String)
  case unsupportedArchiveVersion(Int)
  case duplicateID
  case duplicateEventID
  case archiveTooLarge
  case tooManyRecords
  case tooManyEvents
  case malformedArchive(String)
  case noncanonicalArchive

  public var errorDescription: String? {
    switch self {
    case .emptyField(let field): return "Enter a \(field)."
    case .textTooLong(let field, let limit): return "Keep \(field) within \(limit) characters."
    case .invalidAmount: return "Enter an amount within the supported range."
    case .invalidCurrency: return "Only USD is supported."
    case .invalidDate: return "Enter a valid date."
    case .invalidMoney: return "Enter a dollar amount such as 19.99, with up to two decimal places."
    case .moneyOverflow: return "This amount is too large."
    case .missingClosureOutcome: return "Choose a closure outcome."
    case .unexpectedClosureOutcome: return "Only closed returns can have a closure outcome."
    case .missingClosureNote: return "Explain the difference before closing this return."
    case .invalidEventParent: return "A reimbursement belongs to a different return."
    case .unsupportedArchiveFormat: return "This is not a supported Return Queue backup."
    case .unsupportedArchiveVersion: return "This backup uses an unsupported version."
    case .duplicateID: return "This backup contains duplicate return records."
    case .duplicateEventID: return "This backup contains duplicate reimbursements."
    case .archiveTooLarge: return "This backup exceeds the supported size."
    case .tooManyRecords: return "This backup contains too many returns."
    case .tooManyEvents: return "This backup contains too many reimbursements."
    case .malformedArchive: return "This backup has an invalid structure."
    case .noncanonicalArchive: return "This backup contains unnormalized values."
    }
  }
}

func normalizedText(_ value: String, field: String, limit: Int, required: Bool = false) throws
  -> String
{
  let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !required || !result.isEmpty else { throw ReturnQueueError.emptyField(field) }
  guard result.count <= limit else { throw ReturnQueueError.textTooLong(field, limit) }
  return result
}

func normalizedOptionalText(_ value: String?, field: String, limit: Int) throws -> String? {
  guard let value else { return nil }
  let result = try normalizedText(value, field: field, limit: limit)
  return result.isEmpty ? nil : result
}

let minimumTimestampMilliseconds: Int64 = -62_135_596_800_000
let maximumTimestampMilliseconds: Int64 = 253_402_300_799_999

func timestampMilliseconds(_ date: Date) throws -> Int64 {
  let milliseconds = date.timeIntervalSince1970 * 1_000
  guard milliseconds.isFinite,
    milliseconds >= Double(minimumTimestampMilliseconds),
    milliseconds <= Double(maximumTimestampMilliseconds)
  else { throw ReturnQueueError.invalidDate }
  let result = Int64(milliseconds.rounded())
  guard (minimumTimestampMilliseconds...maximumTimestampMilliseconds).contains(result) else {
    throw ReturnQueueError.invalidDate
  }
  return result
}

func normalizedTimestamp(_ date: Date) throws -> Date {
  Date(timeIntervalSince1970: Double(try timestampMilliseconds(date)) / 1_000)
}
