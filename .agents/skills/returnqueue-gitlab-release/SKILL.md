---
name: returnqueue-gitlab-release
description: Prepare, review, or operate ReturnQueue GitLab CI and iOS release builds using its configured runner and signing workflow. Use for pipelines, archives, and authorized TestFlight uploads.
---

# ReturnQueue GitLab release workflow

Read [CI configuration](../../../docs/gitlab-ci.md) and
[release setup](../../../docs/release-setup.md), then inspect `.gitlab-ci.yml` and
the relevant `tooling/ci` script. Preserve protected release gates and the actual
runner constraints. Do not invent a GitLab destination, Apple team, bundle ID,
certificate, profile or API key. Repository scaffolding can be completed without
those values; actual external setup needs the user's supplied destination/access.

Validate the selected commit, quality jobs and release prerequisites. A SwiftPM
library build is not an iOS archive. Use the configured shared app scheme and
official Xcode tooling on the macOS runner. Signing resources stay in temporary
locations with cleanup; never print credentials or put them in artifacts.

TestFlight upload is a separate manual protected release job with explicit opt-in.
Follow authorization already given in the session; preparing CI alone is not an
instruction to upload a build. App Store publication is a separate decision.
Record the build identity and actual result; upload acceptance does not prove
processing completed, testers received it, or App Store approval.
