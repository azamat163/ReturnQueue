# Return Queue: iOS architecture

Status: implementation contract, reviewed against the product specification on
2026-10-03. The first `ReturnQueue/Core/` model/JSON slice is reconciled with the
current contracts and passed independent review/native 49-test verification.
T005 storage infrastructure passed independent review, native 77 tests and both
unsigned iOS builds on 2026-10-04. T006 Add/edit/details and recovery share passed
distinct review, independent native 93 tests, both builds and four fresh-simulator
UI scenarios on that date. Complete workflows/restore remain pending; see
[slice evidence](../specs/001-free-return-prototype/verification.md).
T001 now has a minimal SwiftUI entry/empty Queue linking the local Core package.
Independent review, unsigned Simulator/Release builds and actual simulator
install/launch passed for T001 on 2026-10-04. Broader P1/P2 workflows and release readiness are not established.

The target is iPhone, iOS 17+, SwiftUI and Swift 6 language mode. The deployment
target is a project assumption; the selected Xcode/SDK must be pinned and tested
before release. MVVM is our project choice, not an Apple architecture standard.

## Responsibility boundaries

| Layer | Owns | Does not own |
| --- | --- | --- |
| SwiftUI View | Layout, accessibility, focus, sheets and bindings to a form draft | Domain validation, disk writes, refund arithmetic or notification scheduling |
| `@MainActor @Observable` screen ViewModel | Draft fields, loading/saving/error states, user intents and projection of committed data | An independent mutable database or file access |
| App-session model | One observable snapshot of the committed local database; selected item IDs and navigation | A second reimbursement ledger or optimistic claims that an edit was saved |
| Services | Serialized durable mutations, JSON/archive files and platform adapters | Screen layout or silently replacing damaged data with an empty list |
| Core | Value types, validation, state transitions, checked money calculations, queue and Summary selectors | SwiftUI, PhotosUI, UserNotifications, permissions or filesystem access |

Observation supports SwiftUI model tracking on the chosen iOS baseline. A view
that owns an observable model uses `@State`; a child that needs editable bindings
uses `@Bindable`. Keep ownership at a stable view/app lifetime and inject existing
models into children rather than constructing a new model inside `body`.
See [Apple: Observation in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10149/)
and [Apple: migration to Observable](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro).

Screen models explicitly use `@MainActor` so their UI-facing state has a visible
isolation contract. Pure Core values use checked `Sendable` conformances where
they cross isolation boundaries. An `async` signature alone is not a guarantee
that work runs away from the main actor. Do not hide filesystem or archive work
inside a main-actor ViewModel. This policy follows the language isolation model,
not an assumption that Observation supplies synchronization.
See [Apple: MainActor](https://developer.apple.com/documentation/swift/mainactor)
and [Swift: incremental concurrency adoption](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption/).

## Dependency construction

The app entry point constructs production services and one app-session model.
Feature ViewModels receive the session model and only the services they need
through initializers. Previews receive seeded in-memory data and fake boundaries.
Use a protocol or injected closure at a real replacement/test boundary, such as
durable storage, current calendar/time and the notification adapter. Keep pure
selectors concrete. No service locator, universal base ViewModel, generic
repository hierarchy or protocol for every type is needed.

Target organization: Core, T005 storage and minimal T001 app/RootView are accepted.
Product screen/ViewModel
organization remains planned:

```text
ReturnQueue/
  Core/                 # Pure package: entities, validation, commands, selectors
  Services/             # Store actor, archive adapter, P2 platform adapters
  UI/
    Shared/             # Common visual elements, app-session model and routing
    Queue/              # QueueView and QueueViewModel
    ReturnDetails/      # Detail and edit flows with value-type form drafts
    Waiting/            # WaitingView and WaitingViewModel
    History/            # HistoryView and HistoryViewModel
    DataBackups/         # Export, restore preview and replacement confirmation
    Summary/            # P2
    Settings/           # P2
  ReturnQueueApp.swift   # Current minimal bootstrap; future service composition
```

Split files by coherent responsibilities. A small display-only subview does not
need its own ViewModel. A form ViewModel may own a value-type draft; cancelling
the form discards it without mutating committed data.

## Mutation and persistence flow

1. A View sends a named intent, such as save draft, record reimbursement or mark
   dropped off. The ViewModel prevents duplicate submission and exposes progress.
2. The store applies the command to its latest committed state. Core validates
   the complete candidate, including IDs, optional fields and checked arithmetic.
3. The storage adapter writes the candidate atomically. Only successful durable
   completion produces a new committed snapshot and revision.
4. The app-session model accepts that snapshot on the main actor. All screens
   project the same snapshot; the ViewModel closes a successful form or displays
   an actionable error while retaining its draft.

The local store is one actor-owned mutation boundary. Disk access and encoding
are off the main actor; mutations must additionally preserve ordering across
suspension points. Actor isolation alone does not prevent another command from
entering during `await`. Initially keep read/apply/validate/write/commit as one
actor-isolated transaction without suspension inside the critical sequence.
If an asynchronous storage implementation is introduced, add an explicit command
queue or revision conflict check rather than saving stale read-modify-write copies.
Return revisions with snapshots so delayed completions cannot overwrite a newer
app-session snapshot.

A failed save preserves the prior durable snapshot. Load corruption is an error
state, not permission to overwrite the file. Restore first decodes and validates
the entire candidate and, in P2, stages safe attachments; only confirmed atomic
replacement changes the active database. Preserve recoverability on every failure
path. [Backup contract](../specs/001-free-return-prototype/contracts/backup.md)
is authoritative for archive contents and restore behavior.

## Domain source of truth

The durable database contains ReturnItems and their reimbursement events; it
does not contain a separately editable total of money returned. The app-session
snapshot is a read model of that committed database. Screen ViewModels never
keep independent mutable copies of its ledger.

- Money is USD integer cents with checked parsing/addition and the limits in the
  [data model](../specs/001-free-return-prototype/data-model.md). Preserve unknown
  optional amounts as `nil`; do not replace them with zero or use `Double` for
  accounting. Money received and store credit remain separate.
- `CalendarDay` represents a validated Gregorian year/month/day. Return deadlines
  and reimbursement days are not UTC timestamps. Use timestamps only where the
  model calls for an instant, such as `createdAt` and `updatedAt`.
- State transitions and closure outcomes follow the current spec: `planned`,
  `droppedOff`, `closed`, `kept`. Closing a return does not create a payment event.
- Summary is a pure projection of events and the selected calendar period. Count
  distinct return IDs with an event, recompute after edits/deletes/restore, and
  never substitute expected refunds, purchase prices or closure dates.

The first Core slice replaces the earlier mandatory amount/location/timestamp
deadline, `refunded` status and single `refundReceivedCents` with optional
CalendarDay fields, closure outcomes and a money/store-credit event ledger.
The exact P1 marker/schema rejects the unreleased draft wire format. Filesystem
access sits in the separate `ReturnQueueStorage` target under Services. T005
replaces the preserved draft with bounded/atomic persistence and serialized
ReturnStore, accepted after independent review/verification. Full restore and UI
acceptance remain separate tasks.

## P1 and P2 isolation

P1 includes the usable local workflow and backup/replacement path. Its launch and
saves do not depend on photos, Summary or notification permission. P2 adds a
photo adapter and an independently testable Summary selector, then Settings and
a reminder coordinator.

The P2 coordinator consumes committed items, local preferences, actual device
permission and a supplied current calendar/time. It derives desired future
requests, reconciles them with the OS adapter and reports scheduling failures.
Notification requests are derived state; the database contains user choices,
not transferable OS permission or OS request identifiers. Changes to date, state,
opt-in, permission, timezone or a replaced database trigger reconciliation.
Return reminders stop after drop-off; refund checks require a separate explicit
choice and date. Failure of this side effect does not roll back a saved return;
show its scheduling status and reconcile again when appropriate.

Preserve calendar deadlines and the chosen local wall-clock time during travel.
Do not replay past requests after restore. DST resolution and OS pending-request
capacity need an explicit implementation policy and boundary tests before P2
acceptance; they are not silently solved by storing a UTC deadline. Notification
delivery remains controlled by iOS. Routing carries an item ID, validates it
against current data and falls back to Queue when unavailable.

## Verification seams

Use existing XCTest tooling unless a later task deliberately changes the test
framework. Tests are required for domain and persistence behavior, not for merely
mirroring property assignments.

| Boundary | Evidence required |
| --- | --- |
| Pure Core | USD parsing/overflow, unknown vs zero, Gregorian validity and date arithmetic, state/closure validation, independent cash/credit event totals |
| Durable store | Failed write preserves old data; malformed and unsupported archives rejected; atomic replacement; serialized concurrent commands and stale completion ordering |
| Feature ViewModel | Draft retained on error; success only after commit; delete/restore updates every projection; duplicate save guarded |
| P2 Summary | Month boundaries, distinct IDs, open/closed/kept events, edits/deletes/restore and known demo totals |
| P2 reminders | Fake permission/clock/scheduler, cancellation, opt-in preservation, timezone/DST, future-only restore and missing-item routing |
| iOS acceptance | Simulator/device workflow, background/relaunch durability, Dynamic Type and VoiceOver, real notification permission/lifecycle and archive share/import |

Inject deterministic calendar/time and temporary filesystem locations. Keep
`UserNotifications` behind a fakeable adapter; unit tests never prompt for OS
permission. Core package tests can establish Core behavior only. An Xcode app
target, simulator tests, archive/signing and a device run are separate evidence.

## Spec Kit integration

[Specification](../specs/001-free-return-prototype/spec.md) and its contracts define
behavior; this document defines implementation boundaries. A feature change updates
spec/plan/tasks before implementation, preserves stable requirement/task IDs and
adds evidence to the relevant task. Do not mark P2 tasks complete because a design
or service interface exists. Review Swift changes against
[the project style guide](swift-style-guide.md).

## T005 storage API

The synchronous persistence boundary and actor state/revision contract are fixed in
[storage.md](../specs/001-free-return-prototype/contracts/storage.md).
`ReturnQueueStorage` owns filesystem access; the app links this local package product
to compile its iOS protection branch. T006 composes real Application Support
persistence with the shared MainActor AppSession and value draft/editor model.

## T006 presentation API

[presentation.md](../specs/001-free-return-prototype/contracts/presentation.md)
defines captured editor revisions, the central activity gate, durable success and
retained drafts on failure. Foundation/Observation Presentation lives in its own
SwiftPM product (macOS 14 host baseline; iOS 17 unchanged); SwiftUI views stay in
the app target. Recovery/DEBUG fixture IO lives in actor services. RootView retains
pending recovery-copy ownership and retry controls until cleanup succeeds.
The shared Xcode scheme includes four real UI tests; package tests cover 16
Presentation cases alongside 49 Core and 28 Storage cases. Full replacement/restore,
grouped queue and reimbursement workflows remain separate tasks.
