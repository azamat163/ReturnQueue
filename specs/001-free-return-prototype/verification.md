# Verification: first P1 Core/JSON slice

Date: 2026-10-03. First-slice acceptance: T002/T003/T004 accepted by root after
separate code review and independent native verification. At that point the other
25 tasks, including T001/T005/T012, remained open. This historical result is
Core/JSON acceptance, not a working P1 iOS app or release.

## Scope

T002 exact P1 JSON v1/schema; T003 CalendarDay, optional amount/date/location,
USD money, event ledger and manual closure validation; T004 meaningful record tests.
Archive contract tests cover only the decode/encode portion of T012.

Public API and wire contract: [backup.md](contracts/backup.md) and
[backup.schema.json](contracts/backup.schema.json). Old unreleased draft v1
archives are rejected by an exact format marker and field schema.

The filesystem draft is moved from Core into a separate ReturnQueueStorageDraft
target for compilation. Its old load/save semantics are not T005 acceptance;
corrupt-load blocking, confirmed replacement and store serialization remain pending.
No UI, permissions, P2 feature, app target or signing is implemented in this slice.

## Independent review

Reviewer `harness_review` did not author this slice. One finding: the original
nesting test used a top-level array, which was rejected before reaching the depth
guard. The test owner corrected it to exercise ArchiveJSONScanner directly with
an object wrapper: depth 64 accepted, depth 65 rejected. Narrow rereview passed;
no other actionable findings remain. Swift functional files were then frozen.

## Independent native verification — PASS

Verifier `workflow_verifier` did not author the slice. Environment: full Xcode
26.3, build 17C529, Apple Swift 6.2.4; native arm64 macOS SwiftPM/XCTest. Root also
confirmed iOS SDK 26.2 and simulator availability. Xcode installation does not
complete app creation/build task T001.

Executed from the implementation checkout:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun swift test \
  --scratch-path /private/tmp/returnqueue-native-verifier-z0w5z9_b/build \
  --cache-path /private/tmp/returnqueue-native-verifier-z0w5z9_b/cache \
  --config-path /private/tmp/returnqueue-native-verifier-z0w5z9_b/config \
  --security-path /private/tmp/returnqueue-native-verifier-z0w5z9_b/security
```

Exit 0; build 17.19 seconds; **49 XCTest methods, 0 failures, 5.920 seconds**:
Archive 23, Money 6, Record 20. Temporary output log:
`/private/tmp/returnqueue-native-verifier-z0w5z9_b/swift-test.log`.
Native package success is the required scoped Core gate; Docker was an earlier
fallback for the then missing Xcode environment, not an additional release gate.

Independent strict formatter, `python3 tooling/harness.py check` and
`git diff --check` passed. The harness counts 55 requirements, 7 stories, 28 tasks;
it establishes document/skill structure, not feature acceptance.

## Author checks and failed attempts

The model author compiled Core/StorageDraft with Swift 6 and ran local adversarial
smoke checks; scoped formatter passed. The development lead's final full-source
formatter, harness check and diff check passed after the two test-only corrections.

Early Docker mounts lacked execute permission for temporary manifests and failed
before compilation; `/tmp:exec` and `/build:exec` fixed that environment error.
Subsequent Linux Swift 6.2.1 runs built the package, but full runtime attempts
stalled in different locations and timed out, both with and without
`--disable-swift-testing`, and with redirected stdout/stderr. No runtime cause
has been established; neither a wrapper fix nor Linux support is claimed.
A direct full XCTest run of an earlier binary completed 49 methods in 7.92 seconds:
48 passed, one failed because the old Int.min expectation used `.8` instead of
`.08`. The test owner corrected that assertion before independent final native
verification. That earlier binary/result is not final acceptance evidence.

## Checks remaining at Core handoff (2026-10-03)

- T001 iOS app target creation/build: pending; Xcode/SDK are now available.
- T005/T012/T013 durable storage, corruption blocking, confirmed replacement: pending.
- T016/T028 simulator/device workflows: pending; no iPhone UI exists yet.
- GitLab pipeline, release signing and TestFlight: not run.
- Linux fallback timeout investigation: unresolved; not counted as PASS.

Only root commits/pushes after final-diff review and scoped checks. No author,
reviewer or verifier in this slice published changes.

## T001 — minimal iOS bootstrap (separate slice)

Date: **2026-10-04, Europe/Moscow**. Status: **T001 accepted by root** after
independent review, both unsigned builds and simulator install/launch smoke passed.
At the T001 handoff: T001/T002/T003/T004 complete; 24 tasks remained open.
The previous Core acceptance above remains valid; Core sources and its tests
are unchanged in this slice.

Scope: checked-in ReturnQueue.xcodeproj, shared ReturnQueue scheme, iOS 17+,
Swift 6 language mode, SwiftUI @main entry and truthful English empty Queue.
The app links the existing local Swift package's ReturnQueueCore product; domain
sources are not copied into the app target. Provisional local Bundle ID:
com.azamat163.returnqueue. Apple registration, team and signing credentials
have not been configured for this project.

No persistence, return editor, operational actions or P2 functionality is provided.
At that handoff T005/T006 and full P1 acceptance remained open. Release Archive
configuration was prepared, but the scheme had no app test target yet; the existing
release script blocked distribution until simulator app tests/test plan and signing
configuration were supplied. The GitLab YAML/release scripts were unchanged.

Author unsigned builds: **PASS**, exit 0 / BUILD SUCCEEDED for both:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/returnqueue-t001-sim-author \
  -clonedSourcePackagesDirPath /private/tmp/returnqueue-t001-packages-author \
  CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/returnqueue-t001-device-author \
  -clonedSourcePackagesDirPath /private/tmp/returnqueue-t001-packages-author \
  CODE_SIGNING_ALLOWED=NO build
```

Logs `/private/tmp/returnqueue-t001-sim-author.log` and
`/private/tmp/returnqueue-t001-device-author.log`. These are unsigned builds,
not a signed archive/IPA or distribution. Earlier sandboxed build failed on
SwiftPM cache/CoreSimulator access; scoped escalation permitted the actual SDK
builds above. The only reported build warning was skipped AppIntents metadata
(no AppIntents dependency). Native strict formatter, plutil project validation,
harness check and diff check passed.

Independent reviewer `harness_review`: **PASS**, no actionable findings. Functional
Swift/project files remained unchanged after this review.

Independent verifier `workflow_verifier`: both unsigned builds **PASS**, exit 0:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t001-debug-verifier-4cbjvmjn/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t001-release-verifier-_6linzof/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Logs `/private/tmp/rq-t001-debug-verifier-4cbjvmjn/build.log` and
`/private/tmp/rq-t001-release-verifier-_6linzof/build.log`.

Simulator smoke **PASS**: iPhone 17 / iOS 26.3, UDID
`5449F349-65C1-4DDF-B11E-9FCF209FBD50`. It was initially Shutdown and had no installed
ReturnQueue bundle. Verifier booted it, installed the Debug app and launched:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun simctl install \
  5449F349-65C1-4DDF-B11E-9FCF209FBD50 \
  /private/tmp/rq-t001-debug-verifier-4cbjvmjn/DerivedData/Build/Products/Debug-iphonesimulator/ReturnQueue.app
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun simctl launch \
  5449F349-65C1-4DDF-B11E-9FCF209FBD50 com.azamat163.returnqueue
```

Launch returned PID **50773**, still alive after three seconds. Screenshot visually
passed: English empty Queue, no fake purchases or unavailable controls. Root also
inspected the screenshot and accepted this gate. Verifier terminated its test app and returned only the used, initially Shutdown
simulator to Shutdown after the smoke run.

Temporary launch metadata `/private/tmp/rq-t001-debug-verifier-4cbjvmjn/launch.json`;
screenshot `/private/tmp/rq-t001-debug-verifier-4cbjvmjn/returnqueue-launch.png`.
Root retained a stable task artifact outside the repository:
`/Users/aagataev/.codex/visualizations/2026/10/03/01a1012c-4737-7c71-8587-6600853c8fec/returnqueue-bootstrap.png`.

This acceptance proves bootstrap compile/install/launch only. It does not complete
T005 persistence, T006 editor, T008 grouping/navigation, T015 accessibility or T016
full P1 workflows. No signed archive, IPA, TestFlight or GitLab pipeline was run.

## T005 storage slice — 2026-10-04

Status: **T005 accepted by root** after separate review and final independent
verification. At that storage handoff five tasks were accepted (T001–T005);
the other 23 remained open.
Frozen Core/wire files and app UI
behavior are unchanged. The local app target links the new ReturnQueueStorage
product so builds compile its iOS protection branch.

Author unsigned builds passed, exit 0, using Xcode 26.3 / Apple Swift 6.2.4:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t005-author-debug-sp88px1q/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t005-author-release-wc_j356l/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Logs: `/private/tmp/rq-t005-author-debug-sp88px1q/build.log` and
`/private/tmp/rq-t005-author-release-wc_j356l/build.log`.
Final author native XCTest passed: **77 tests, 0 failures**, 8.301 seconds, exit 0;
49 Core + 12 repository + 16 store tests. All three permission-specific tests ran
without skips as an unprivileged user. Those tests explicitly skip only UID 0;
directory/malformed/version/size cases always run. The reviewer identified this
portability issue; the owner split/fixed the cases before the final author run.

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun swift test \
  --scratch-path /private/tmp/rq-t005-author-tests-lbrjv4kd/build \
  --cache-path /private/tmp/rq-t005-author-tests-lbrjv4kd/cache \
  --config-path /private/tmp/rq-t005-author-tests-lbrjv4kd/config \
  --security-path /private/tmp/rq-t005-author-tests-lbrjv4kd/security
```

Log: `/private/tmp/rq-t005-author-tests-lbrjv4kd/swift-test.log`.
Strict repository Swift formatter lint and diff check passed. Independent reviewer
accepted the final Services/tests diff after the focused portability correction;
root reviewed Package/project/docs integration without findings.

Final independent native XCTest **PASS**: 77/77, 0 failures, 0 skips, UID 501,
Apple Swift 6.2.4; build 18.59 seconds, test suite 8.298 seconds, exit 0.

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun swift test \
  --scratch-path /private/tmp/rq-t005-final-tests-81e72lxo/build \
  --cache-path /private/tmp/rq-t005-final-tests-81e72lxo/cache \
  --config-path /private/tmp/rq-t005-final-tests-81e72lxo/config \
  --security-path /private/tmp/rq-t005-final-tests-81e72lxo/security
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t005-final-debug-u5mpa7nk/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t005-final-release-2p0sju1h/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Both independent unsigned builds **PASS**, exit 0. Logs:
`/private/tmp/rq-t005-final-tests-81e72lxo/swift-test.log`,
`/private/tmp/rq-t005-final-debug-u5mpa7nk/build.log`,
`/private/tmp/rq-t005-final-release-2p0sju1h/build.log`.
Independent strict lint, foundation harness, diff check, project plist and shared
scheme checks passed. Services/tests were authored separately and reviewed by
`harness_review`; root independently reviewed integration before acceptance.
The verifier authored the storage tests and ran final verification after the
distinct review; neither implementation owner was the sole reviewer.

These checks prove host persistence semantics and compilation of iOS protection
code. Runtime device file protection, app persistence UI, full replacement/restore,
signing and release readiness remain separate checks. T012/T013/T014/T016 remain
open. No Linux support/PASS or remote GitLab run is claimed. Documentation-only
acceptance changes after these gates require scoped consistency checks, not a new
Core runtime run.

## T006 author checks and review handoff (2026-10-04)

At this author handoff T006 remained open until distinct review and independent
simulator verification; the final accepted results are recorded below.
Presentation/session and editor tests were authored separately from UI/services.
The production composition uses the existing Application Support archive and
real ReturnStore; DEBUG UI fixtures use separate UUID directories inside the
test app container. No Core model, wire format or accepted storage source changed.

Author native XCTest passed: **93/93 tests, 0 failures**, 8.332 seconds, exit 0
(49 Core + 28 Storage + 16 Presentation). Command used the same Xcode 26.3
DEVELOPER_DIR and `xcrun swift test` with scratch/cache/config/security under
`/private/tmp/rq-t006-author-tests-fzu8kxfr`; log `swift-test.log` there.
Author unsigned generic Simulator Debug and generic iOS Release builds passed.
Final logs after the focused recovery fix:
`/private/tmp/rq-t006-author-debug-c547r87p/build-final-cleanup.log` and
`/private/tmp/rq-t006-author-release-us90bhza/build-final-cleanup.log`.

The first two full UI runs failed (1/4 passed each); those results are retained:
`/private/tmp/rq-t006-author-ui-tcz2poa1/Results.xcresult` and
`/private/tmp/rq-t006-author-ui-final-5hpwl2lm/Results.xcresult`.
Actual screen recordings confirmed expanded optional fields hidden behind the
keyboard accessory, and the native recovery share sheet whose system close
action was localized independently of the app. Corrections target the editor
Form and safe gesture bounds, scope the nested alert action, and use the system
share close identifier with a filename assertion. The enclosing DisclosureGroup
identifier also overwrote child field IDs; it now belongs only to its label.
Visibility checks include the navigation/keyboard bounds because XCTest reported
fields under the navigation bar as hittable. Targeted diagnostics are retained in
`/private/tmp/rq-t006-author-ui-targeted-d77yhje7/Results.xcresult` and
`/private/tmp/rq-t006-author-ui-create-fixed-u49v2kfx/Results.xcresult`.

Baseline author UI **4/4 PASS**, 0 failures, 222.776 seconds, exit 0:
`/private/tmp/rq-t006-author-ui-full-four-pls9yg8g/Results.xcresult`, with adjacent
`ui-test.log`. Actual cases cover create/optional values/relaunch/edit/cancel,
invalid inputs/unknown values, failed atomic write and blocked corrupt-load/raw
share/explicit retry. This baseline preceded the reviewer's focused cleanup fix.
The reviewer found that a failed temporary-copy cleanup could be forgotten by a
new export. RootView now reserves export/cleanup operations before starting Tasks,
blocks export while a copy remains, and keeps Retry cleanup available independently
of the alert and load phase. APIs, Core, Storage and unit tests did not change.
Affected author recovery UI **PASS**, 34.671 seconds, exit 0:
`/private/tmp/rq-t006-author-ui-cleanup-fixed-w1ndolr6/Results.xcresult` and adjacent
`ui-test.log`. Both unsigned builds and strict recursive lint passed on this tree.
The independent verifier must run all four UI cases on the final reviewed tree;
no test method is excluded from the required acceptance run.

Root visually accepted rendered Add and saved Detail against the supplied Figma
intent/native mapping, including exact package/pin SVGs, colors and native controls.
Stable screenshots are `/Users/aagataev/.codex/visualizations/2026/10/03/01a1012c-4737-7c71-8587-6600853c8fec/returnqueue-add-return.png`
and the adjacent `returnqueue-return-detail.png`. The source screenshots and
attachments remain in the author xcresults; see `docs/design/t006-native-mapping.md`.
Strict recursive Swift lint and the foundation harness passed; these do not
substitute for final independent verification. At this author handoff distinct
final review/verification were pending. GitLab CI, signing and release remain unrun.

## T006 final independent checks (2026-10-04)

Distinct `harness_review` accepted the final source after the cleanup fix; root
reviewed integration and rendered Add/Detail. The independent verifier matched all
48 source fingerprints before/after checks. Native **93/93 PASS**, 0 failures,
0 skips, UID 501, Apple Swift 6.2.4: elapsed 26.608 seconds, suite 8.238 seconds.
Unsigned Debug Simulator and Release iOS builds **PASS**, exit 0, elapsed 34.514
and 17.185 seconds. All **4/4 UI XCTest PASS**, 0 failures/skips, suite 232.885
seconds, exit 0, on fresh iPhone 17 / iOS 26.3 simulator
`3C98A0D0-7F6F-46E2-89A8-0F0D3C25FF5B` (initially Shutdown).

All commands used `DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer`
from the implementation checkout. Evidence root:
`/private/tmp/rq-t006-final-verifier-1h7khfei/`.

```sh
swift test --scratch-path /private/tmp/rq-t006-final-verifier-1h7khfei/native/build \
  --cache-path /private/tmp/rq-t006-final-verifier-1h7khfei/native/cache \
  --config-path /private/tmp/rq-t006-final-verifier-1h7khfei/native/config \
  --security-path /private/tmp/rq-t006-final-verifier-1h7khfei/native/security
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t006-final-verifier-1h7khfei/debug-derived \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t006-final-verifier-1h7khfei/release-derived \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'platform=iOS Simulator,id=3C98A0D0-7F6F-46E2-89A8-0F0D3C25FF5B' \
  -derivedDataPath /private/tmp/rq-t006-final-verifier-1h7khfei/debug-derived \
  -resultBundlePath /private/tmp/rq-t006-final-verifier-1h7khfei/UIResults.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Logs: `native.log`, `debug-build.log`, `release-build.log`, `ui-test.log` under
that evidence root; command/result JSONs and `UIResults.xcresult` preserve the
actual invocations/outcomes. Strict recursive lint, harness, diff, plist and scheme
checks passed. Disk inspection (`disk-verification.json`) confirmed four isolated
UUID archives: edited title/date/7999 cents survived relaunch; corrected unknowns
remain null; failed write retained Original sneakers; explicit recovery restored
bytes matching `test-original.json` SHA-256. Production-default archive was absent
on this fresh test device and the recovery directory contained no leftover copies.

Root accepted T006 after these scoped gates: T001–T006 completed, 22 tasks open.
Fresh test-device cleanup is recorded by the verifier's final handoff; simulator
data and SDK/build caches are not repository artifacts. Root also reviewed the
independent Add/Detail/native-share screenshots; stable files reside in the same
visualization directory as above (`returnqueue-recovery-share.png` added).
No physical-device protection, full backup/restore, P2, remote GitLab, signing or
release acceptance is inferred from these scoped results.
