# R1 — Unified Research Journey

Direct and Via MCP are explicit execution routes, independent of Offline demo / Wikipedia English. The reader uses its existing serial controller. Switching routes joins the previous worker, clears the article/candidate state, and retains the query without automatically searching. MCP preparation occurs on the first explicit operation. Only a running, matching loopback server run is admitted. Stop/Restart invalidates and joins MCP reader work; reconnect explicitly or select Direct. No automatic fallback. Selecting a different source explicitly resets the route to Direct on successful handoff.

The existing server handler observer counts actual MCP calls; the direct reader recorder is not invoked for the MCP adapter. Guided Explore MCP remains independent; its opt-in exchange inspector is not a capture of arbitrary reader calls. Offline edit publication is deliberately unavailable via MCP (read-only catalogue).

Native acceptance: swift test --filter JourneyLifecycleTests; build ResearchExplorerApp; verify Direct vs Via MCP for both sources, mode switches during a query, stop/restart, failed route, no double counting, explicit source change and joined quit. No native proof yet.
