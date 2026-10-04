// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ReturnQueue",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "ReturnQueueCore", targets: ["ReturnQueueCore"]),
    .library(name: "ReturnQueueStorage", targets: ["ReturnQueueStorage"]),
    .library(name: "ReturnQueuePresentation", targets: ["ReturnQueuePresentation"]),
  ],
  targets: [
    .target(name: "ReturnQueueCore", path: "ReturnQueue/Core"),
    .target(
      name: "ReturnQueueStorage", dependencies: ["ReturnQueueCore"],
      path: "ReturnQueue/Services"),
    .target(
      name: "ReturnQueuePresentation", dependencies: ["ReturnQueueCore", "ReturnQueueStorage"],
      path: "ReturnQueue/Presentation"),
    .testTarget(
      name: "ReturnQueueCoreTests", dependencies: ["ReturnQueueCore"],
      path: "Tests/ReturnQueueCoreTests"),
    .testTarget(
      name: "ReturnQueueStorageTests", dependencies: ["ReturnQueueCore", "ReturnQueueStorage"],
      path: "Tests/ReturnQueueStorageTests"),
    .testTarget(
      name: "ReturnQueuePresentationTests",
      dependencies: ["ReturnQueueCore", "ReturnQueueStorage", "ReturnQueuePresentation"],
      path: "Tests/ReturnQueuePresentationTests"),
  ]
)
