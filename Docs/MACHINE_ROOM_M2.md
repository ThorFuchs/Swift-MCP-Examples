# Machine Room — M2 advanced Swift Charts

Tracking: [Examples #6](https://github.com/ThorFuchs/Swift-MCP-Examples/issues/6).
Base M1: `79f7f0d8d77742b539393fea3e38396804a6a1b4`.

## Data contract

- Existing M1 run-scoped projection remains the single source for the UI.
- Latency: actual nonnegative duration measurements from up to 50 retained
  terminal handler events. Missing durations never turn into zeros.
- Tool breakdown: the same recent retained terminal sample, four known tools
  plus Other if present. It does not represent all calls in a server run.
- Outcome mix: reconciled observed run totals only. Partial, overflowed or
  inconsistent counts suppress the entire distribution instead of manufacturing
  successful calls. No sectors for zero counts; the legend gives exact counts.
- Chart Pause freezes a bounded projection for the same live run. KPI values
  above remain live. Stop, failed/starting state, or run-ID change drops the
  pause; historical data is never substituted for a new run.
- Activity Pulse selection is by stable bucket slot, with Swift Charts
  `chartXSelection` and a keyboard-accessible native Picker. The selected
  interval opens Activity with an explicit run-scoped wall-clock filter.
  Clock adjustments, rolling-window alignment and event retention can make the
  retained rows differ from the monotonic bucket count; this is disclosed.
- The Activity drill-down is presentation-only. Existing filters also apply;
  clear the interval to restore the regular log. Export is disabled during
  interval drill-down to avoid exporting a broader dataset than displayed.
  No changes to the redacted export schema or writer.
- No new tasks, pollers, capture buffers, public listeners, SDK changes,
  dependencies, or GitHub Actions.

## Local qualification

```bash
swift test --filter MachineRoomProjectionTests
swift test --filter MachineRoomAnalyticsTests
swift build --product ResearchExplorerApp
bash Scripts/qualify-re04-local.sh
swift run ResearchExplorerApp
```

Manual acceptance on macOS 27:

1. Idle: unavailable until a matching run is observed. Start locally, run
   Explore MCP repeatedly, and compare the charts with actual retained events.
2. Latency samples and tool breakdown use their own labeled denominator.
   Outcomes are exact observed run counts, not the recent sample.
3. Select a Pulse interval using the chart and independently the Picker;
   inspect retained events, clear filter, and verify normal export returns.
4. Pause the charts; run Explore MCP again. KPI values must advance while
   charts remain unchanged. Resume; stop and restart invalidate the freeze.
5. Compact/wide, light/dark, keyboard and VoiceOver, Increase Contrast and
   Reduce Motion. Confirm no phantom network activity, no misleading partial
   distribution, no clipped chart labels or inaccessible selection.
6. Full RE-04 journeys, cancellation and source switching are still required.
   The existing anomalous Activity screenshot height belongs to M4 review.

Native UI and accessibility verification are pending. M3 adds the separate
client-side exchange visualization.
