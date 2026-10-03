import ReturnQueueCore
import SwiftUI

@main
struct ReturnQueueApp: App {
  // Bootstrap has no persistence or editing yet; never substitute sample purchases.
  private let initialQueue: [ReturnItem] = []

  var body: some Scene {
    WindowGroup {
      RootView(queue: initialQueue)
    }
  }
}
