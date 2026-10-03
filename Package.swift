// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReturnQueue",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ReturnQueueCore", targets: ["ReturnQueueCore"])],
    targets: [
        .target(name: "ReturnQueueCore", path: "ReturnQueue/Core"),
        .testTarget(name: "ReturnQueueCoreTests", dependencies: ["ReturnQueueCore"], path: "Tests/ReturnQueueCoreTests")
    ]
)
