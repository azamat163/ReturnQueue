# GitLab CI foundation

The repository now has a [pipeline](../.gitlab-ci.yml) and executable release scripts.
It has not been connected to a GitLab project or runner, and no Apple credentials
have been configured for this project. T001–T008 passed scoped independent checks:
current native package suite 106 tests, unsigned Debug/Release builds and five real
UI tests on a fresh simulator (2026-10-04). Production release prerequisites remain
unmet; no remote GitLab job is claimed. See [actual evidence](../specs/001-free-return-prototype/verification.md).

## Checks available now

`foundation:validate` and `core:validate` run on branch, merge request and tag
pipelines with a Linux Docker runner tagged `linux` and `docker`. Foundation uses
`python:3.12-slim-bookworm` with Git/Bash installed. Core uses the official
`swift:6.2.1-noble` image. Before the first remote run, pin the
image to the digest supplied by the team's registry if immutable image identity
is required. This image is independent of the later macOS/Xcode toolchain.

Foundation checks Spec Kit references and maintained guide/skill links, shell syntax,
offline signing-profile safety tests. Core runs strict official Swift formatting
and SwiftPM tests. Formatter warnings fail the job. Build or test failures remain failures;
there are no success placeholders for missing tools or unconfigured iOS jobs.
Current Core XCTest passed locally on full Xcode; the Linux GitLab job has not run
and earlier local Docker attempts timed out. Passing these checks
would validate the package only, not SwiftUI, iOS notifications, signing, or the
product's requirements.

Local commands, from the repository root:

```sh
python3 tooling/harness.py check
python3 tooling/ci/test-release-tools.py
bash tooling/ci/check-core.sh
```

The [Core check](../tooling/ci/check-core.sh) selects Swift 6.2.1 and places SwiftPM
and Clang caches inside ignored `.build/`. When a local executor is already inside
a sandbox that cannot nest SwiftPM's manifest sandbox, a deliberate local-only
`RQ_SWIFTPM_DISABLE_SANDBOX=1` opt-in can be used. It is rejected in CI. This does
not provide XCTest or the iOS SDK: install full Xcode for Apple-platform tests.
The host now has full Xcode 26.3 and native package verification; local bootstrap
build/launch evidence is tracked separately. No TestFlight validation has run.

## Release jobs, disabled by default

`ios:archive` appears only when `IOS_RELEASE_ENABLED=1` and the ref is a protected
tag matching `v0.1.0`. It is a blocking manual action after Foundation and Core validation. The
[archive script](../tooling/ci/archive-ios.sh) validates its setup and runs the shared app scheme’s simulator tests using a
configured `IOS_TEST_DESTINATION` before decoding or importing signing
credentials into a unique temporary keychain, builds a Release archive, and exports
one App Store Connect IPA. Export's destination is `export`; it does not upload.

`ios:testflight` additionally requires `TESTFLIGHT_UPLOAD_ENABLED=1` and a second
manual action. It consumes the successful archive job's IPA in the same pipeline,
validates the binary and submits it to App Store Connect. Apple processing and
assignment to TestFlight tester groups remain separate actions. The pipeline does
not submit an App Store version for review or make it publicly available.

Both jobs use tags `macos`, `xcode-26`, `ephemeral`. These tags do not install Xcode
or guarantee isolation: register a runner that actually meets those properties.
Use a disposable macOS VM with a dedicated user, one job per VM and destruction
after the job. Signing changes that user's keychain search list temporarily;
sharing the user with another job, project or interactive session is unsupported.
The GitLab `resource_group` also serializes release jobs within this project.
Cleanup traps restore the original search list and remove only this job's keychain
and profile copies; they cannot handle SIGKILL or a dead host. VM teardown is the
final cleanup boundary. A default/login keychain is never deleted or replaced.

Set `DEVELOPER_DIR` and an exact `XCODE_VERSION` matching the installed stable
Xcode 26 release. The runner label pins the major family; the script checks the
exact configured version. Apple upload requirements can change: review the
current [supported Xcode versions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
before enabling a release toolchain.

Artifacts contain only the signed archive/dSYMs and IPA, expire after seven days,
and are restricted to Maintainers. Private keys, imported p12 files, keychains,
decoded profiles and generated export options stay outside artifact paths.

## GitLab setup and validation

1. Connect or mirror this repository into the chosen GitLab project. Choose one
   authoritative development remote and tag/release source; no mirror is configured.
2. Register the Linux runner for Core checks. Register a protected isolated macOS
   runner for releases; do not allow unprotected refs to use the release runner.
3. Validate `.gitlab-ci.yml` in GitLab's CI Lint using project context and simulated
   pipelines for branches, merge requests, protected release tags, and both opt-ins.
   Local YAML parsing does not validate GitLab semantics, project variables or rules.
4. Protect the default branch and `v*` tags; restrict tag creation to trusted release
   maintainers. Add the protected variables listed in [release setup](release-setup.md).
5. When the GitLab tier supports it, protect the `testflight` environment and restrict
   deployment permissions. Protected environments require Premium or Ultimate;
   on other tiers, use protected tags, protected variables and the protected runner.
6. Keep opt-ins off until an app target, its tests and signing have been verified.
   Run the first archive manually, inspect its IPA, then choose the upload action.

Local review includes shell syntax, parsing the YAML, profile rejection tests and
release preflight failures. Remote CI Lint, Linux execution, real archive/export
and App Store Connect upload remain pending their configured environments.

## Primary references

- [Swift official Linux Docker images](https://www.swift.org/install/linux/docker/)
- [Official swift-format usage and strict lint](https://github.com/swiftlang/swift-format)
- [GitLab YAML reference](https://docs.gitlab.com/ci/yaml/)
- [Protected and File CI variables](https://docs.gitlab.com/ci/variables/)
- [GitLab resource groups](https://docs.gitlab.com/ci/resource_groups/)
- [Protected environments and tier requirements](https://docs.gitlab.com/ci/environments/protected_environments/)
- [Apple command-line archive/export](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
- [Apple App Store Connect uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

## T001 bootstrap agreement

The shared application scheme/product is `ReturnQueue` and the project path is
`ReturnQueue.xcodeproj`, matching the release scripts' expected naming. The local
bootstrap Bundle ID is `com.azamat163.returnqueue`; it is provisional and unregistered.
Any future `IOS_BUNDLE_ID`, App Store record and provisioning profile must agree
before signing. No team or credentials are stored in the project.

At the T001 bootstrap handoff, the scheme had Release Archive configuration and
no app test target. T006 added ReturnQueueUITests with four actual UI scenarios;
T008 adds the fifth, checking grouped Queue and durable regrouping, to that shared
scheme. `archive-ios.sh` requires tests/a test plan before signing;
their existence alone does not configure credentials or enable release jobs.
The Linux Core image remains 6.2.1 and has
not been remotely validated; the native author's Xcode toolchain is a separate check.
