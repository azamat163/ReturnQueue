---
name: returnqueue-swift-ios
description: Write or review ReturnQueue Swift and SwiftUI code using official Swift API guidance, the repository formatter, and its MVVM boundaries. Applies to this iOS app and its pure Swift Core.
---

# ReturnQueue Swift and iOS

Read [the project style guide](../../../docs/swift-style-guide.md) and
[architecture](../../../docs/ios-architecture.md) for the code being changed.
These are project skills based on official sources, not skills published by Apple.
Use the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
for naming and API clarity. Use [official swift-format](https://github.com/swiftlang/swift-format)
with `.swift-format` for layout; the configuration is project policy.

Target iOS 17+ and Swift 6 language mode. Keep Core free of SwiftUI, PhotosUI and
UserNotifications. Views render state and forward user intent; screen ViewModels
own presentation under MainActor; persistence and platform services are injected
at the app composition root. Use Observation for new SwiftUI screen state.
Create abstractions where a real test seam or alternate implementation needs one.

Money uses validated integer cents; unknown amounts remain optional. Calendar
deadlines retain day-only semantics. Reimbursements are the source for Summary;
expected amounts and store credit never become received cash. Publish a successful
mutation to shared UI state after durable persistence succeeds. Do not quiet
concurrency diagnostics with unchecked Sendable or broad unsafe isolation.

Run scoped formatter and meaningful tests for the change. Core SwiftPM tests cannot
verify iPhone screens, notifications, signing or distribution; use the iOS scheme
on a real SDK when it exists. Existing draft Core is not accepted product behavior.
