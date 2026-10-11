import Foundation
import Observation
import ReturnQueueStorage

public enum DeleteReturnSaveState: Equatable, Sendable {
  case idle, saving, succeeded
  case failed(String)
}

@MainActor @Observable
public final class DeleteReturnModel {
  public private(set) var saveState: DeleteReturnSaveState = .idle
  public private(set) var confirmationRequested = false
  private let session: AppSession
  private let itemID: UUID
  private let expectedRevision: UInt64

  public init(session: AppSession, itemID: UUID, expectedRevision: UInt64) {
    self.session = session
    self.itemID = itemID
    self.expectedRevision = expectedRevision
  }

  public func requestConfirmation() {
    guard saveState != .saving, saveState != .succeeded else { return }
    confirmationRequested = true
  }

  public func cancelConfirmation() {
    guard saveState != .saving, saveState != .succeeded else { return }
    confirmationRequested = false
    saveState = .idle
  }

  public func confirm() async {
    guard !Task.isCancelled, confirmationRequested,
      saveState != .saving, saveState != .succeeded
    else { return }
    saveState = .saving
    do {
      _ = try await session.delete(
        itemID: itemID, expectedRevision: expectedRevision, confirmation: .confirmed)
      confirmationRequested = false
      saveState = .succeeded
    } catch is CancellationError {
      confirmationRequested = false
      saveState = .idle
    } catch {
      confirmationRequested = false
      saveState = .failed(dataFailureMessage(error))
    }
  }
}
