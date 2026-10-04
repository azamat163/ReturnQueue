// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ReturnQueue",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [
    .library(name: "ReturnQueueCore", targets: ["ReturnQueueCore"]),
    .library(name: "ReturnQueueStorage", targets: ["ReturnQueueStorage"]),
  ],
  targets: [
    .target(name: "ReturnQueueCore", path: "ReturnQueue/Core"),
    .target(
      name: "ReturnQueueStorage", dependencies: ["ReturnQueueCore"],
      path: "ReturnQueue/Services"),
    .testTarget(
      name: "ReturnQueueCoreTests", dependencies: ["ReturnQueueCore"],
      path: "Tests/ReturnQueueCoreTests"),
    .testTarget(
      name: "ReturnQueueStorageTests", dependencies: ["ReturnQueueCore", "ReturnQueueStorage"],
      path: "Tests/ReturnQueueStorageTests"),
  ]
)
