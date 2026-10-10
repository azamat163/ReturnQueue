# US3 manual refunds and state changes — T009/T010/T011

Status: exact API and policies approved by root on 2026-10-04; independent
tests-first materialization and expected missing-symbol RED passed. Implementation
accepted 2026-10-10 after distinct review, independent 143 native tests, unsigned
Debug/Release builds and eight fresh-simulator UI scenarios; see [verification](../verification.md).
Base: `00ebe88a436cdc5f9570a37b38ff58d5061524b3`. T009–T011 are accepted.
The accepted 106 native tests and five UI cases remain regression requirements.

Authority: spec US3, FR-013–024/025/026/045; [data model](../data-model.md),
[wire](backup.md), [storage](storage.md), [session/editor](presentation.md),
[Queue](queue.md). No persisted fields, format marker, version, enums or model
validation change. This slice is manual journal functionality, without payments,
merchant/bank acceptance, auto-closure, overdue-money claims, P2 or full restore.

## Pure Core API

```swift
public struct RefundSummary: Equatable, Sendable {
  public let moneyCents: Int
  public let storeCreditCents: Int
  public let expectedRefundCents: Int?
  public let differenceCents: Int?
  public var isExcess: Bool { get }
  public init(item: ReturnItem) throws
}

public enum ReturnConfirmation: Equatable, Sendable { case none, confirmed }
public enum ReturnConfirmationReason: Equatable, Sendable {
  case stateChange, reimbursementDeletion, excessReimbursement
}
public enum ReturnMutation: Equatable, Sendable {
  case dropOff(date: CalendarDay, expectedRefundDate: CalendarDay?)
  case keep
  case reopenToReturn
  case reopenWaiting(date: CalendarDay, expectedRefundDate: CalendarDay?)
  case close(outcome: ClosureOutcome, note: String?)
  case addReimbursement(Reimbursement)
  case editReimbursement(Reimbursement)
  case deleteReimbursement(UUID)
}
public enum ReturnTransitionFailure: Error, Equatable, LocalizedError, Sendable {
  case confirmationRequired(ReturnConfirmationReason)
  case missingReimbursement
  case invalidStateAction
  case historyNotesTooLong
}
public struct ReturnTransitionPreview: Equatable, Sendable {
  public let item: ReturnItem
  public let summary: RefundSummary
  public let confirmationReason: ReturnConfirmationReason?
}
public enum ReturnTransitions {
  public static func preview(
    _ command: ReturnMutation, to item: ReturnItem, updatedAt: Date
  ) throws -> ReturnTransitionPreview
  public static func applying(
    _ command: ReturnMutation, to item: ReturnItem, updatedAt: Date,
    confirmation: ReturnConfirmation = .none
  ) throws -> ReturnItem
  public static func requiresExpectedRefundConfirmation(
    from original: ReturnItem, to candidate: ReturnItem
  ) throws -> Bool
}
```

RefundSummary uses the existing checked Money/ReturnItem money, credit and difference
helpers. It checks the combined arithmetic even when expectation is unknown. It
supports a mathematical preview without requiring a closed outcome/explanation.
Whole-domain validation still happens before a candidate can commit. Unknown
expectation gives nil difference and no inferred completeness; known zero stays
zero. Difference is expectation minus money minus credit and can be negative.
There is no exported combined-money total or automatically selected full/partial
outcome. Purchase price does not participate in these calculations.

`preview` first validates the source, builds a value copy, normalizes/validates the
whole candidate and returns its summary and required confirmation. It never writes
or mutates the source. `applying` uses that same preview and rejects a required
confirmation with `confirmationRequired` before returning a candidate. A rejected
command leaves all source fields, timestamps and event ordering unchanged.

Actions:

- `dropOff` is the ordinary action from planned only; another source state fails
  `invalidStateAction`. It sets droppedOff and the supplied separate dates.
- `keep` is permitted from any state for explicit correction; ordinary Keep is
  shown only for planned/droppedOff. It clears the active outcome, retaining all
  dates, ledger and closureNote.
- `reopenToReturn` is permitted from any state, sets planned and clears only the
  active outcome. Drop-off/expected dates, prior closureNote and ledger remain.
- `reopenWaiting` is correction from any state, including a date correction while
  already waiting; it sets droppedOff and the two explicitly supplied dates,
  clears the active outcome and preserves the ledger/prior closureNote.
- `close` is permitted from any state for explicit correction or closure-note
  correction. Ordinary Close is shown only for Waiting. Outcome is mandatory and
  manually chosen: fullRefund → `Refund received`, partialRefund → `Partial refund`,
  denied → `Denied`, cancelled → `Cancelled`. No reimbursement is generated.
- All state commands require `.confirmed`. Closing any known nonzero difference,
  including excess, requires a normalized nonempty explanation. Unknown expectation
  still requires a chosen outcome and confirmation, without a fabricated remainder.
- When close replaces or clears a different normalized nonempty prior closureNote,
  append `Previous closure explanation: <old note>` to existing Notes, separated
  by two newlines when Notes is nonempty. Preserve existing Notes exactly after its
  established normalization. If the resulting Notes exceeds 4000 characters,
  reject with `historyNotesTooLong`; do not truncate or silently discard history.
  An unchanged note is not duplicated. UI explains preservation in Notes and offers
  editing Notes before retrying if the limit prevents the command.
- Reimbursement create rejects an existing event ID with `duplicateEventID`; edit
  requires that ID already exist or throws `missingReimbursement`. Both require
  matching returnItemID (`invalidEventParent` otherwise), positive validated USD
  cents, a valid calendar day and the existing 1000-character event-note limit.
  Edit preserves the event position/ID/parent; create appends; delete removes only
  the exact existing ID and requires explicit `.confirmed`.
- Create/edit on any state is allowed as recorded-history correction. If the
  candidate total exceeds known expectation, including a kind-only edit, explicit
  excess confirmation is required. Delete has its own confirmation showing the
  resulting separate totals/difference. No silent cap or negative compensating event.
- Ledger changes on closed records must retain a valid closure: if the new known
  difference is nonzero and closureNote is absent, throw `missingClosureNote`.
  UI says `Edit the closure explanation or reopen this return first.` No automatic
  reopen or automatic explanatory text is introduced.

Other input failures retain the existing typed ReturnQueueError cases, including
invalid dates/currency/amount, overflow, duplicate IDs and text limits. Archive-wide
IDs/counts/20 MiB validation remains the codec's responsibility at Store commit.
The state command preserves identity, createdAt, unrelated fields and events;
only its intended fields and normalized supplied updatedAt change.

`requiresExpectedRefundConfirmation` is true only if expectedRefundCents changed
and the new known expectation is below candidate recorded money+credit. Unknown →
known zero counts as change; known → unknown does not. An unrelated title/Notes or
purchase-price edit to an existing excess does not renew the warning. It does not
change or validate a closure outcome on behalf of the user.

## Durable Store and shared session extension

```swift
// Actor-isolated, synchronous inside each critical section.
ReturnStore.mutate(
  itemID: UUID, command: ReturnMutation, expectedRevision: UInt64,
  updatedAt: Date, confirmation: ReturnConfirmation = .none
) throws -> ReturnSnapshot
ReturnStore.update(
  _ item: ReturnItem, expectedRevision: UInt64,
  confirmation: ReturnConfirmation = .none
) throws -> ReturnSnapshot

// MainActor; central activity gate and committed publication remain intact.
AppSession.mutate(
  itemID: UUID, command: ReturnMutation, expectedRevision: UInt64,
  updatedAt: Date, confirmation: ReturnConfirmation = .none
) async throws -> ReturnSnapshot
AppSession.update(
  _ item: ReturnItem, expectedRevision: UInt64,
  confirmation: ReturnConfirmation = .none
) async throws -> ReturnSnapshot

// Added typed SessionFailure cases; existing cases retain meaning.
SessionFailure.validation(ReturnQueueError)
SessionFailure.transition(ReturnTransitionFailure)
```

Store obtains its latest writable snapshot, checks exact captured revision and
record existence, applies the semantic command to that latest record, validates
all records/IDs/limits, encodes, writes atomically and publishes. There is no await
inside apply/validate/write/commit. Missing/stale/read-blocked checks precede domain
processing; invalid validation, confirmation and failed write preserve previous
snapshot, revision and original bytes. No UI replacement-array API is introduced.
Core errors escape `mutate` as their original typed errors; AppSession maps them to
validation/transition. Persistence/record/revision errors retain StoreFailure.
Existing `update` gains only the expectation-change guard above; it otherwise keeps
its current validation/error semantics and original createdAt preservation. Domain
confirmation errors escape that guard through the same typed session mapping.

AppSession uses its existing `.saving` activity gate for each command/update,
blocks busy/not-ready writes and publishes successful durable results even if the
caller was cancelled during await. Load failure never becomes writable/empty;
retry/raw sharing/owned-copy cleanup guards are unchanged.

## Presentation API and confirmation binding

```swift
public enum RefundActionState: Equatable, Sendable {
  case idle, awaitingConfirmation(ReturnConfirmationReason), saving, saved
  case failed(String)
}
@MainActor @Observable public final class RefundActionModel {
  public init(session: AppSession, item: ReturnItem, revision: UInt64)
  public private(set) var state: RefundActionState
  public private(set) var pendingPreview: ReturnTransitionPreview?
  public func submit(_ command: ReturnMutation, updatedAt: Date) async -> Bool
  public func confirmPending() async -> Bool
  public func cancelPending()
}
public struct ReimbursementDraft: Equatable, Sendable {
  public var date, amount, note: String
  public var kind: ReimbursementKind
  public init(date: String = "", amount: String = "",
              kind: ReimbursementKind = .money, note: String = "")
  public init(event: Reimbursement)
}
public enum ReimbursementField: String, Sendable { case date, amount, note }
@MainActor @Observable public final class ReimbursementEditorModel {
  public init(session: AppSession, item: ReturnItem, revision: UInt64,
              event: Reimbursement? = nil, newEventID: UUID = UUID(),
              now: @escaping @MainActor @Sendable () -> Date = { Date() },
              timeZone: @escaping @MainActor @Sendable () -> TimeZone = { .current })
  public var draft: ReimbursementDraft
  public private(set) var fieldErrors: [ReimbursementField: String]
  public let action: RefundActionModel
  public func save() async -> Bool
  public func confirmPending() async -> Bool
  public func cancelPending()
}
public enum StateEditorMode: Equatable, Sendable { case dropOff, keep, close, correct }
public struct StateDraft: Equatable, Sendable {
  public var state: ReturnState
  public var droppedOffDate, expectedRefundDate, closureNote: String
  public var closureOutcome: ClosureOutcome?
  public init(state: ReturnState = .planned, droppedOffDate: String = "",
              expectedRefundDate: String = "", closureOutcome: ClosureOutcome? = nil,
              closureNote: String = "")
}
public enum StateEditorField: String, Sendable {
  case droppedOffDate, expectedRefundDate, closureOutcome, closureNote
}
@MainActor @Observable public final class StateEditorModel {
  public init(session: AppSession, item: ReturnItem, revision: UInt64,
              mode: StateEditorMode,
              now: @escaping @MainActor @Sendable () -> Date = { Date() },
              timeZone: @escaping @MainActor @Sendable () -> TimeZone = { .current })
  public var draft: StateDraft
  public private(set) var fieldErrors: [StateEditorField: String]
  public let action: RefundActionModel
  public func save() async -> Bool
  public func confirmPending() async -> Bool
  public func cancelPending()
}

@MainActor @Observable public final class RefundsViewModel {
  public init(session: AppSession)
  public var waitingItems: [ReturnItem] { get }
  public var historyItems: [ReturnItem] { get }
  public var waitingCount: Int { get }
  public var historyCount: Int { get }
}

// Narrow compatible extension of the existing item editor.
EditorSaveState.awaitingConfirmation
ReturnEditorModel.pendingSummary: RefundSummary? { get }
ReturnEditorModel.confirmPendingSave() async -> Bool
ReturnEditorModel.cancelPendingSave()
```

Initial drafts copy values; a new event has empty amount/note, visible default Money
kind and valid local Gregorian today for Date received. Editing an event retains
its original day/kind/ID. Drop-off defaults to the existing date when present,
otherwise valid local today; expected refund date remains optional/manual. A new
close has no preselected outcome; correcting an already closed record copies its
chosen outcome/note. Keep/correct retain all unrelated fields. Invalid/nonfinite
clock, BCE era or years outside 1...9999 leave a required day blank with actionable
validation, never invent an AD date. Calendar inputs never pass through UTC days.

Reimbursement amount is required and positive, parsed by exact Money.cents; blank,
zero, negative, >two fractional digits and out-of-range input fail. Field errors
retain all input; unknown expectations show `Not set`, not $0.00.

`submit` previews against its original item and captured revision. A required
confirmation retains an immutable command, supplied timestamp, revision and preview;
`confirmPending` sends exactly that command under the same revision. Draft edits,
Cancel and stale-revision failure clear pending approval. No approval can authorize
a changed amount/day/kind/outcome or be silently rebound to the latest revision.
A stale failure offers reload and cancel/reopen; reload does not overwrite input or
change the editor base revision. Forms/pickers/buttons are disabled while saving;
duplicate submission is rejected. New action/editor submission and confirmation
methods check Task.isCancelled before entering the session/store mutation boundary;
a caller already cancelled there does not write. Cancellation after actor entry
cannot promise rollback: if durable commit succeeds, the existing session must still
publish that truthfully. Its accepted cancellation contract is unchanged. Only durable success
returns true/dismisses. Confirmations show separate Money/Store credit, expectation,
signed difference or unknown, selected action/outcome and any excess warning.

The existing ReturnEditorModel keeps save(), retained draft/error and its captured
revision. An expectation-change excess enters awaitingConfirmation with a frozen
candidate/timestamp/revision; confirmPendingSave commits that candidate, not a newly
read draft. Changing the draft/cancelling/stale failure invalidates pendingSummary.

## Read projections, navigation and UI semantics

Waiting: droppedOff only, ordered droppedOffDate ascending (unknown last), then
createdAt ascending, UUID ASCII ascending. History: closed/kept only, ordered
updatedAt descending then UUID ASCII ascending. Each projection/count reads the
latest shared committed snapshot through RefundsViewModel; no independent ledger
copies. Counts equal their filtered arrays, never all saved records. These projections
may show last-committed data while load is blocked, without implying successful
loading or permitting mutations. Queue continues
its accepted planned-only grouping. No fake `Closed on` date: History may display
`Last updated` from the actual timestamp, with year. Event rows show Date received,
Money/Store credit, amount and note; display order is received day ascending, UUID
ascending, without changing stored order. History includes events/notes/dates and
chosen outcome, while Keeping item never masquerades as refund.

Root has exactly three working tabs: `To return`, `Waiting for refund`, `History`.
Each has native navigation to the current item by ID. After a durable state change,
select its destination tab (planned→To return; droppedOff→Waiting; closed/kept→History)
and open the same current item there. Cancel/failure leaves current routing intact.
Stale navigation resolves by ID; missing item gets the existing unavailable state.
Every tab respects load/activity blocks; global retry/export/cleanup remains
available, without changing the accepted raw-copy ownership/readiness guards.

Detail adds Dropped off, independent Expected refund date, separate manual totals,
known/unknown difference, ledger and closure outcome/explanation. Copy states that
amounts were recorded by the user; drop-off is not merchant acceptance. No progress
bar infers approval or money arrival; no overdue label is inferred from returnBy.
Working actions: ordinary Mark as dropped off and Keep for active planned; Add
reimbursement, Keep and Close for Waiting; edit/delete existing events and Correct
state on any record, plus Add reimbursement for historical correction where needed.
Deletion asks confirmation, does not delete the return itself. Record deletion and
full backups/restore remain US4.

Root obtained high-fidelity Figma contexts/screenshots for Waiting, refund details,
History, Record reimbursement and Return details under
`/private/tmp/returnqueue-us3-{waiting,refund-details,history,record-reimbursement,return-details}{-context.txt,.png}`.
Implementation must read mandatory figma-design-to-code and figma-swiftui skills
before using those designs. Reuse existing named palette/assets, semantic fonts,
native TabView/NavigationStack/Form/alert controls; device chrome is native. Do not
invent Settings/Summary/reminder buttons or substitute exact in-scope custom assets.
Exact downloaded SVGs from `/private/tmp/returnqueue-us3-assets/` become matching
named vector-preserving imagesets, byte for byte: QueueTabIcon, WaitingTabIcon,
HistoryTabIcon and reimbursement-row ReimbursementMoney are 22×22; native Picker
choices ReimbursementMoneyChoice/ReimbursementCreditChoice are distinct 20×20
assets, not scaled substitutes. `provenance.json` retains source URLs/hashes/dimensions.
Native TabView template rendering/selected tint is an intentional platform
adaptation. Use native segmented Picker for Money/Store credit choices; do not build
a fake segmented HStack. History may add named ColorSuccess #23755a from its exact
context; reuse existing tokens otherwise. DetailPin24 remains unchanged. Do not
fetch tool-instruction sample PNGs or create substitute icon artwork.

Keep previous Add/Queue/detail controls and IDs compatible. Give IDs to actual
labels/controls, not enclosing DisclosureGroup containers that override descendants.
Native sharing dismissal still waits for the real share to disappear before Retry.

Stable IDs:

- Tabs: `tab.toReturn`, `tab.waiting`, `tab.history`.
- Waiting/History lists and counts: `waiting.list`, `waiting.count`, `history.list`,
  `history.count`; rows `waiting.item.<UUID>`, `history.item.<UUID>`; empty states
  `waiting.empty`, `history.empty` only for ready filtered-empty snapshots.
- Detail: `detail.dropOff`, `detail.keep`, `detail.close`, `detail.correctState`,
  `detail.addReimbursement`; totals `refund.money`, `refund.credit`, `refund.expected`,
  `refund.difference`, `refund.outcome`, `refund.closureNote`, `refund.droppedOffDate`.
- Ledger: `reimbursement.item.<UUID>`, `reimbursement.edit.<UUID>`,
  `reimbursement.delete.<UUID>`.
- Reimbursement form: `reimbursement.form`, `reimbursement.date`,
  `reimbursement.amount`, `reimbursement.kind`, `reimbursement.note`,
  `reimbursement.save`, `reimbursement.cancel`, `reimbursement.error`.
- State form: `state.form`, `state.target`, `state.droppedOffDate`,
  `state.expectedRefundDate`, `state.outcome`, `state.closureNote`, `state.save`,
  `state.cancel`, `state.error`.
- Confirmation: `refund.confirm`, `refund.cancelConfirmation`, `refund.confirmation`;
  item-editor expectation warning: `editor.confirmExcess`, `editor.cancelExcess`.
- Existing queue/add/editor/recovery IDs remain stable.

## Ownership and required acceptance

Exact API is approved; source work begins only after independent tests-first
missing-symbol RED and root GO:

- Lead owns ReturnStore.swift, AppSession.swift, the narrow ReturnEditorModel.swift
  excess extension, Package/project/scheme integration and docs/contracts.
- Implementation worker owns new Core RefundSummary.swift/ReturnTransitions.swift,
  new Presentation action/draft/form models, new UI ReimbursementEditor.swift,
  ClosureView.swift, RefundsView.swift, HistoryView.swift, and narrow RootView,
  ReturnDetailView/ReturnEditorView routing/action/confirmation integration.
- Independent test author owns new Core RefundTests, new storage/presentation
  mutation/form tests and US3 UI cases. Existing 106 native/five UI assertions stay.
- Existing model/Money/day/ArchiveCodec/schema/ReturnRepository/recovery files are
  frozen; no concurrent editing of shared files. Separate reviewer checks final
  source; subsequent independent QA verifies the frozen result. Only root publishes.

Tests first cover known/unknown/zero/excess math; checked overflow; no automatic
closure; state confirmation/correction; old-note preservation/4000 limit; event
create/edit/kind/delete/parent/missing/duplicate; closed ledger note failures;
immutable preview and rejected source/timestamp; expectation-change warning;
command/revision-bound confirmation, stale/busy/read-block/error/duplicate-submit
and cancellation after durable commit; real atomic failure preserving bytes.

Fresh-simulator acceptance includes $100 expectation → drop off → $50 Money + $30
Store credit → Partial refund with $20 explanation → History/relaunch; keep and
correct/reopen without losing dates/notes/events; event edit/delete Cancel and Save;
excess confirmation Cancel/accept and changed-draft invalidation; unknown/zero;
invalid input and failed write retaining draft/bytes; all three real tabs/routing.
Existing five UI scenarios, full native suite, both unsigned builds, recursive
strict lint and explicit harness verify (eight offline + full native) must pass.
Actual disk inspection and root Figma/native visual checks are separate evidence.
No task closes merely because code or tests exist; full P1/restore/P2, T015/T016,
physical protection, remote GitLab/signing/release remain separate.
