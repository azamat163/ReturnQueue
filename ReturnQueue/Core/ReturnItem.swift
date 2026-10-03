import Foundation

/// Mutable form inputs become normalized domain values through `validated()`.
public struct ReturnItem: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var merchant: String
  public var dropOffLocation: String?
  public var returnBy: CalendarDay?
  public var purchaseDate: CalendarDay?
  public var droppedOffDate: CalendarDay?
  public var expectedRefundDate: CalendarDay?
  public var purchasePriceCents: Int?
  public var expectedRefundCents: Int?
  public var currency: String
  public var state: ReturnState
  public var closureOutcome: ClosureOutcome?
  public var closureNote: String?
  public var notes: String
  public var policyReference: String?
  public var createdAt: Date
  public var updatedAt: Date
  public var reimbursements: [Reimbursement]

  public init(
    id: UUID = UUID(), title: String, merchant: String, dropOffLocation: String? = nil,
    returnBy: CalendarDay? = nil, purchaseDate: CalendarDay? = nil,
    droppedOffDate: CalendarDay? = nil, expectedRefundDate: CalendarDay? = nil,
    purchasePriceCents: Int? = nil, expectedRefundCents: Int? = nil, currency: String = "USD",
    state: ReturnState = .planned, closureOutcome: ClosureOutcome? = nil,
    closureNote: String? = nil, notes: String = "", policyReference: String? = nil,
    createdAt: Date = Date(), updatedAt: Date? = nil, reimbursements: [Reimbursement] = []
  ) {
    self.id = id
    self.title = title
    self.merchant = merchant
    self.dropOffLocation = dropOffLocation
    self.returnBy = returnBy
    self.purchaseDate = purchaseDate
    self.droppedOffDate = droppedOffDate
    self.expectedRefundDate = expectedRefundDate
    self.purchasePriceCents = purchasePriceCents
    self.expectedRefundCents = expectedRefundCents
    self.currency = currency
    self.state = state
    self.closureOutcome = closureOutcome
    self.closureNote = closureNote
    self.notes = notes
    self.policyReference = policyReference
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
    self.reimbursements = reimbursements
  }

  public func validated() throws -> Self {
    var result = self
    result.title = try normalizedText(title, field: "purchase name", limit: 120, required: true)
    result.merchant = try normalizedText(merchant, field: "store name", limit: 120, required: true)
    result.dropOffLocation = try normalizedOptionalText(
      dropOffLocation, field: "return location", limit: 200)
    result.closureNote = try normalizedOptionalText(
      closureNote, field: "closure note", limit: 1_000)
    result.notes = try normalizedText(notes, field: "notes", limit: 4_000)
    result.policyReference = try normalizedOptionalText(
      policyReference, field: "policy reference", limit: 1_000)
    try Money.validate(cents: purchasePriceCents ?? 0, currency: currency, allowsZero: true)
    if let expectedRefundCents {
      try Money.validate(cents: expectedRefundCents, currency: currency, allowsZero: true)
    }
    result.createdAt = try normalizedTimestamp(createdAt)
    result.updatedAt = try normalizedTimestamp(updatedAt)
    guard reimbursements.count <= 10_000 else { throw ReturnQueueError.tooManyEvents }
    var eventIDs = Set<UUID>()
    result.reimbursements = try reimbursements.map { event in
      guard event.returnItemID == id else { throw ReturnQueueError.invalidEventParent }
      guard eventIDs.insert(event.id).inserted else { throw ReturnQueueError.duplicateEventID }
      return try event.validated()
    }
    // Compute even for open records: malformed arithmetic must fail before saving.
    let difference = try result.unresolvedDifferenceCents()
    _ = try Money.adding(result.moneyReceivedCents(), result.storeCreditCents())
    if state == .closed {
      guard closureOutcome != nil else { throw ReturnQueueError.missingClosureOutcome }
      if let difference, difference != 0, result.closureNote == nil {
        throw ReturnQueueError.missingClosureNote
      }
    } else if closureOutcome != nil {
      throw ReturnQueueError.unexpectedClosureOutcome
    }
    return result
  }

  public func moneyReceivedCents() throws -> Int { try total(for: .money) }
  public func storeCreditCents() throws -> Int { try total(for: .storeCredit) }

  public func unresolvedDifferenceCents() throws -> Int? {
    guard let expectedRefundCents else { return nil }
    try Money.validate(cents: expectedRefundCents, currency: currency, allowsZero: true)
    let received = try Money.adding(moneyReceivedCents(), storeCreditCents())
    let (result, overflow) = expectedRefundCents.subtractingReportingOverflow(received)
    guard !overflow else { throw ReturnQueueError.moneyOverflow }
    return result
  }

  private func total(for kind: ReimbursementKind) throws -> Int {
    guard currency == "USD" else { throw ReturnQueueError.invalidCurrency(currency) }
    return try reimbursements.reduce(0) { total, event in
      guard event.returnItemID == id else { throw ReturnQueueError.invalidEventParent }
      try Money.validate(cents: event.amountCents, currency: currency)
      return event.kind == kind ? try Money.adding(total, event.amountCents) : total
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, title, merchant, dropOffLocation, returnBy, purchaseDate, droppedOffDate
    case expectedRefundDate, purchasePriceCents, expectedRefundCents, currency, state
    case closureOutcome, closureNote, notes, policyReference, createdAt, updatedAt, reimbursements
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeUUID(forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    merchant = try container.decode(String.self, forKey: .merchant)
    dropOffLocation = try container.decodeIfPresent(String.self, forKey: .dropOffLocation)
    returnBy = try container.decodeIfPresent(CalendarDay.self, forKey: .returnBy)
    purchaseDate = try container.decodeIfPresent(CalendarDay.self, forKey: .purchaseDate)
    droppedOffDate = try container.decodeIfPresent(CalendarDay.self, forKey: .droppedOffDate)
    expectedRefundDate = try container.decodeIfPresent(
      CalendarDay.self, forKey: .expectedRefundDate)
    purchasePriceCents = try container.decodeIfPresent(Int.self, forKey: .purchasePriceCents)
    expectedRefundCents = try container.decodeIfPresent(Int.self, forKey: .expectedRefundCents)
    currency = try container.decode(String.self, forKey: .currency)
    state = try container.decode(ReturnState.self, forKey: .state)
    closureOutcome = try container.decodeIfPresent(ClosureOutcome.self, forKey: .closureOutcome)
    closureNote = try container.decodeIfPresent(String.self, forKey: .closureNote)
    notes = try container.decode(String.self, forKey: .notes)
    policyReference = try container.decodeIfPresent(String.self, forKey: .policyReference)
    createdAt = try container.decodeTimestamp(forKey: .createdAt)
    updatedAt = try container.decodeTimestamp(forKey: .updatedAt)
    reimbursements = try container.decode([Reimbursement].self, forKey: .reimbursements)
    guard try validated() == self else { throw ReturnQueueError.noncanonicalArchive }
  }

  public func encode(to encoder: any Encoder) throws {
    let value = try validated()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(value.id, forKey: .id)
    try container.encode(value.title, forKey: .title)
    try container.encode(value.merchant, forKey: .merchant)
    try container.encode(value.dropOffLocation, forKey: .dropOffLocation)
    try container.encode(value.returnBy, forKey: .returnBy)
    try container.encode(value.purchaseDate, forKey: .purchaseDate)
    try container.encode(value.droppedOffDate, forKey: .droppedOffDate)
    try container.encode(value.expectedRefundDate, forKey: .expectedRefundDate)
    try container.encode(value.purchasePriceCents, forKey: .purchasePriceCents)
    try container.encode(value.expectedRefundCents, forKey: .expectedRefundCents)
    try container.encode(value.currency, forKey: .currency)
    try container.encode(value.state, forKey: .state)
    try container.encode(value.closureOutcome, forKey: .closureOutcome)
    try container.encode(value.closureNote, forKey: .closureNote)
    try container.encode(value.notes, forKey: .notes)
    try container.encode(value.policyReference, forKey: .policyReference)
    try container.encode(timestampMilliseconds(value.createdAt), forKey: .createdAt)
    try container.encode(timestampMilliseconds(value.updatedAt), forKey: .updatedAt)
    try container.encode(value.reimbursements, forKey: .reimbursements)
  }
}
