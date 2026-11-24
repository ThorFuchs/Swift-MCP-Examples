# Unified research and evidence collection

Follow a question through a deliberately chosen research route and keep its evidence.

## Overview

The source selector chooses fictional Riverglass or English Wikipedia. The Research route menu independently selects Direct or Via MCP. Via MCP requires an explicitly started local host; the first user operation prepares the SDK catalogue. Route changes join previous work and keep the query, not the open article. Stop or restart invalidates the old MCP route; reconnect explicitly. Server metrics observe actual catalogue handlers, not duplicated direct events. The guided journey's opt-in exchange inspector is separate from interactive reader requests.

Select a live section to inspect Related Knowledge: a bounded sample of supported internal article titles from that section's existing HTML. Choosing a title initiates a search, not an automatic fetch of the linked URL. No crawl, graph store, external citation fetch or automatic target resolution occurs.

Choose Collect section to retain the displayed text, revision, source license, reference metadata or its typed absence, and the execution route. The bounded collection survives source/mode changes and snapshot-cache expiry but is not persistent across quit. Personal notes remain separate and are never submitted to MCP or Activity. Export Markdown or JSON explicitly; inspect attribution and truncation. See the repository's R1–R3 runbooks and opt-in live smoke test.

## Wikipedia Time Machine

In Direct mode, open a live article and choose Load earlier revisions in the Revision panel. One bounded page of at most 20 earlier revisions is returned. Load next older page replaces it; Return to pinned revision history restores the initial anchor. The displayed article, section, citation evidence and collected dossier remain unchanged. History stores revision IDs, timestamps and byte-size metadata, not editor names or comments. Open revision and Compare with pin open the upstream Wikipedia page in your browser. This is title-scoped history, not native historical content admission. Via MCP never silently switches to Direct. Native historical reading is a separate future contract.
