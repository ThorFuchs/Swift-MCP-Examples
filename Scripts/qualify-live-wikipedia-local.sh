#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Explicit, opt-in live Wikipedia qualification on the native host.
# No GitHub Actions. Do not enable this test in ordinary offline CI.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [[ "$(uname -s)" != Darwin ]] || (( $(sw_vers -productVersion | cut -d. -f1) < 27 )); then
  echo "Native macOS 27+ required." >&2
  exit 2
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Use a clean checkout." >&2
  exit 2
fi
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$(printenv RE_LIVE_PROOF_DIR || true)"
if [[ -z "$out" ]]; then out="$HOME/Desktop/ResearchExplorer-LiveWikipedia-$stamp"; fi
if [[ -e "$out" ]]; then echo "Refusing to reuse $out" >&2; exit 2; fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"
case "$out/" in "$root/"*) echo "Choose output outside the repository." >&2; exit 2;; esac
{
  echo "source_sha=$(git rev-parse HEAD)"
  echo "timestamp_utc=$stamp"
  sw_vers
  xcodebuild -version
  swift --version
} | tee "$out/provenance.txt"
cp Package.resolved "$out/Package.resolved.before"
shasum -a 256 Package.resolved > "$out/lock-sha256-before.txt"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
# Separate runs so a direct-reader failure does not conceal the MCP result.
# Each uses the real public provider. There is no auto-retry beyond its policy.
status=0
for mode in directReaderUsesRealWikipedia guidedMCPUsesRealWikipedia; do
  case "$mode" in
    direct*) marker="LIVE_WIKI DIRECT PASS joined=true";;
    guided*) marker="LIVE_WIKI MCP PASS joined=true";;
  esac
  log="$out/$mode.log"
  if RE_LIVE_WIKIPEDIA=1 swift test --disable-automatic-resolution --filter "LiveWikipediaSmokeTests/$mode" 2>&1 | tee "$log"; then
    if grep -Fq "$marker" "$log" && grep -Eq 'Test run with 1 test(s)? in 1 suite(s)? passed' "$log"; then
      printf '%s\tPASS\n' "$mode" >> "$out/stages.tsv"
    else
      printf '%s\tFAIL: missing actual nonempty test receipt\n' "$mode" >> "$out/stages.tsv"
      status=1
    fi
  else
    printf '%s\tFAIL\n' "$mode" >> "$out/stages.tsv"
    status=1
  fi
done
shasum -a 256 Package.resolved > "$out/lock-sha256-after.txt"
cmp -s Package.resolved "$out/Package.resolved.before" || { echo "Dependency lock drift" >&2; status=1; }
git status --porcelain > "$out/post-status.txt"
if [[ -s "$out/post-status.txt" ]]; then echo "Working tree drift" >&2; status=1; fi
cat "$out/stages.tsv"
echo "Receipt directory: $out"
if (( status != 0 )); then
  echo "Live qualification did not pass. Keep exact failure evidence; do not relax HTML/identity admission."
  exit 1
fi
echo "PASS: direct reader and real guided HTTP MCP journey using English Wikipedia; both joined."
