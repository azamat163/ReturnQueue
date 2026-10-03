import Foundation

public enum ReturnState: String, Codable, CaseIterable, Sendable {
  case planned, droppedOff, closed, kept
}

public enum ClosureOutcome: String, Codable, CaseIterable, Sendable {
  case fullRefund, partialRefund, denied, cancelled
}

public enum ReimbursementKind: String, Codable, CaseIterable, Sendable {
  case money, storeCredit
}

public struct Reimbursement: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var returnItemID: UUID
  public var date: CalendarDay
  public var amountCents: Int
  public var kind: ReimbursementKind
  public var note: String

  public init(
    id: UUID = UUID(), returnItemID: UUID, date: CalendarDay, amountCents: Int,
    kind: ReimbursementKind, note: String = ""
  ) {
    self.id = id
    self.returnItemID = returnItemID
    self.date = date
    self.amountCents = amountCents
    self.kind = kind
    self.note = note
  }

  public func validated() throws -> Self {
    var result = self
    try Money.validate(cents: amountCents, currency: "USD")
    result.note = try normalizedText(note, field: "reimbursement note", limit: 1_000)
    return result
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, returnItemID, date, amountCents, kind, note
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeUUID(forKey: .id)
    returnItemID = try container.decodeUUID(forKey: .returnItemID)
    date = try container.decode(CalendarDay.self, forKey: .date)
    amountCents = try container.decode(Int.self, forKey: .amountCents)
    kind = try container.decode(ReimbursementKind.self, forKey: .kind)
    note = try container.decode(String.self, forKey: .note)
    guard try validated() == self else { throw ReturnQueueError.noncanonicalArchive }
  }

  public func encode(to encoder: any Encoder) throws {
    let value = try validated()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(value.id, forKey: .id)
    try container.encode(value.returnItemID, forKey: .returnItemID)
    try container.encode(value.date, forKey: .date)
    try container.encode(value.amountCents, forKey: .amountCents)
    try container.encode(value.kind, forKey: .kind)
    try container.encode(value.note, forKey: .note)
  }

}
