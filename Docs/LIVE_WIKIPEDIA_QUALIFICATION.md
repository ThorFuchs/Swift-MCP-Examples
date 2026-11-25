# Live Wikipedia qualification — Track C

Base M4: `0836c6bace6994d77154ed4cd52b890db564f489`.
Scope: J2 live research plus live-source guided HTTP MCP. Test-only; no
production provider, transport, dependency, UI or CI changes.

## Existing production path

The default source is fictional Riverglass. While the local host is stopped,
choose **Server → Research source → Wikipedia English**; then select Research
and explicitly search. The application uses `WikipediaProvider` through
`ExplorerService`. The built-in guided MCP client uses the public SDK,
the real app-owned loopback HTTP host and the selected live service.

MediaWiki REST v1 uses search/page and page/{encoded returned key}/with_html
on the exact HTTPS origin https://en.wikipedia.org. The HTML normalizer
currently admits profile **2.8.0** with strict revision identity. Do not weaken
that contract if upstream behavior changes. See [LIVE_CONTRACT.md](LIVE_CONTRACT.md)
and [the official REST reference](https://www.mediawiki.org/wiki/API:REST_API/Reference).

## Explicit native test

```bash
bash Scripts/qualify-live-wikipedia-local.sh
```

This runs two independent opt-in Swift Testing cases using the *normal app
source loader* and public network. Default test runs skip them. The test
host uses 127.0.0.1 and an ephemeral port; it never exposes a public listener.
One direct reader search+outline and one guided client search+outline
normally require four upstream REST requests total (plus only the existing
bounded retry/redirect policy). Sections/references use cached snapshots.
No further live calls are added by the test harness.

The query is Noether's theorem. The direct reader explicitly picks the exact
returned title. The guided client retains its existing search/first-candidate
behavior. Each independently checks the admitted source, positive page and
revision IDs, immutable permalink, provenance, section text, and references.
A later upstream revision is legal between the independent runs; within each
run, identities must agree. Empty reference metadata and actual missing
reference metadata remain distinct. A missing-reference failure is not a
successful end-to-end reference retrieval.

The direct route must not start a listener or count MCP handler calls.
The guided route must record five validated milestones, at least six
actual exchanges (pagination may increase that number), four terminal
handlers, no failures/partial observation, and joined app cleanup.
A transport response alone does not qualify the journey.

The script saves commit/toolchain, lock identity, both raw test logs, a
stage ledger and cleanup receipts under Desktop/ResearchExplorer-LiveWikipedia-*.
It rejects skipped/empty tests and missing pass markers, runs both routes
even if one fails, and rejects lock/source drift.

## Manual UI follow-up

1. Launch `swift run ResearchExplorerApp`. Confirm Offline demo is the default.
2. Server → Research source → Wikipedia English while stopped.
3. Research → enter Noether's theorem → choose article → select a section.
   Inspect the live source badge, revision permalink, license, text, and
   citation metadata; no fictional source substitution.
4. Server → Start server → Record exchange details → Explore MCP.
   Inspect actual live research results, six or more exchanges and four
   handler terminals in the Machine Room, then Stop server.
5. Optionally switch back to Offline demo while stopped. Confirm clean quit.

## Evidence status

Repository inspection confirms the live path exists. The external HTTP
attempt from the assistant execution environment failed at DNS resolution;
a separate web fetch did not retrieve the raw REST response. This does not
establish a failure of Wikipedia or of the app. No live-native result or
visual UI evidence is claimed until this test runs on the native host.
The currently accepted HTML profile and the live response budget remain
unchanged. If an actual run fails, record its stage and owned problem code
before investigating the upstream response format or transport.

## R1–R3 qualification extension

The original direct and guided tests qualified commit 1f6657c9 on the Mac Studio. The new script additionally runs interactiveLiveResearchCollectsEvidence: explicitly select Via MCP, search/open/read/references, capture the exact section, search one related title through the same route, switch Direct, and verify the retained dossier and both file formats. The additional test normally uses three upstream requests (search, outline, related-title search). The prior proof does not qualify the changed code/schema. All three tests must pass at the new SHA; no automatic retries beyond the existing provider contract.

## R4b and R5

The local live script now runs a fifth independent case, `directReaderReadsHistoricalRevision`. It explicitly previews one returned history row, reads its independently chosen section, verifies the original pin remains unchanged, adopts the exact revision and reloads it without substituting latest. Historical envelope or HTML-profile drift is a failure, not a reason to loosen admission. R5 is separately qualified with `MCPHTTPJourneyTests/knowledgeResourcesPromptsAndSkillOverHTTP` using the offline provider and a real HTTP listener. Previous native receipts do not qualify these changes.
