// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ReturnQueue",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [.library(name: "ReturnQueueCore", targets: ["ReturnQueueCore"])],
  targets: [
    .target(name: "ReturnQueueCore", path: "ReturnQueue/Core"),
    // Compilation seam for the preserved filesystem draft; T005 remains pending.
    .target(
      name: "ReturnQueueStorageDraft", dependencies: ["ReturnQueueCore"],
      path: "ReturnQueue/Services"),
    .testTarget(
      name: "ReturnQueueCoreTests", dependencies: ["ReturnQueueCore"],
      path: "Tests/ReturnQueueCoreTests"),
  ]
)
