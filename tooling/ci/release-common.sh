#!/usr/bin/env bash
# Sourced by release jobs. Never run with shell tracing: secrets are command inputs.
set +x
set -euo pipefail

fail() { echo "Release setup error: $*" >&2; exit 1; }
require_variable() {
  local variable_name=$1
  [[ -n ${!variable_name:-} ]] || fail "$variable_name is required."
}
require_file_variable() {
  require_variable "$1"
  local variable_name=$1
  [[ -f ${!variable_name} ]] || fail "$variable_name must be a GitLab File variable."
}
release_preflight() {
  [[ ${CI_DEBUG_TRACE:-false} != true ]] || fail "Disable CI_DEBUG_TRACE before running a signing or upload job."
  [[ $(uname -s) == Darwin ]] || fail "iOS release requires macOS."
  [[ ${CI_COMMIT_REF_PROTECTED:-} == true ]] || fail "A protected GitLab ref is required."
  [[ ${CI_COMMIT_TAG:-} =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Use a release tag such as v0.1.0."
  [[ ${IOS_RELEASE_ENABLED:-0} == 1 ]] || fail "Set IOS_RELEASE_ENABLED=1 after configuring release prerequisites."
  [[ ${IOS_EPHEMERAL_RUNNER:-0} == 1 ]] || fail "An isolated ephemeral runner is required; confirm IOS_EPHEMERAL_RUNNER=1."
  require_variable DEVELOPER_DIR
  require_variable XCODE_VERSION
  [[ -d $DEVELOPER_DIR ]] || fail "DEVELOPER_DIR does not exist."
  command -v python3 >/dev/null || fail "Python 3 is required."
  local actual_xcode
  actual_xcode=$(xcodebuild -version) || fail "Select full Xcode, not Command Line Tools."
  [[ $actual_xcode == "Xcode $XCODE_VERSION"$'\n'* ]] || fail "Xcode version does not match XCODE_VERSION."
  [[ $XCODE_VERSION == 26 || $XCODE_VERSION == 26.* ]] || fail "This harness targets Xcode 26; review scripts before changing the toolchain major."
  xcrun --find codesign >/dev/null || fail "Xcode signing tools are missing."
  xcrun --sdk iphoneos --show-sdk-path >/dev/null || fail "The iOS SDK is missing."
}
