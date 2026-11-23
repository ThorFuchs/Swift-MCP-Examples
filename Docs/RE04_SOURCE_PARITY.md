# RE-04 source synchronization — exact provenance and pending native qualification

**Track:** C-01 · [Examples issue #4](https://github.com/ThorFuchs/Swift-MCP-Examples/issues/4)
**State:** imported source; **not yet natively compiled or tested in this checkout**.
**Why no GitHub CI:** Actions are intentionally deferred during the temporary GitHub billing/payment interruption on 2026-11-23.

## Immutable source references

- Source: `ThorFuchs/Swift-MCP-Server` at exact commit `e74557366c04a671973403f6911cb60fc02a88e3` (Core RE-04).
- Destination baseline: `ThorFuchs/Swift-MCP-Examples` at `25928bc262dae7a90897c9390eb94475d3733247` (the standalone RE-03 extraction).
- This C-01 branch adds exactly the RE-04 source/test delta, plus the source-owned walkthrough and this evidence note. The Core RE-04 README diff is **not** copied: Track C's new showcase README is handled in its independent [docs PR #3](https://github.com/ThorFuchs/Swift-MCP-Examples/pull/3).

## Source / test parity inventory

The recursive Git tree comparison on the exact source and destination commits found **only the following nine differences in Swift source and test files**. Every other Swift source/test blob matched bit-for-bit.

| Relative package path | RE-04 operation |
| --- | --- |
| `Sources/ExplorerPresentation/Server/ConnectionRecipe.swift` | New |
| `Sources/ExplorerPresentation/Server/ExchangeInspector.swift` | New |
| `Sources/ExplorerPresentation/Server/MCPJourneyController.swift` | Update |
| `Sources/ResearchExplorerApp/Activity/ActivityView.swift` | Update |
| `Sources/ResearchExplorerApp/App/AppLifetime.swift` | Update |
| `Sources/ResearchExplorerApp/Server/ServerView.swift` | Update |
| `Tests/ExplorerAppTests/JourneyLifecycleTests.swift` | New |
| `Tests/ExplorerPresentationTests/InspectorAndRecipeTests.swift` | New |
| `Tests/ExplorerPresentationTests/MCPHTTPJourneyTests.swift` | Update |

Also imported `Docs/MCP_WALKTHROUGH.md` unchanged from the same Core commit.

**Acceptance for source parity:** independently recheck each of the nine destination blob SHA-1s against Core's exact source path and confirm that no unrelated `Sources/` or `Tests/` path changed. Git object hashes verify bytes, **not** functional correctness or a native build.

## Intended RE-04 behavior (requires native verification)

- The guided *Explore MCP* journey uses the public SDK HTTP client on an explicitly running local loopback host; local research is not counted as a wire exchange.
- The opt-in exchange inspector wraps the real SDK client transport, is metadata-only, ephemeral and bounded to 32 retained records. No bodies, headers, URLs, request arguments, tokens or arbitrary error descriptions are stored.
- Connection recipes use exact MCP 2026-07-28 method/metadata/headers. Their request model must be tested against a real local HTTP server.
- Lifecycle tests must demonstrate cancellation/join, a clean stop/restart and source switching without residual exchange records.

## Native test handoff (independent of GitHub Actions)

A separate **RE-03 baseline** is now available: the earlier [C-00 PR #3 run #45249983754](https://github.com/ThorFuchs/Swift-MCP-Examples/actions/runs/45249983754) completed native macOS 27 `Scripts/test.sh` and the app build successfully on the Mac Studio. Its separate hosted manifest job failed without executing steps. This does **not** qualify the newly synchronized RE-04 code and was not triggered by this branch.

Run from a clean clone of this exact branch on **macOS 27, Xcode 27.2, Swift 6.4.2**. First record `git rev-parse HEAD`, `git status --porcelain`, `swift --version` and the resolved source/fixture dependency graph. Then run the checked-in local qualification script (toolchain, source SHA, logs, nonempty focused suite receipts, unchanged dependency lock):

```bash
bash Scripts/qualify-re04-local.sh
```

Alternatively execute the three main commands manually:

```bash
Scripts/test.sh
swift build --product ResearchExplorerApp
swift run research-explorer --mcp-client
```

Capture actual nonempty execution and results of `InspectorAndRecipeTests`,
`JourneyLifecycleTests`, and `MCPHTTPJourneyTests`; confirm the real
Server → Explore MCP lifecycle in the GUI, disabled-on-startup network/listener,
shutdown/restart, and redaction. Repeat under optimized configuration if needed
for dependent SDK validation. Preserve exact commit/toolchain and raw logs.

The standalone [Examples main Actions run #45044360991](https://github.com/ThorFuchs/Swift-MCP-Examples/actions/runs/45044360991)
passed a Linux **manifest-only** job; its macOS job was skipped. It is not
native qualification. Do not trigger GitHub Actions from this branch during the billing interruption. Run a macOS job **only after the billing issue is resolved**
and an appropriate Examples runner is configured.

## Isolation and release policy

- No changes to `Package.swift`, `Package.resolved`, Core/HTTP sources, CI workflow or main.
- No new public API in the SDK, no dependency upgrades, no artificial events,
  no security changes, no new listener/network activation at startup.
- Do **not** merge this unverified integration or remove Core's older copy
  until the independent [Core extraction gate #50](https://github.com/ThorFuchs/Swift-MCP-Server/issues/50)
  is satisfied. No 1.0 tag or release is authorized by this branch.
