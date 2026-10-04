# T006 presentation and editor contract

T005 storage and P1 wire are frozen. This slice adds real create/edit/details,
minimal item navigation and read-error recovery; it does not accept T008 grouping,
status/reimbursement workflows, P2 or full backups/restore. T006 was accepted on
2026-10-04 after distinct review, native 93 tests, unsigned builds and four actual
fresh-simulator UI scenarios; see [verification](../verification.md).

## Public Presentation API

`ReturnQueuePresentation` imports Foundation, Observation, Core and Storage,
with no SwiftUI/UIKit or direct file IO. iOS stays 17+. The host package baseline
becomes macOS 14 because these actual observable models use Observation.

```swift
enum SessionPhase: Equatable, Sendable {
  case notLoaded
  case loading(lastCommitted: ReturnSnapshot?)
  case ready(ReturnSnapshot)
  case loadFailed(ReturnStoreFailure, lastCommitted: ReturnSnapshot?)
}
enum SessionActivity: Equatable, Sendable { case idle, loading, saving, exporting }
enum SessionFailure: Error, Equatable, Sendable {
  case busy, notReady
  case store(ReturnStoreFailure)
  case recovery(ReturnPersistenceFailure)
}
@MainActor @Observable final class AppSession {
  init(store: ReturnStore, recovery: RecoveryFileService)
  private(set) var phase: SessionPhase
  private(set) var activity: SessionActivity
  var snapshot: ReturnSnapshot? { get }
  var canEdit: Bool { get } // ready AND idle
  func load() async throws
  func create(_ item: ReturnItem) async throws -> ReturnSnapshot
  func update(_ item: ReturnItem, expectedRevision: UInt64) async throws -> ReturnSnapshot
  func exportOriginal() async throws -> URL
  func cleanupRecovery(_ url: URL) async throws
}
```

One central activity gate covers load, mutation and export. Concurrent intents fail
with busy before actor entry; Add/Edit/Retry/Export are disabled appropriately.
Loading/failure never looks like an empty ready database. The last committed data
may remain visible while blocked, but cannot be edited. Only monotonically newer
snapshots publish. A mutation that committed must publish even if its caller was
cancelled during the await; no cancellation check may discard its committed result.
The activity gate prevents a delayed save from undoing a newer failed-load phase.
Failed saves preserve ready snapshot; failed loads block all changes.

```swift
enum ReturnEditorField: String, CaseIterable, Sendable {
  case title, merchant, dropOffLocation, returnBy, purchaseDate, expectedRefundDate
  case purchasePrice, expectedRefund, policyReference, notes
}
struct ReturnDraft: Equatable, Sendable {
  var title, merchant, dropOffLocation, returnBy, purchaseDate: String
  var expectedRefundDate, purchasePrice, expectedRefund, policyReference, notes: String
  init() // all empty
  init(item: ReturnItem)
}
enum EditorSaveState: Equatable, Sendable {
  case idle, saving, saved
  case failed(String)
}
@MainActor @Observable final class ReturnEditorModel {
  init(session: AppSession, now: @escaping @Sendable () -> Date = { Date() })
  init(session: AppSession, item: ReturnItem, revision: UInt64,
       now: @escaping @Sendable () -> Date = { Date() })
  var draft: ReturnDraft
  private(set) var fieldErrors: [ReturnEditorField: String]
  private(set) var saveState: EditorSaveState
  var isEditing: Bool { get }
  func save() async -> Bool // true only after durable success
}
```

Editor captures its original item/revision when opened, never substitutes the
current revision at save. It copies the original, changes only the fields above
and updatedAt, preserving ID, createdAt, state, ledger, droppedOffDate and closure.
Create generates one stable ID/creation instant per editor. Dates are optional
Gregorian YYYY-MM-DD inputs, initially empty; amounts are optional plain USD decimal
inputs using exact Money parsing. Blank becomes nil; zero remains explicit zero.
No implicit current calendar day, policy or amount. Required texts/limits and each
date/amount report actionable field errors before the storage command. Full Core
validation still runs. Failed/duplicate/stale saves retain the draft, original base
revision and old data; only success dismisses. Cancel discards the value draft.
Stale messaging offers reload of shared data and cancel/reopen to review the latest
record; reloading session does not overwrite the draft or editor base revision.

## Recovery service and composition

New `Services/RecoveryFileService.swift` is a small actor in Storage. It exposes
`init(directory: URL)`, `makeDestination() throws -> URL` and `remove(_ url: URL) throws`.
It creates/tracks only its own temporary copy URLs; cleanup rejects unowned paths
and never deletes the original archive. IO stays off MainActor. Export obtains an
owned destination then calls actual Store.copyRawArchive; failure cleans its own
staging copy. The sharing sheet's dismissal removes the copy through this actor.
RootView reserves export/cleanup before starting each Task. A pending copy URL is
retained until successful cleanup and blocks another export. Retry cleanup stays
available after dismissing an error and across load phases; only one removal runs
at a time. A completion clears only its captured matching URL, so it cannot forget
another copy. Cleanup never changes the original archive or committed records.

App composition uses Application Support/ReturnQueue/returns.json and real
ReturnRepository/ReturnStore. There is no production fallback to a temporary empty
database. Read failure offers Retry and Export original data; the latter first warns
that the original may be damaged and contain personal purchase details/notes, then
shares a streaming recovery copy. No destructive reset option or restore/import UI.

DEBUG UI test launch arguments (all ignored outside DEBUG): `-rq-ui-testing` plus
`-rq-test-root <UUID>` selects a dedicated subdirectory inside this app container.
`-rq-test-write-failure` injects actual repository pre-replacement failure;
`-rq-test-corrupt` corrupts only that isolated archive, preserving its previous bytes
as a test fixture; `-rq-test-repair-on-retry` restores that fixture only after the
explicit Retry action. Fixture IO lives in a separate DEBUG-only actor adapter.
No arbitrary external path, production data, fake success or sample records.
Implementation and test owners agree exact fixture setup before writing UI tests.

## UI/design and test seam

Use Figma Add 11:194 and Detail 11:243 high-fidelity context and screenshots.
Native NavigationStack/Form, sheet cancellation/confirmation controls and Dynamic
Type replace device/navigation chrome. Custom named asset tokens retain accent
#3155cb and file-owned background/surface/ink/secondary/tint/line. Exact downloaded
SVGs: Add hero package 28pt; Detail location pin 24pt. No substitute/redrawn assets.
Optional details are expandable. Details derive the current item by ID, display all
editor fields and state truthfully, mark unknown values Not set and dates manual.
No dead progression/reminder/P2 tabs. T006 introduced minimal Queue Add/detail
navigation; later T007/T008 grouping/sorting acceptance is fixed separately in
[queue.md](queue.md), without changing this session/editor contract.

Accessibility IDs: `queue.add`, `queue.item.<UUID>`, `detail.edit`,
`editor.<field rawValue>`, `editor.optional`, `editor.save`, `editor.cancel`,
`editor.form`, `editor.error`, `editor.reload`, `load.retry`, `load.export`,
`recovery.confirm`, `recovery.cleanup`. The optional identifier belongs only to
the disclosure label, preserving child field IDs. Tests check the visible viewport
below navigation chrome and above the keyboard/accessory before entering values.
Icons have semantic accessible labels. Presentation tests use actual Store and
isolated temporary repositories. Meaningful tests cover validation, cancel/draft
isolation, failed save, stale revision, latest non-editor preservation, duplicate
submission, activity gate and cancellation after commit, blocked load and raw-copy
cleanup. UI XCTest uses an isolated fresh simulator/container and actual disk:
create -> terminate/relaunch -> detail -> cancel edit/save edit; invalid input;
write failure preserving draft/previous file; load failure/retry/raw recovery.
Screenshots are compared to Figma with native adaptations recorded separately.
