#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Source-owned macOS visual review, no GitHub Actions required.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [[ "$(uname -s)" != "Darwin" ]] || (( $(sw_vers -productVersion | cut -d. -f1) < 27 )); then
  echo "Native macOS 27+ is required for visual review." >&2
  exit 2
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Use a clean checkout; design review must not mutate source." >&2
  exit 2
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$(printenv RE_DESIGN_PROOF_DIR || true)"
if [[ -z "$out" ]]; then out="$HOME/Desktop/ResearchExplorer-Design-$stamp"; fi
if [[ -e "$out" ]]; then
  echo "Refusing to reuse review directory: $out" >&2
  exit 2
fi
mkdir -p "$out/screenshots"
{
  echo "source_sha=$(git rev-parse HEAD)"
  echo "timestamp=$stamp"
  sw_vers
  xcodebuild -version
  swift --version
} | tee "$out/provenance.txt"

# Screenshots are real rendered view-layer captures, not AI mockups.
RE_SNAPSHOT_DIR="$out/screenshots" swift test --filter ReaderSnapshotTests 2>&1 | tee "$out/snapshot-test.log"

for name in \
  01-first-run-light \
  02-reader-wide-light \
  03-reader-wide-dark \
  04-reader-compact-light \
  05-reader-large-article-text-dark \
  06-search-results-light \
  07-evidence-cited-light \
  08-evidence-metadata-missing-dark \
  09-server-idle-light \
  10-activity-empty-dark \
  11-machine-room-live-light \
  12-machine-room-analytics-dark \
  13-machine-room-exchanges-light \
  14-activity-observed-dark \
  15-machine-room-compact-dark
do
  file="$out/screenshots/$name.png"
  if [[ ! -s "$file" ]]; then
    echo "Missing actual native screenshot: $file" >&2
    exit 1
  fi
  shasum -a 256 "$file" >> "$out/screenshot-sha256.txt"
  sips -g pixelWidth -g pixelHeight "$file" >> "$out/screenshot-dimensions.txt"
done
if [[ -n "$(git status --porcelain)" ]]; then
  echo "FAIL: native review modified tracked or untracked source." >&2
  exit 1
fi
echo "15 native view-layer captures complete: $out/screenshots"
echo "Important: the capture method omits window-server glass/chrome. Review the live window, VoiceOver, Reduce Transparency, contrast and keyboard navigation manually."
