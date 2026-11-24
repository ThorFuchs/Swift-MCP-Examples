# R4a — Wikipedia Time Machine: earlier revision metadata

Starting point: R1–R3 `124fcb573784914fab3194f68e11c57f3117d021`. User reported the app runs well; no new native receipt was supplied. R4a is a focused first slice, not full native historical reading.

- Direct-mode Wikipedia reader can explicitly request one earlier history segment (up to 20 rows) relative to the selected pin, and replace it with the next older segment. No automatic pagination. Candidate and cached pin are admitted by the existing service and provider; expired candidate/cache is an explicit problem.
- One new exact-origin REST route: `page/{encoded candidate key}/history?older_than={positive decimal revision ID}`. Construct all URLs locally; ignore returned pagination URLs, use the last admitted row ID. Existing retry, concurrency, cancellation and body budgets remain. Do not admit historical HTML, raw compare or arbitrary URLs.
- Retain IDs, UTC timestamps, size, delta and minor flag only. No editor names/IPs or edit comments. The response is title-scoped and does not prove the page ID of each historical row. External links are constructed from positive revision IDs and open Wikipedia only on user action. The pinned native article and collected evidence remain unchanged.
- History uses the existing ResearchController's single worker; no hidden Direct fallback in Via MCP. The read-only four-tool MCP schema stays unchanged. Activity records a fixed local operation label, not historical content or usernames.
- Live normalized part IDs are revision-local ordinals. Disable implicit section alignment across live revisions in the existing latest-revision comparison. Keep the offline stable-ID demonstration; on live adoption require a new section selection. Wikipedia's own comparison is available as an explicit link.

Native historical HTML admission is R4b: capture/verify the distinct revision response shape, exact page/revision ID, historical content model, license and HTML identity before enabling native reading. Do not substitute current license or content metadata on missing historical fields. No change to HTML profile or cache expiry.

Reference: https://www.mediawiki.org/wiki/API:REST_API/Reference (Get page history; Get revision information with HTML; Compare revisions).

Native gates: RevisionHistoryTests, LiveProviderTests, full RE04 regression and a new opt-in live history probe. Native rendering, live API response and warning-free DocC are not yet qualified.

## Native live test

The existing live qualification script now runs a fourth independent case, earlierWikipediaHistoryPreservesPin. It requires the real Noether article, reads one section, requests earlier history, optionally loads one older page, and checks unchanged pin/passage/reference metadata, page separation, local-only observation and joined app cleanup. Four cases must run; historical metadata is not a native historical HTML proof.
