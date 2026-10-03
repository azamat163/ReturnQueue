import Foundation

public enum ReturnStatus: String, Codable, CaseIterable, Sendable {
  case planned, droppedOff, refunded, kept
}

public enum ReturnQueueError: Error, Equatable, LocalizedError, Sendable {
  case emptyField(String)
  case invalidAmount
  case invalidRefund
  case incompleteRefund
  case invalidDate
  case invalidMoney
  case moneyOverflow
  case unsupportedArchiveVersion(Int)
  case duplicateID

  public var errorDescription: String? {
    switch self {
    case .emptyField(let field): return "Enter a \(field)."
    case .invalidAmount: return "Enter an amount between $0.01 and $1,000,000.00."
    case .invalidRefund: return "The refund must be between zero and the purchase amount."
    case .incompleteRefund: return "Record the full refund before marking this return as refunded."
    case .invalidDate: return "Enter a valid date."
    case .invalidMoney: return "Enter a dollar amount such as 19.99, with up to two decimal places."
    case .moneyOverflow: return "This amount is too large."
    case .unsupportedArchiveVersion: return "This backup uses an unsupported version."
    case .duplicateID: return "This backup contains duplicate return records."
    }
  }
}

/// Dollar amounts are stored in USD cents for this US-only prototype.
public struct ReturnItem: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var merchant: String
  public var amountCents: Int
  public var dropOffLocation: String
  public var deadline: Date
  public var status: ReturnStatus
  public var notes: String
  public var refundReceivedCents: Int
  public var createdAt: Date

  public init(
    id: UUID = UUID(),
    title: String,
    merchant: String,
    amountCents: Int,
    dropOffLocation: String,
    deadline: Date,
    status: ReturnStatus = .planned,
    notes: String = "",
    refundReceivedCents: Int = 0,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.merchant = merchant
    self.amountCents = amountCents
    self.dropOffLocation = dropOffLocation
    self.deadline = deadline
    self.status = status
    self.notes = notes
    self.refundReceivedCents = refundReceivedCents
    self.createdAt = createdAt
  }

  public var remainingRefundCents: Int {
    // Defensive for a draft which has not passed validation yet.
    guard amountCents > 0, refundReceivedCents >= 0 else { return 0 }
    return refundReceivedCents >= amountCents ? 0 : amountCents - refundReceivedCents
  }

  public func validated() throws -> ReturnItem {
    var result = self
    result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    result.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    result.dropOffLocation = dropOffLocation.trimmingCharacters(in: .whitespacesAndNewlines)
    result.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !result.title.isEmpty else { throw ReturnQueueError.emptyField("purchase name") }
    guard !result.merchant.isEmpty else { throw ReturnQueueError.emptyField("store name") }
    guard !result.dropOffLocation.isEmpty else {
      throw ReturnQueueError.emptyField("return location")
    }
    guard (1...100_000_000).contains(amountCents) else { throw ReturnQueueError.invalidAmount }
    guard (0...amountCents).contains(refundReceivedCents) else {
      throw ReturnQueueError.invalidRefund
    }
    guard status != .refunded || refundReceivedCents == amountCents else {
      throw ReturnQueueError.incompleteRefund
    }
    guard deadline.timeIntervalSince1970.isFinite, createdAt.timeIntervalSince1970.isFinite else {
      throw ReturnQueueError.invalidDate
    }
    return result
  }
}
