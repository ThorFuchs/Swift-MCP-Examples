#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Track C / RE-04: native local qualification without starting GitHub Actions.
# Run from a clean checkout on macOS 27 / Swift 6.4, optionally on Mac Studio.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script requires a native macOS host, not Linux." >&2
  exit 2
fi
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( macos_major < 27 )); then
  echo "Research Explorer requires macOS 27 or later." >&2
  exit 2
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Refusing qualification on a dirty checkout. Use a fresh clone." >&2
  exit 2
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$(printenv RE04_PROOF_DIR || true)"
if [[ -z "$out" ]]; then out="$HOME/Desktop/ResearchExplorer-RE04-$stamp"; fi
mkdir -p "$out"
exec > >(tee "$out/run.log") 2>&1
source_sha="$(git rev-parse HEAD)"
{
  echo "RE-04 / Track C LOCAL NATIVE QUALIFICATION"
  echo "source_sha=$source_sha"
  echo "report_dir=$out"
  echo "timestamp_utc=$stamp"
  sw_vers
  uname -sm
  xcodebuild -version
  swift --version
} | tee "$out/provenance.txt"

if ! swift --version | grep -Eq 'Swift version 6\.4([ .]|$)'; then
  echo "This receipt requires Swift 6.4; no alternative toolchain silently accepted." >&2
  exit 2
fi
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

cp Package.resolved "$out/Package.resolved.before"
shasum -a 256 Package.resolved | tee "$out/lock-sha256-before.txt"
printf 'stage\tstatus\n' > "$out/stages.tsv"

run_stage() {
  local name="$1"
  shift
  echo "=== $name: start ==="
  if "$@" 2>&1 | tee "$out/$name.log"; then
    printf '%s\tPASS\n' "$name" >> "$out/stages.tsv"
  else
    printf '%s\tFAIL\n' "$name" >> "$out/stages.tsv"
    echo "FAILED: $name; inspect $out/$name.log" >&2
    exit 1
  fi
  echo "=== $name: PASS ==="
}

# The full test runner builds the CLI needed by subprocess-based stdio tests.
run_stage "full-sdk-and-example-tests" bash Scripts/test.sh
run_stage "native-app-build" swift build --product ResearchExplorerApp

# Separate nonempty receipts for the imported RE-04 tests.
for suite in InspectorAndRecipeTests JourneyLifecycleTests MCPHTTPJourneyTests; do
  run_stage "focused-$suite" swift test --filter "$suite"
  if ! grep -Eq 'Test run with [1-9][0-9]* tests? in [1-9][0-9]* suites? passed' "$out/focused-$suite.log"; then
    echo "FAIL: $suite did not prove a nonempty Swift Testing execution." >&2
    exit 1
  fi
done

# The real stdio client launches a child process and exchanges actual MCP messages.
run_stage "real-stdio-client-journey" swift run research-explorer --mcp-client

git status --porcelain | tee "$out/post-status.txt"
shasum -a 256 Package.resolved | tee "$out/lock-sha256-after.txt"
if ! cmp -s Package.resolved "$out/Package.resolved.before"; then
  echo "FAIL: Package.resolved changed; original dependency graph is not qualified." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "FAIL: working tree changed during the native proof." >&2
  exit 1
fi
echo "PASS: full tests, native app, three RE-04 suites, stdio journey, and unchanged dependency lock."
echo "Not yet verified: GUI/VoiceOver/manual HTTP demo, final SDK tags, signing, public release."
