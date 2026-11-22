# Research Explorer extraction and validation

- Original: https://github.com/ThorFuchs/Swift-MCP-Server/tree/453eb632e0db8812a7bae7172e934d11d8a10a8a/Examples/ResearchExplorer
- Pinned source commit: `453eb632e0db8812a7bae7172e934d11d8a10a8a`
- Destination: `ThorFuchs/Swift-MCP-Examples` package root.
- Preserve source modules, tests, fixtures, notices, docs and all 8 screenshots.
- Update only standalone package name, root-relative commands and dedicated CI. No SDK public API changes.

## Acceptance gates

1. Run `Scripts/test.sh` and `swift build --product ResearchExplorerApp` on macOS 27 / Swift 6.4.2.
2. Verify real stdio client/subprocess journey and HTTP loopback client/server journey, cancellation and joins.
3. Verify exact-snapshot file inventory including 8 original PNGs and third-party notices.
4. Confirm successful external Core and HTTP dependency resolution; record graph from `Package.resolved`.
5. Migrate Core references and remove its old example + CI stage only in a separate, gated PR **after** this extraction passes.
6. Replace branch-based SwiftPM dependencies with compatible versioned refs before a stable app release.

**No new test run is claimed by this migration commit.**
