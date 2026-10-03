# Return Queue: Swift style guide

Reviewed 2026-10-03. Official guidance comes from Swift.org and Apple Developer;
the local rules below are project decisions. A repository skill can apply those
rules, but is not itself an official Apple or Swift skill.

## Official foundations

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
  guide naming and readable call sites. Use `UpperCamelCase` for types and
  protocols, `lowerCamelCase` for other declarations; Boolean names read as
  predicates. Prefer clear argument labels and document API meaning/invariants.
- [Swift project swift-format](https://github.com/swiftlang/swift-format) is the
  formatter. Swift 6 toolchains include it through `swift format`; its strict lint
  mode can fail CI on formatting warnings. Use a checked-in `.swift-format` and
  the same pinned toolchain in development and CI.
- [Swift concurrency migration guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption/)
  supplies the isolation model. Express isolation in declarations and resolve
  diagnostics rather than adding broad suppression annotations.
- [Apple Observation](https://developer.apple.com/videos/play/wwdc2023/10149/)
  describes `@Observable` integration and ownership through `@State`,
  `@Environment` and `@Bindable` on our iOS 17+ baseline.

## Project layout and naming

Use two-space indentation, 100-column formatting and the checked-in formatter
configuration as the layout authority. These values are our policy, not Swift
API guideline requirements. Run the formatter over owned Swift sources and
tests; exclude generated output, dependencies and synced reference material.
Formatting is a separate change when it would obscure a behavioral review.

Name files after their primary type or coherent feature. Prefer domain names
such as `ReturnItem`, `Reimbursement`, `CalendarDay`, `QueueViewModel` and
`recordReimbursement(for:)`. Avoid vague `Manager`/`Helper` names and redundant
suffixes that add no meaning. Match specification terminology: Money, Store
credit, Expected refund and closure outcome describe different facts.

Use the narrowest access required. `public` exists for Core package consumers,
not by default throughout the app. Keep injected dependencies immutable with
`let`; use `private(set)` for observable state that only the model may change.
Document non-obvious domain invariants and failure behavior with `///`. Comments
explain the reason for an implementation choice rather than restating a line.

## SwiftUI and MVVM

- Views render state and send intents. Validation, money arithmetic, persistence
  and notification calls belong outside `body` and button closures.
- UI-facing reference models are explicitly `@MainActor @Observable`. Use a
  value-type draft for edit forms; committing and cancelling have distinct paths.
- Keep view-owned models stable with `@State`, use `@Bindable` only when bindings
  are needed, and inject existing dependencies. No `.shared` service locator or
  `BaseViewModel` hierarchy.
- Model meaningful operation states so saving, a failure and a successful commit
  are distinguishable. Avoid several independent flags that permit contradictory
  UI states. Small presentational Views need no extra ViewModel.
- Use semantic SwiftUI text styles, system colors and standard controls where
  suitable. Support Dynamic Type, VoiceOver and English product copy; avoid
  layout choices that rely on a single simulator font size.

These are project architecture rules, detailed in
[ios-architecture.md](ios-architecture.md).

## Values, errors and concurrency

Keep Core entities value types. Use USD integer cents and checked arithmetic;
never calculate reimbursements with `Double`. Optional unknown values stay
optional. `CalendarDay` stores a validated Gregorian day, while `Date` is used
for actual instants. Names and types must make the distinction visible.

Return typed errors for user input, disk failures and malformed archives. A load
failure must not become an empty database. Handle each error at the boundary
where the user can act; preserve the draft and old saved data on failure. Avoid
`try?` when it hides a required save/load error, forced unwraps for external data
and `try!` outside deliberately bounded test fixtures.

Aim for Swift 6 language mode in every target. The compiler version and language
mode are separate settings; package tools version alone does not prove all iOS
targets use the intended mode. UI state stays on the main actor, store mutation
on its dedicated actor. `Sendable` conformances must reflect actual safe ownership;
do not use `@unchecked Sendable`, `nonisolated(unsafe)` or blanket `@preconcurrency`
to silence new-code diagnostics. Any necessary interoperability exception requires
a documented ownership reason and focused verification.

Use structured tasks and cancellation for screen work. Retain a task only when
its lifetime needs explicit cancellation. `Task {}` can inherit actor isolation;
it is not a way to move expensive synchronous work off the UI. Do not default to
`Task.detached` or dispatch queues when a service isolation boundary expresses the
required ownership. After `await`, account for cancellation, changed selection
and actor reentrancy before applying results. The durable mutation contract must
prevent overlapping commands from saving stale copies.

Log operational context without item names, receipt contents, notes, amounts,
archive contents or credentials. User-facing errors explain the recovery action;
they do not expose filesystem paths or implementation details.

## Formatting and review

From the repository root, using the selected Swift 6 toolchain:

```sh
swift format lint --strict --configuration .swift-format --recursive Package.swift ReturnQueue Tests
swift format format --in-place --configuration .swift-format --recursive Package.swift ReturnQueue Tests
```

Formatting changes files; lint checks only. When an iOS test target or another
owned Swift folder is added, add it to the harness source list. Do not lint an
entire cloned dependency tree. Formatter success verifies style, not compilation,
business behavior, accessibility or an iOS release. The checked-in harness may
wrap these commands and report missing tools separately.

Review a change against its Spec Kit requirement, ownership boundaries, validation
and durability behavior, cancellation/isolation, accessibility and appropriate
tests. Core behavior uses meaningful XCTest scenarios and temporary storage.
An Xcode simulator/device check remains mandatory for iOS feature acceptance.
The present draft Core must be reconciled with the event ledger before it is
treated as an implementation foundation.
