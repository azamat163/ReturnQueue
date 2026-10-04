import Foundation
import ReturnQueueCore

public enum ReturnEditorField: String, CaseIterable, Sendable {
  case title, merchant, dropOffLocation, returnBy, purchaseDate, expectedRefundDate
  case purchasePrice, expectedRefund, policyReference, notes
}

public struct ReturnDraft: Equatable, Sendable {
  public var title = ""
  public var merchant = ""
  public var dropOffLocation = ""
  public var returnBy = ""
  public var purchaseDate = ""
  public var expectedRefundDate = ""
  public var purchasePrice = ""
  public var expectedRefund = ""
  public var policyReference = ""
  public var notes = ""

  public init() {}

  public init(item: ReturnItem) {
    title = item.title
    merchant = item.merchant
    dropOffLocation = item.dropOffLocation ?? ""
    returnBy = item.returnBy?.iso8601 ?? ""
    purchaseDate = item.purchaseDate?.iso8601 ?? ""
    expectedRefundDate = item.expectedRefundDate?.iso8601 ?? ""
    purchasePrice = item.purchasePriceCents.map(Self.decimal) ?? ""
    expectedRefund = item.expectedRefundCents.map(Self.decimal) ?? ""
    policyReference = item.policyReference ?? ""
    notes = item.notes
  }

  private static func decimal(_ cents: Int) -> String {
    let remainder = cents % 100
    return "\(cents / 100).\(remainder < 10 ? "0" : "")\(remainder)"
  }
}
