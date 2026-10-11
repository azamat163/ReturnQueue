# Archive service and Data & backups contract — US4 T012–T014

API approved by root on 2026-10-10 after US3 publication at
`3dd6089b393ad4e3041c997bb14a8069c329bac4`. This is the authoritative implementation
contract. T012–T014 remain unchecked: tests-first materialization/genuine missing-symbol
RED precede implementation; independent review and native/iOS acceptance precede
completion. No persisted model/schema change is authorized.

Scope: T012–014, validated P1 export/replacement, explicit single/all deletion and
native Data & backups. P1 marker/schema, models, money, days, reimbursement/state
semantics stay unchanged. Preserve all existing 143 native/8 UI cases. T015/016,
P2 settings/photos/reminders/Summary and signed release remain separate gates.

## Storage API

All new declarations live in ReturnQueueStorage. Service and session use the same
ReturnStore instance. Public initializers of preview/export are internal; UI cannot
manufacture a staged candidate or owned export. ID is a capability in this process,
not persisted in the archive. Counts are inspection data, not authoritative records.

```swift
public struct RestorePreview: Equatable, Sendable {
  public let id: UUID
  public let returnCount: Int
  public let reimbursementCount: Int
  public let currentReturnCount: Int? // nil in readFailed, never fake zero
}

public struct ArchiveExport: Equatable, Sendable {
  public let id: UUID
  public let url: URL
}

public enum ArchiveConfirmation: Equatable, Sendable {
  case none, confirmed
}

public enum ArchiveFailure: Error, Equatable, Sendable {
  case invalidArchive, archiveTooLarge, sourceUnavailable
  case invalidPreview, stalePreview, confirmationRequired
  case exportFailed, cleanupFailed, invalidExport
}

public actor ArchiveService {
  public init(store: ReturnStore, directory: URL)
  public func exportValidated() async throws -> ArchiveExport
  public func previewImport(from selectedURL: URL) async throws -> RestorePreview
  public func discardPreview(_ id: UUID) async
  public func restore(
    _ id: UUID, confirmation: ArchiveConfirmation = .none
  ) async throws -> ReturnSnapshot
  public func removeExport(_ export: ArchiveExport) throws
}

// Extend the existing actor, keeping synchronous commit transactions.
ReturnStore.delete(
  itemID: UUID, expectedRevision: UInt64,
  confirmation: ArchiveConfirmation = .none
) throws -> ReturnSnapshot
ReturnStore.deleteAll(
  expectedRevision: UInt64, confirmation: ArchiveConfirmation = .none
) throws -> ReturnSnapshot
```

Narrow admitted-export test seam, internal to ReturnQueueStorage:

```swift
// Public init(store:directory:) retains an empty internal observer.
ArchiveService.init(
  store: ReturnStore, directory: URL,
  exportCreatedObserver: @escaping @Sendable (ArchiveExport) -> Void
)
```

Invoke that synchronous nonthrowing callback exactly after protected atomic file
creation and capability registration, before returning the identified export. New
`@testable` tests hold a bounded gate, cancel after admission, release unconditionally
and assert the same capability returns/remains removable. Timeout is a failure.
This observer and the staged-preview observer are the entire test-seam scope, not a
general interception framework. No public/shipping test flags or unsafe isolation.

Store's package-internal functions are visible to ArchiveService in the same target:

```swift
ReturnStore.stageRestore(_ data: Data) throws -> RestorePreview
ReturnStore.discardRestore(_ id: UUID)
ReturnStore.restore(_ id: UUID, confirmation: ArchiveConfirmation) throws -> ReturnSnapshot
ReturnStore.encodedCommittedArchive() throws -> Data
```

Narrow test seam, internal to ReturnQueueStorage (not a shipping public option):

```swift
// Existing public init(persistence:) stays unchanged and installs an empty observer.
ReturnStore.init(
  persistence: any ReturnPersistence,
  restoreStageObserver: @escaping @Sendable () -> Void
)
```

The synchronous nonthrowing observer is called exactly after a valid candidate and
its ID/generation have been registered, before returning that token. New tests use
`@testable import ReturnQueueStorage` and a bounded Sendable gate with unconditional
release; timeout is a test failure. Invalid stage calls no observer. This admits a
deterministic cancelled-after-stage-return proof without unsafe isolation, a new
public test flag or suspension inside a transaction. Production initializer behavior
and old constructors remain unchanged.

Store stages only after a completed initial load: ready/readFailed allowed,
notLoaded rejected with ReturnStoreFailure.notLoaded. Stage decodes immutable bytes
through ArchiveCodec; no partial candidates. One candidate holds its unique ID,
captured validated bytes and private in-memory generation. New valid stage replaces
the previous candidate. Invalid selection does not become a candidate; the model
discards its previous candidate before starting a new selection.

Add `private var generation = UUID()` to Store. Every load attempt, including failed
load, invalidates the prior generation; every successful commit changes it. Failed
ordinary writes leave it unchanged. Public revision still changes only on successful
loads/commits. Existing revision/error semantics must remain compatible. Export,
cleanup and staging do not alter generation, snapshot or revision.

Restore checks explicit confirmation, token existence, generation and allowed state;
revalidates captured bytes, prepares next revision and normalized encoding, atomically
writes once, publishes ready, consumes token and changes generation without suspension.
ArchiveCodec preserves its original pretty/sorted bytes while they fit the unchanged
20 MiB cap. Only an oversized representation retries the same validated archive as
compact sorted JSON without slash escaping; all fields, nulls, values and v1 rules
remain unchanged. A compact result above the same cap still throws archiveTooLarge.
This shared encoder policy applies to restore, validated export and later ordinary
mutations; it does not bypass validation by committing selected raw bytes or add an
extra encoding preflight during preview.
It does not reread selectedURL. Source modification/deletion after preview cannot alter
the inspected candidate. A failed write retains candidate, original state/bytes/revision
for explicit retry; stale/unknown tokens never write. Restoring in readFailed is an
explicit replacement, never silently treating unreadable live data as empty.

New Store.stageRestore/restore/delete/deleteAll check Task.checkCancellation at actual
actor entry before staging or admitting the transaction. A model-only check cannot
protect cancellation while queued for that actor. Once admitted, synchronous validation/
write/publication completes without cancellation checkpoints after irreversible IO;
Session publishes committed success even if caller cancelled while that transaction ran.
Existing create/update/mutate cancellation behavior is not changed by this slice.

After Store.stageRestore has admitted/returned a candidate, Service/Session must return
its token even if the task was cancelled meanwhile. No late Task.checkCancellation
may throw away that identity. The cancelled model receives the exact token, suppresses
UI publication, then discards ONLY that ID. Store.discardRestore(id) is nonthrowing,
id-specific and deliberately not cancellation-blocked; an old cancelled task cannot
discard a newer candidate. A failure before staging has no token and no retained
candidate. This return-then-exact-discard boundary is tested separately from durable
write cancellation, because staging itself changes no live bytes/revision.

For uniform UI mapping, invalid input is ArchiveFailure.invalidArchive/archiveTooLarge;
retain the staged candidate with its original generation after an intervening change
so a known token reports stalePreview, not invalidPreview. Consumed/foreign/discarded
tokens report invalidPreview. Live write/revision
errors retain existing ReturnStoreFailure.writeFailed/revisionOverflow. Delete is
ready-only and uses existing staleRevision/missingRecord/readBlocked errors. All-data
delete writes canonical empty v1, never unlinks live file. Service requires confirmation
even for empty replacement. UI disables Delete all on an already empty archive.

`encodedCommittedArchive()` is ready-only, encodes current committed records on Store
actor and does not write live disk. Snapshot capture is the serialized export point;
later commits do not change that backup. A validated empty backup is valid. In
readFailed, only existing streaming Export original data is available.

## IO, scope and temporary ownership

ArchiveService preview owns external-file IO off MainActor: balance successful
security-scoped start in defer, coordinate the read on Apple platforms, and use existing
bounded regular-file descriptor logic for the coordinated URL. Read at most cap+1;
metadata alone cannot enforce the cap. Selected missing file is sourceUnavailable,
not an empty archive. A false scoped-start is not automatically failure for a local
readable URL; the actual coordinated/read result decides access. Import never writes
the selected URL. Read/decode errors preserve the live archive.

No generic persistence redesign: extract a small internal bounded reader only if it
avoids duplicating proven descriptor logic. Keep existing repository ENOENT-only nil
semantics, injected write stages, protection-before-rename and old tests intact.

Validated export creates a uniquely named `ReturnQueue-backup-<UUID>.json` under its
injected private temporary directory, registers ownership before publication and
uses existing protected atomic repository writing. On failure remove only its own
staged destination; errors cannot delete live/import/saved-user files. Track identity
and exact URL; removeExport rejects forged/unowned/mismatched capability, treats its
own already absent file as removed, and retains ownership on cleanup failure.

Check cancellation before creating an export resource; after registered creation,
ArchiveService and Session return its ArchiveExport despite late cancellation. They
must not throw CancellationError or substitute nil and lose that owned identity.
DataSettingsModel.exportCurrent similarly returns the admitted owned result. A
cancelled view then retains that exact typed copy without presenting native sharing,
explicitly removes it and clears ownership only on success. Failed cancellation
cleanup retains its capability and persistent Retry cleanup; sheet closure/new export
remain guarded. removeExport/cleanupBackup are not cancellation-blocked. Apply the
same rule to an admitted raw result using its returned URL and exact local request ID.

Reuse the finally accepted native RecoveryShare presenter, not a second wrapper.
Data & backups is itself one native SwiftUI sheet; embed the SAME representable in
that sheet's DataSettingsView background, where its attached parent is the actual
presenting owner. Root's background presenter cannot present through an unrelated
already-presented DataSettings sheet. Do not add a sharing SwiftUI sheet, global-window
lookup, custom native cancel control, modal polling, timers or guessed UIKit styles.
Root's existing presenter remains exclusively for Root's raw load-failure recovery.
Future US4 makes one compatible value-initializer extension, leaving the actual
presenter lifecycle unchanged:

```swift
struct RecoveryShare: Identifiable {
  let id: UUID
  let url: URL
  init(id: UUID = UUID(), url: URL)
}
```

Existing `RecoveryShare(url:)` calls continue to generate a fresh ID. Validated
exports use `RecoveryShare(id: export.id, url: export.url)` explicitly; retaining
the current implicit `let id = UUID()` would break matching capability identity.
This is a future US4 source change only; current US3 code is frozen and unchanged.

DataSettingsView holds one typed copy plus an optional identified native request:

```swift
private enum OwnedDataCopy {
  case raw(id: UUID, url: URL)
  case validated(ArchiveExport)
  // id/url computed from the payload; validated uses export.id, never a new alias ID.
}
@State private var ownedCopy: OwnedDataCopy?
@State private var share: RecoveryShare?
@State private var cleanupInProgress = false
```

Reserve the slot before asynchronous export entry. After successful raw/validated
copy, retain its typed capability, then present RecoveryShare with the SAME ID/URL.
Matching actual native dismissal clears only that request's share before starting
cleanup; mismatched late callbacks cannot clear a newer copy. Cleanup checks share
is nil, matching owned identity and single-flight before calling session.cleanupRecovery
for raw or session.cleanupBackup for validated. Never delete selectedURL/live storage.
Release ownedCopy only on successful deletion of that same identity. Failed cleanup
retains capability and enables persistent Retry cleanup, including after dismissing
an error alert. Both retry affordances are disabled while native share owns the file.

While export reservation, ownedCopy or cleanup is outstanding, block new exports,
import/restore confirmation and deletion. Keep DataSettings sheet Close and interactive
dismissal disabled until its owned copy is removed, with an actionable cleanup error;
closing the sheet must not forget the only remaining capability. Additionally block
both closure paths throughout `.saving`, even when no share exists: a destructive
commit result must return to its still-retained screen before requesting sheet dismissal.
Cancelled native
sharing still cleans only the owned temp copy, never the original. After cleanup,
return to the SAME import preview; export/cleanup do not invalidate its store generation.
No dialog closing is proof that the user saved a backup; copy says sharing ended,
not backup saved. Temp IO stays off MainActor.

## Presentation API and durable publication

```swift
AppSession.init(store: ReturnStore, recovery: RecoveryFileService, archive: ArchiveService)
AppSession.exportBackup() async throws -> ArchiveExport
AppSession.previewRestore(from: URL) async throws -> RestorePreview
AppSession.cancelRestore(_ id: UUID) async
AppSession.restore(_ id: UUID, confirmation: ArchiveConfirmation) async throws -> ReturnSnapshot
AppSession.delete(itemID: UUID, expectedRevision: UInt64,
                  confirmation: ArchiveConfirmation) async throws -> ReturnSnapshot
AppSession.deleteAll(expectedRevision: UInt64,
                     confirmation: ArchiveConfirmation) async throws -> ReturnSnapshot
AppSession.cleanupBackup(_ export: ArchiveExport) async throws
```

Require explicit ArchiveService injection in production and fixtures; do not add an
optional unavailable-feature fallback. This changes construction, not old test
assertions. SessionFailure adds `archive(ArchiveFailure)`; existing store errors remain
store(...), cancellation remains cancellation. SessionActivity adds `.importing` for
selection/staging, uses `.saving` for restore/deletes and `.exporting` for backup.
All session intents reserve the central activity gate before awaiting service/Store.
Cleanup owns only temp files and need not block record operations after actual share
dismissal. Preview is not a transaction lock; later mutation/load can stale it.

Models check Task.isCancelled before Store entry. If cancellation occurs after a
durable commit, Session still publishes the actual committed snapshot. A late import
result after screen cancellation is discarded by its exact candidate ID; it cannot
replace a newer UI preview. Duplicate confirms are rejected. Awaited write failure
retains input/preview and does not navigate or claim success.

Approved exact new presentation types for tests-first implementation:

```swift
public enum DataSettingsState: Equatable, Sendable {
  case idle, importing, exporting, saving, succeeded(DataChange)
}
public enum DataChange: Equatable, Sendable { case replaced, deletedAll }
public enum DataSettingsConfirmation: Equatable, Sendable {
  case replace(previewID: UUID), deleteAll(expectedRevision: UInt64)
}

@MainActor @Observable public final class DataSettingsModel {
  public init(session: AppSession)
  public private(set) var state: DataSettingsState
  public private(set) var preview: RestorePreview?
  public private(set) var pendingConfirmation: DataSettingsConfirmation?
  public private(set) var error: String?
  public var canImport: Bool { get }
  public var canExport: Bool { get }
  public var canExportOriginal: Bool { get }
  public var canDeleteAll: Bool { get }
  public var canClose: Bool { get }
  public func selectArchive(from url: URL) async
  public func cancelPreview() async
  public func requestReplacement()
  public func requestDeleteAll()
  public func cancelConfirmation()
  public func confirm() async
  public func exportCurrent() async -> ArchiveExport?
  public func exportOriginal() async -> URL?
}

public enum DeleteReturnSaveState: Equatable, Sendable {
  case idle, saving, succeeded, failed(String)
}
@MainActor @Observable public final class DeleteReturnModel {
  public init(session: AppSession, itemID: UUID, expectedRevision: UInt64)
  public private(set) var saveState: DeleteReturnSaveState
  public private(set) var confirmationRequested: Bool
  public func requestConfirmation()
  public func cancelConfirmation()
  public func confirm() async
}
```

DataSettingsModel retains immutable optional preview and one pending command capturing
candidate ID or displayed snapshot revision. Errors retain preview and return state to
idle so explicit retry is available. Cancelling confirmation does not discard preview;
changing selection/cancelling preview does. `confirm()` applies only captured pending
command and rejects duplicates while saving; it never captures a newer revision/token.
An import intent generation suppresses late UI publication and discards that result's
exact candidate on screen cancellation. `exportCurrent()` returns only owned success,
leaves preview intact and returns nil with actionable error on failure. DataSettingsView
owns returned export through actual native dismissal and cleanup. Models do not claim
the user saved it. canExport is false in loadFailed; canExportOriginal permits existing
raw recovery there, forwarding exportOriginal intent through the same model activity
gate to session.exportOriginal. UI also disables model actions during its owned slot.

`model.canClose` is false during saving/exporting, true during idle/importing and after
a durable success has been recorded. The actual view-level canClose ALSO requires no
export reservation, ownedCopy, native share or cleanup. Toolbar Close uses that same
combined value as `.interactiveDismissDisabled(!canClose)`; it cannot bypass the guard.
Toolbar Close reserves its closing intent synchronously before awaiting preview cancellation;
new async-entry actions, including selected-file callbacks, stay blocked until dismissal.
For importing, either explicit Close or an allowed interactive dismissal invalidates
the import intent and cancels its retained task. Its late result is discarded by exact
preview ID, with no resurrected UI or write. Cancellation is never a fake import error.
`cancelPreview()` handles this importing case as well as discarding an existing preview;
the view's onDismiss/onDisappear must invoke it when no committed change is pending.
It never cancels an already admitted saving transaction.

Instantiate DeleteReturnModel ONLY when the actual Delete return action opens
confirmation, using that displayed record ID and displayed snapshot revision. Do not
construct it once at detail initialization and retain an obsolete revision across
intervening ledger/state saves. Caller must not substitute latest revision at confirm;
stale rejection
keeps the screen actionable. Cancel changes no Store state. Specific small models keep
destructive APIs testable without a generic command hierarchy.

Opening native fileImporter changes only the view's picker-presented binding; it does
not reserve SessionActivity.importing or model.state.importing. UIKit cancellation
does not invoke the importer completion; picker Cancel therefore leaves model, gate,
preview and live data unchanged. Begin importing ONLY on an actual successfully
selected URL forwarded to model.selectArchive. Report genuine selection/provider
errors without interpreting picker cancellation as malformed data.

DataSettings preview is inline in its native Form, with an explicit confirmation alert;
there is no extra preview-sharing modal owner. Native fileImporter completes/dismisses
before returning the selected URL to that Form. Any remaining dismissal transition is
handled by the accepted presenter's actual owner/transition signals, not a delay.

After successful restore/deleteAll, the still-retained sheet reports a frozen committed
DataChange to Root BEFORE requesting sheet dismissal. Root's callback only records that
change; it never clears stored paths or dismisses another sheet from an async completion.
Root retains its DataSettings presentation and operation task throughout saving. The
sheet invokes the committed callback exactly once, independent of Task cancellation
after the admitted durable commit, then requests its own dismissal. Its actual Root
sheet onDismiss consumes the recorded change and clears all three paths/pendingRoute
before showing committed lists. Both ordinary and coincident imported UUIDs get that
reset. Cancel/failure never report the callback or request success dismissal. A failed
write keeps the same sheet/preview and makes Close available for explicit cancellation.
Do not publish a `.succeeded` model state after the view has already been dismissed;
guarding toolbar/interactive closure during saving prevents that lifecycle loss.
Single-delete consumes its admitted confirmation when the operation completes, including
failure or cancellation; it retains the captured revision and an actionable failure
without repeating a filesystem attempt until a new explicit confirmation is requested.
Its saving guard continues to block duplicate confirmation throughout the awaited write.
The native alert uses a separate writable view presentation binding: UIKit may set it
to false before the confirmed action starts. That dismissal does not cancel or replace
the frozen semantic approval; only the explicit Cancel action cancels that approval.
Only confirmed committed success requests the detail's native navigation dismissal
and then removes its ID from the cached paths; failure and Cancel do neither.
Independently, Root projects and prunes navigation IDs absent from the latest ready
committed snapshot, so a deleted record cannot remain a destination or be reintroduced
by a cached path binding. This uses record identity, not return state. Loading and
readFailed do not filter paths; cancellation and failed writes retain the committed
IDs. This missing-ID reconciliation is distinct from the wholesale, including
coincident-ID, reset performed only on the successful Data sheet's actual onDismiss.

## UI and acceptance boundaries

P1 gear on main navigation opens Data & backups directly; P2 T021 later points gear
to Settings. Amend backup.md's existing Settings paragraph after US3 gate release.
The same data.open entry remains available in readFailed alongside Root Retry/Export
original data: open DataSettings for validated replacement, with unknown current count,
disabled ordinary validated export/delete and working raw recovery on its attached owner.
Opening it does not reset/clear the load failure or substitute an empty snapshot.
Native Form, real `.fileImporter(allowedContentTypes: [.json])`, single selection,
native preview/confirm/share. Exact high-fidelity context and local Shield24/Trash20
assets are recorded in the task evidence design provenance; preserve accepted global tab SVGs.

Actual picker testability: DEBUG-only UIFileSharingEnabled and
LSSupportsOpeningDocumentsInPlace Info keys expose ALL Documents under On My iPhone,
not a restricted UUID subtree. Therefore Debug Documents contains only isolated
UUID fixture folders, no personal/live/archive storage; Release keeps both disabled.
Existing private live
ApplicationSupport archive is never exposed. Explicit test arguments prepare a copy
of actually UI-created committed records and bounded malformed variants, never seed
production purchases or invoke fake importer callbacks. Record initial native Files
AX hierarchy/screenshot and freeze locator paths from that observation. Fixture IO
belongs in the DEBUG service; only its owned UUID directories may be removed.

Stable IDs: data.open/form/close/export/restore/deleteAll/error/success;
data.originalConfirm/originalCancel for explicit raw-copy personal/damaged-data warning;
restore.preview/returnCount/eventCount/exportCurrent/replace/cancel/confirm/confirmCancel;
detail.deleteReturn; delete.returnConfirm/returnCancel/allConfirm/allCancel. Assign
control IDs to controls/labels only, avoiding SwiftUI ancestor AX inheritance.

Preview shows selected return/event counts, current count when known, explicit full
replacement warning and optional export current/original. An empty candidate says
0 returns and still warns/needs confirmation. Corrupt live data keeps Add/Edit/Delete
blocked and offers original export or validated replacement. No destructive start-empty.
No account/sync/monetization/photo/reminder controls or synthetic production records.

Tests-first acceptance follows the approved task evidence plan. Meaningful old143+8 plus new native/UI
counts are fixed only after materialization, not chosen to hit a number. Required gates:
genuine RED, full native suite/harness8offline, strict formatter, unsigned Debug/Release,
independent review, fresh UI all baseline/new, real native picker/import/export/disk
proof and Figma/native/large-text visual review. Remote CI/signing/physical-device proof
are separate; opening a share sheet is not proof of saved external backup.
