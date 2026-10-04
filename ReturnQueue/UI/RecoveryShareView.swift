import SwiftUI
import UIKit

struct RecoveryShare: Identifiable {
  let id = UUID()
  let url: URL
}

struct RecoveryShareView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
