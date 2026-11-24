# Machine Room — M3 visual MCP journey

Tracking: [Examples #6](https://github.com/ThorFuchs/Swift-MCP-Examples/issues/6).
M2 base: `734217ff8befd58809ead1b616754fbf6a77d68c`.

## What is rendered

- Client/server overview, explicit Explore/Cancel and opt-in controls; five
  planned milestones derived only from actual controller observations.
- Preparation reports protocol/catalogue checks, not an outputSchema check.
  Tool milestones report schema and identity checks only when the real step
  succeeded and its validated flag is true. Repeated observations are not
  silently lost. Unobserved stages are never inferred to be in flight.
- The bounded inspected exchanges are shown separately: SDK exchange duration
  and outgoing request-body/incoming delivered-message sizes, using native
  Swift Charts. These are not TCP, HTTP/TLS wire bytes, server handler
  latencies or a reconstructed waterfall. An ordinary successful journey
  has six exchanges; pagination may produce more.
- Shared categorical chart selection, native Picker, exact record details
  (including delivered messages and transport outcome), and retained record
  list. A response is not synonymous with successful protocol validation.
- The projection only accepts the run ID of the server owning the journey.
  Presentation ID changes for a new journey, clearing prior chart selection.
  A previous in-flight journey can still be cancelled; its old results are
  not shown as belonging to the new server run.
- Opt-out hides previously retained records; it is not a deletion action.
  New journey/clear behavior remains owned by the existing controller.
  No new recorder, timer, observer, storage, export, network action or SDK
  API; no transport or lifecycle implementation change.

## Local qualification

```bash
swift test --filter MachineRoomJourneyProjectionTests
swift build --product ResearchExplorerApp
bash Scripts/qualify-re04-local.sh
swift run ResearchExplorerApp
```

Manual check: Start server, Explore MCP without inspection, verify five
milestones and no exchange metadata. Enable recording and repeat. Select a
record independently through each chart and the Picker; exact values must
agree with the retained record list. Check failure/cancel, source change,
stop/restart and new-journey selection reset. Turn off recording after an
inspected run; exchange panels disappear. Confirm no fake progress stages,
privacy/retention boundary, wide and compact windows, light/dark and VoiceOver.

Portable projection tests are not a native UI qualification. M4 will
capture the real running window, address the Activity layout capture anomaly,
and review accessibility and final visual polish. GitHub Actions, merges
and release tags remain out of scope.
