import ReturnQueueCore
import SwiftUI

struct RootView: View {
  let queue: [ReturnItem]

  var body: some View {
    NavigationStack {
      List(queue) { item in
        VStack(alignment: .leading) {
          Text(item.title)
            .font(.headline)
          Text(item.merchant)
            .foregroundStyle(.secondary)
        }
      }
      .overlay {
        if queue.isEmpty {
          ContentUnavailableView(
            "No returns yet",
            systemImage: "shippingbox",
            description: Text("Adding returns will be available in a future update.")
          )
        }
      }
      .navigationTitle("Queue")
    }
  }
}
