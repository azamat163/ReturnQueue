import Foundation

/// Separate user-recorded reimbursements, with an optional signed remainder.
public struct RefundSummary: Equatable, Sendable {
  public let moneyCents: Int
  public let storeCreditCents: Int
  public let expectedRefundCents: Int?
  public let differenceCents: Int?

  public var isExcess: Bool { (differenceCents ?? 0) < 0 }

  public init(item: ReturnItem) throws {
    moneyCents = try item.moneyReceivedCents()
    storeCreditCents = try item.storeCreditCents()
    _ = try Money.adding(moneyCents, storeCreditCents)
    expectedRefundCents = item.expectedRefundCents
    differenceCents = try item.unresolvedDifferenceCents()
  }
}
