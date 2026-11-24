# R4a — Wikipedia revision timeline

Scope: the first native Time Machine slice, based on R1–R3 at `124fcb573784914fab3194f68e11c57f3117d021`.

## Contract

- Explicit Direct-only history for the selected English Wikipedia candidate. The existing reader driver owns cancellation, supersession and joins. The pinned outline, passage, references and collection are unchanged.
- REST GET /page/{encoded-returned-key}/history with an optional single numeric older_than cursor, not arbitrary response URLs. Maximum 20 rows, one retained segment; older replaces the previous segment. Reopen/research explicitly if candidate admission expires.
- Existing service/provider two-operation permits, 15-second deadline, two-attempt policy and 4 MiB delivery cap still apply. History requests reject redirects to a different exact URL; older search/outline requests cannot redirect to the newly admitted history route.
- Admit positive Int64 revision IDs, finite ISO dates, unique rows, descending timestamps, nonnegative revision size and optional delta. Ignore editor/user and comment fields. Do not claim that title-addressed history proves page identity.
- UI shows revision date, ID, revision size and delta, minor-edit flag, pinned revision when present and a constructed HTTPS oldid permalink. No historical text is fetched or substituted. The only outbound operation is explicit history loading.
- History errors are separate from reading/reference errors. No automatic fallback from Via MCP. The four MCP tools and their schemas remain unchanged. History is a direct Activity event, not an MCP handler.

## Next slice (R4b)

Qualify actual revision/{id}/with_html responses on the native host. Their revision envelope differs from page/with_html; require exact revision/page identity, supported content model, HTML profile and honest license provenance before normalizing. Historical sections must be selected independently; ordinal section IDs do not establish correspondence across live revisions. The full native old-revision reader and compare remain open. R5 MCP Resources follows after that admission contract is reviewed.

Reference: https://www.mediawiki.org/wiki/API:REST_API/Reference#History
