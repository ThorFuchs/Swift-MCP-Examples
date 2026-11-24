#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Source-owned DocC build without a new SwiftPM plugin dependency or Actions.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "The complete example requires the native macOS toolchain." >&2
  exit 2
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 27 )); then
  echo "macOS 27+ required." >&2
  exit 2
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Use a clean checkout for an exact-source documentation receipt." >&2
  exit 2
fi
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$(printenv RE_DOCC_DIR || true)"
if [[ -z "$out" ]]; then out="$HOME/Desktop/ResearchExplorer-DocC-$stamp"; fi
if [[ -e "$out" ]]; then echo "Refusing to reuse $out" >&2; exit 2; fi
mkdir -p "$out"
out="$(cd "$out" && pwd)"
case "$out/" in "$root/"*) echo "Choose an output directory outside the checkout." >&2; exit 2;; esac
mkdir -p "$out/graphs" "$out/archives" "$out/logs"
docc="$(xcrun --find docc)"
{
  echo "source_sha=$(git rev-parse HEAD)"
  echo "timestamp=$stamp"
  sw_vers
  xcodebuild -version
  swift --version
  echo "docc=$docc"
} | tee "$out/provenance.txt"
cp Package.resolved "$out/Package.resolved.before"

# The compiler emits symbol graphs, including executable/internal symbols.
# A new scratch path avoids a cache hit hiding a missing graph.
# No manifest or lock changes; dependency resolution must use the existing lock.
for target in ResearchExplorerApp ResearchExplorer; do
  swift build --scratch-path "$out/build" --disable-automatic-resolution --target "$target" \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir -Xswiftc "$out/graphs" \
    -Xswiftc -symbol-graph-minimum-access-level -Xswiftc internal \
    2>&1 | tee "$out/logs/symbols-$target.log"
done

for target in ExplorerDomain WikimediaAccess ExplorerMCP ExplorerPresentation ResearchExplorer ResearchExplorerApp; do
  catalog="$root/Sources/$target/$target.docc"
  graphdir="$out/graphs-$target"
  archive="$out/archives/$target.doccarchive"
  test -d "$catalog"
  test -s "$out/graphs/$target.symbols.json" || { echo "Missing symbol graph for $target" >&2; exit 1; }
  mkdir -p "$graphdir"
  cp "$out/graphs/$target.symbols.json" "$graphdir/"
  shopt -s nullglob
  for extension_graph in "$out/graphs/$target"@*.symbols.json; do cp "$extension_graph" "$graphdir/"; done
  shopt -u nullglob
  "$docc" convert "$catalog" \
    --additional-symbol-graph-dir "$graphdir" \
    --fallback-display-name "$target" \
    --fallback-bundle-identifier "org.thorfuchs.researchexplorer.$target" \
    --fallback-bundle-version 1 \
    --output-dir "$archive" \
    --warnings-as-errors \
    --experimental-documentation-coverage --coverage-summary-level detailed \
    2>&1 | tee "$out/logs/docc-$target.log"
  test -s "$archive/metadata.json"
  test -s "$archive/documentation-coverage.json"
  echo "PASS archive: $archive"
done
cmp -s Package.resolved "$out/Package.resolved.before" || { echo "Package.resolved drift" >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then
  echo "FAIL: working tree changed during documentation build." >&2
  exit 1
fi
echo "Six DocC archives generated; review coverage reports and documentation navigation."
echo "$out/archives"
