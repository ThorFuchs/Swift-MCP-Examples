# Track C — Developer experience, Research Explorer & showcase

**Status:** proposed editorial direction; documentation-only starting point.
**Tracking:** [Examples issue #2](https://github.com/ThorFuchs/Swift-MCP-Examples/issues/2).
**Product contract:** [Research Explorer 1.0 specification](RELEASE_1_0_SPEC.md).

Track C is the developer-facing and design-oriented workstream.
Track A owns Core release qualification; Track B owns HTTP release qualification.
Track C changes **neither** package's production implementation, security contracts,
timeouts, dependency graph, release tags, nor Go/No-Go decision.

## One story, three repositories

| Repository | Promise we can demonstrate | Primary entry point |
| --- | --- | --- |
| [Swift-MCP-Server](https://github.com/ThorFuchs/Swift-MCP-Server) | Build a typed MCP server and client with explicit stdio lifecycle | Server and client Quickstarts (Track A coordinates public API) |
| [Swift-MCP-Server-HTTP](https://github.com/ThorFuchs/Swift-MCP-Server-HTTP) | Add Streamable HTTP and client/server authorization with bounded lifecycle | HTTP client/server setup and security notes (Track B coordinates) |
| [Swift-MCP-Examples](https://github.com/ThorFuchs/Swift-MCP-Examples) | See real SDK calls inside a useful, offline-first research experience | Research Explorer app, CLI, tested native captures |

Use clear technical descriptions rather than broad claims like “production ready,”
“certified,” “full MCP compliance,” “official Apple SDK,” or “Wikipedia-verified citations.”
The Apple SwiftNIO contribution can be linked factually to the merged upstream PR;
it does not imply Apple endorsement.

## Editorial direction

**Quiet, editorial, native.** Treat the article as the hero and the developer
inspection as a transparent second layer. Maintain real SwiftUI materials
rather than redrawing an imitation OS frame. Prefer generous space, readable
source/provenance details, accurate screenshots, and short runnable code
over marketing banners, decorative badges, or a logo wall.

The public hierarchy should read:

1. **Use it** — launch offline Research Explorer and enjoy a coherent research journey.
2. **Understand it** — inspect real HTTP and stdio MCP exchanges with validated tool results.
3. **Build with it** — follow the public SDK APIs and reproducible examples.
4. **Trust the boundaries** — inspect provenance, privacy, timeouts, cancellation, and known release limits.

Aesthetics must not hide critical provenance or imply unsupported functionality.

## Work sequence

### C-00 — Developer-facing entry point (this docs-only PR)

Replace the extract-style README front matter with a readable app + SDK
showcase. Link the actual existing RE-03 screenshot and **its capture caveats**.
Keep exact platform requirements, runnable commands, four tool names, and
pre-release limits. No application or SDK source changes.

### C-01 — Consolidate the actual implementation

Standalone Examples `main` currently starts from Core snapshot
`453eb632e0db8812a7bae7172e934d11d8a10a8a` (RE-03).
Later Core commit `e74557366c04a671973403f6911cb60fc02a88e3`
adds RE-04 work (opt-in Exchange Inspector, connection recipes, lifecycle
tests, app presentation) in 11 files under `Examples/ResearchExplorer/`.
**Do not claim RE-04 present in standalone Examples until a separate
source-inventory/migration PR has been reviewed, tested, and merged.**

Keep RE-04 developer metadata opt-in, ephemeral and redacted, distinguish
Activity handler counts from arbitrary HTTP activity, and test both actual
transport journeys. Do not copy the Core root manifest, change public SDK
APIs, or diverge two competing active implementation trees.

### C-02 — Qualify standalone native Examples

The last Examples `main` workflow
[45044360991](https://github.com/ThorFuchs/Swift-MCP-Examples/actions/runs/45044360991)
passed its Linux manifest job; its macOS job was **skipped**.
Enable a correctly registered macOS 27 runner for this repository or
provide independent exact-SHA native receipts, then exercise:

- `Scripts/test.sh` and `swift build --product ResearchExplorerApp`
- Real stdio client/server and in-app loopback HTTP client/server journeys
- Offline startup with no listener or network
- Swift Concurrency cancellation/join and repeated clean shutdown
- Real app screenshots, keyboard/VoiceOver, light/dark and attribution

Core [extraction gate #50](https://github.com/ThorFuchs/Swift-MCP-Server/issues/50)
must remain independent. Do not remove Core's in-tree version before the
standalone verification is established.

### C-03 — RE-05 app packaging and visible polish

Address [RE-05 #37](https://github.com/ThorFuchs/Swift-MCP-Server/issues/37):
real Help, first-run guidance, search/reading/evidence refinements, keyboard
accessibility, actual rendered screenshots with their limitations, correct
license notices, a reproducible .app packaging recipe and exact commit evidence.
Do not start a public listener by default or silently refresh article revisions.

### C-04 — Coordinate the three SDK entry points

After A/B confirm exact APIs and dependency versions, prepare narrow docs-only
PRs in Core/HTTP for coherent titles, Server/Client quickstarts, nav links and
version/support statements. Each must use **real source/examples/tests** as
evidence. Do not modify Core/HTTP `main` or release metadata from Track C
without their own focused PR and review.

### C-05 — Developer launch, after approved tags

Publish a short, accurate technical walkthrough, inspectable diagram of
Server ↔ stdio/HTTP ↔ Client ↔ Research Explorer, changelog/releases,
a first issue template and a community introduction. Keep the app version
separate from the SDK SemVer versions. No press or “1.0 now available” claim
until the actual packages have approved immutable tags and consumer tests.

## Definition of done for the Track C foundation

- [ ] Developer landing tells the difference between *direct* and *real MCP*.
- [ ] Screenshot has traceable origin and capture limitations.
- [ ] Standalone app's exact source revision and CI truth are transparent.
- [ ] RE-04 migration is a separately tracked, tested slice.
- [ ] A/B own their technical release decision; Track C introduces no bypass.
- [ ] No unsupported feature, trust, performance or third-party endorsement claim.
