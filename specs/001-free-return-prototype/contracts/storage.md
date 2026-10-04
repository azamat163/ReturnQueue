# P1 storage boundary (T005)

This contract extends the frozen [P1 wire contract](backup.md); it changes no JSON
fields or business validation. T005 supplies storage infrastructure, not backup UI,
restore, deletion, or T006 form acceptance. T005 was accepted on 2026-10-04 after
independent review, native 77/77 tests and unsigned Simulator/Release builds.

## Swift API

The `ReturnQueueStorage` library depends on `ReturnQueueCore`. Its synchronous
`ReturnPersistence: Sendable` boundary exposes:

```swift
func readArchiveData() throws -> Data?
func writeAtomically(_ data: Data) throws
func copyRawArchive(to destination: URL) throws
```

`nil` means opening the actual archive returned ENOENT, including a missing parent.
Permission, malformed, unsupported and oversized files never mean an empty archive.
Reads allocate at most the P1 limit plus one sentinel byte, regardless of file
metadata; a growth race cannot bypass the limit. Raw copying streams into a temporary
destination and atomically publishes that destination. It never decodes the source
or modifies it, supports an oversized corrupt source without loading it into memory,
and rejects the source itself as the destination. Missing source is an explicit error.
This is a recovery seam; export presentation and user warnings remain later tasks.

`ReturnRepository(fileURL:)` implements this boundary. Files use system protection
on iOS (`completeUntilFirstUserAuthentication`) applied to the temporary file before
commit. Validation/encoding, write, protection or atomic replacement failure leaves
the previous original bytes intact. Temporary files are cleaned up. No fallible step
after replacing the original can report an uncommitted write.

```swift
struct ReturnSnapshot: Equatable, Sendable {
  let revision: UInt64
  let records: [ReturnItem]
}

enum ReturnStoreState: Equatable, Sendable {
  case notLoaded
  case ready(ReturnSnapshot)
  case readFailed(ReturnStoreFailure, lastCommitted: ReturnSnapshot?)
}

actor ReturnStore {
  init(persistence: any ReturnPersistence)
  func state() -> ReturnStoreState
  func load() throws -> ReturnSnapshot
  func create(_ item: ReturnItem) throws -> ReturnSnapshot
  func update(_ item: ReturnItem, expectedRevision: UInt64) throws -> ReturnSnapshot
  func copyRawArchive(to destination: URL) throws
}
```

Methods are actor-isolated and synchronous internally (callers await actor entry).
`load` retries actual reading, validates the whole archive, and increments a monotonic
session revision on success. Genuine missing archive becomes a ready empty snapshot;
no file is written during load. A failed load/retry enters `readFailed`, preserving the
last committed snapshot for diagnostics/display without making it writable. All
normal mutations require `ready`; `notLoaded` and `readFailed` block writes.

`create` appends to the latest committed records, never replaces an existing ID.
`update` requires an existing ID and the exact current snapshot revision; a stale
editor is rejected rather than overwriting intervening work. It preserves the original
`createdAt`; other fields come from the supplied validated item. Both validate and
normalize the entire candidate, including archive-wide identifiers/counts, encode,
atomically write, then publish the new snapshot/revision. There is no suspension
between applying a mutation and committed publication. Failed validation/encoding or
write preserves state, revision and bytes. Revision overflow is rejected before IO.
No public store method accepts a replacement array from UI.

`ReturnStoreFailure` has content-free cases `notLoaded`, `readBlocked`,
`readFailed`, `writeFailed`, `invalidRecords`, `staleRevision`, `missingRecord`,
and `revisionOverflow`. `ReturnPersistenceFailure` cases are `readFailed`,
`writeFailed`, `archiveTooLarge`, `sourceMissing`, `rawCopyFailed`, and
`invalidDestination`. No case carries private content.

The repository initializer accepts a default no-op synchronous
`failureInjector: @Sendable (ReturnRepository.WriteStage) throws -> Void`.
Stages `stage`, `protection`, and `replacement` run before each corresponding
operation; the protection seam also runs on macOS so failure preservation is testable.
This seam cannot change the transaction ordering. Public errors never contain user fields or filesystem paths.
Raw-copy failure does not change store state or revision. Store deletion/whole-archive
restore and attachment support are explicitly outside this API/slice.

## Verification boundary

Separate persistence tests exercise real temporary files and a synchronous injected
failure seam: first load/missing versus read error; rejected writes before load and
after failed retry; malformed/version/size limits; normalized restart roundtrip;
atomic failure preserving original bytes and committed revision; duplicate IDs and
missing/stale edits; concurrent creates preserving both records; raw recovery including
oversized bytes; iOS protection branch compilation through unsigned app builds.
Core archive tests remain unchanged. T012 full restore/archive acceptance stays open.
