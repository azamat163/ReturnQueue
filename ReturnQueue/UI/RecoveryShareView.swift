import SwiftUI
import UIKit

struct RecoveryShare: Identifiable {
  let id = UUID()
  let url: URL
}

struct RecoveryShareView: UIViewControllerRepresentable {
  let share: RecoveryShare?
  let onDismiss: @MainActor @Sendable (UUID) -> Void

  func makeUIViewController(context: Context) -> UIViewController {
    let presenter = RecoverySharePresenter()
    presenter.update(share: share, onDismiss: onDismiss)
    return presenter
  }

  func updateUIViewController(_ controller: UIViewController, context: Context) {
    (controller as? RecoverySharePresenter)?.update(share: share, onDismiss: onDismiss)
  }
}

@MainActor
private final class RecoverySharePresenter: UIViewController {
  private var share: RecoveryShare?
  private var onDismiss: (@MainActor @Sendable (UUID) -> Void)?
  private var activeID: UUID?
  private var completedID: UUID?
  private var activity: UIActivityViewController?
  private var completion: RecoveryShareCompletion?
  private var waitingForTransition = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    presentIfNeeded()
  }

  func update(share: RecoveryShare?, onDismiss: @escaping @MainActor @Sendable (UUID) -> Void) {
    self.share = share
    self.onDismiss = onDismiss
    presentIfNeeded()
  }

  private func presentIfNeeded() {
    guard !waitingForTransition, activeID == nil, let share,
      share.id != completedID,
      viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive
    else { return }

    // This owner is attached to Root, outside SwiftUI's sheet presentation context.
    let owner = parent ?? self
    if let presented = owner.presentedViewController {
      if presented.isBeingDismissed, let transition = presented.transitionCoordinator {
        waitForTransition(transition)
      }
      return
    }
    if let transition = owner.transitionCoordinator, waitForTransition(transition) { return }

    let id = share.id
    let activity = UIActivityViewController(activityItems: [share.url], applicationActivities: nil)
    let completion = RecoveryShareCompletion { [weak self] in self?.didDismiss(id: id) }
    activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
      Task { @MainActor in self?.dismissActivity(id: id) }
    }
    if traitCollection.userInterfaceIdiom == .pad {
      activity.modalPresentationStyle = .popover
      if let popover = activity.popoverPresentationController {
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
    }
    activity.presentationController?.delegate = completion
    activeID = id
    self.activity = activity
    self.completion = completion
    owner.present(activity, animated: true)
  }

  @discardableResult
  private func waitForTransition(_ transition: UIViewControllerTransitionCoordinator) -> Bool {
    waitingForTransition = true
    let registered = transition.animate(alongsideTransition: nil) { [weak self] _ in
      guard let self else { return }
      self.waitingForTransition = false
      self.presentIfNeeded()
    }
    if !registered { waitingForTransition = false }
    return registered
  }

  private func dismissActivity(id: UUID) {
    guard activeID == id, let activity, let completion else { return }
    if activity.presentingViewController == nil {
      completion.finish()
    } else if activity.isBeingDismissed, let transition = activity.transitionCoordinator {
      transition.animate(alongsideTransition: nil) { [weak self] context in
        guard let self, self.activeID == id else { return }
        if !context.isCancelled, activity.presentingViewController == nil {
          completion.finish()
        } else if activity.presentingViewController != nil {
          // This path follows a service's explicit completion, not an abandoned gesture.
          self.dismissAfterServiceCompletion(activity, completion: completion)
        }
      }
    } else {
      dismissAfterServiceCompletion(activity, completion: completion)
    }
  }

  private func dismissAfterServiceCompletion(
    _ activity: UIActivityViewController, completion: RecoveryShareCompletion
  ) {
    // Service completion can precede UIKit's transition. Release the copy only afterwards.
    activity.dismiss(animated: true) {
      guard activity.presentingViewController == nil else { return }
      completion.finish()
    }
  }

  private func didDismiss(id: UUID) {
    guard activeID == id else { return }
    completedID = id
    activeID = nil
    activity = nil
    completion = nil
    onDismiss?(id)
  }
}

@MainActor
private final class RecoveryShareCompletion: NSObject, UIAdaptivePresentationControllerDelegate {
  private let onCompletion: @MainActor @Sendable () -> Void
  private var hasCompleted = false

  init(onCompletion: @escaping @MainActor @Sendable () -> Void) {
    self.onCompletion = onCompletion
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish()
  }

  func finish() {
    guard !hasCompleted else { return }
    hasCompleted = true
    onCompletion()
  }
}
