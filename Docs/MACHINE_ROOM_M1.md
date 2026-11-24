# Machine Room — M1 cockpit

Tracking: [Examples #6](https://github.com/ThorFuchs/Swift-MCP-Examples/issues/6).
Base: Liquid Glass polish `a82c2c51e68c0d90647c91678011b0ccbe99b0b5`.
Scope: native Server workspace only, plus a pure read-only presentation projection
and deterministic tests. Native qualification remains open.

## Contract

- One existing `AppLifetime.activitySnapshot`; no new timer, observer, listener,
  instrumentation, dependency or SDK API.
- The controller's run ID must equal the store snapshot's run ID before any
  metrics are presented. Idle and awaiting-observation are **unavailable**, not
  measured zeros. Source changes and restart cannot label the old snapshot live.
- Starting, live, stopping, last run and failed run are distinct scopes.
  Last-run totals remain visible when matched, while the five-minute window ages.
  A failed run is not proof of a clean join.
- Four adaptive KPI cards: active handlers, all terminal handlers, failed
  handlers (including tool problems), five-minute median. Cancellation count
  and median sample count are labeled separately. Partial observation is explicit.
- Activity Pulse is the existing 60 × 5 s completed-handler histogram, using
  real `RequestBucket` values only. The window sum is checked for overflow;
  an overflow becomes unavailable/partial, never a wrapped or fabricated count.
- The retained recent-call table is scoped to the same run and max 50 entries.
  Neither the chart nor the table measures all HTTP requests, connections,
  client exchanges or network bytes.
- Existing host actions and RE-04 Guided MCP Journey/connection recipes are
  preserved. M1 does not redefine journey recording/lifecycle or add new charts.

## Review on macOS

From a clean checkout on macOS 27 / Swift 6.4:

```bash
swift test --filter MachineRoomProjectionTests
swift build --product ResearchExplorerApp
bash Scripts/qualify-re04-local.sh
swift run ResearchExplorerApp
```

Open Server and check these actual states:

1. Idle: no listener, "Not started", unavailable metrics and no fabricated chart.
2. Explicit Start: starting/awaiting observation; once matching run is ready,
   Live shows measured zeros and no latency sample until a handler finishes.
3. Enable Record exchange details if desired; run Explore MCP. Terminal count
   reflects actual completed handlers, not discover/tools/list protocol requests.
4. Stop: Last run only after the server reports stopped. Restart: previous
   metrics hidden until the new run ID matches. Switch source after a joined
   stop: no old-run KPI or recent-call table in the new controller.
5. Review native controls, labels, chart axes and layout in wide and compact
   windows, light/dark, high contrast and VoiceOver. Capture actual screenshots
   separately; the layer harness does not reproduce all Window Server materials.

M2 adds measured latency/recent-tool charts, selection and accessibility
interaction; M3 adds the real client exchange lane; M4 addresses native visual
QA and the Activity screenshot height anomaly. No GitHub Actions, merge or tag
is needed for M1 local verification.
