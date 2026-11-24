# Machine Room — M4 signature polish and documentation

Base: M3 `2ef86477b951bfbf356c18aa2b2e232bbfa601ac`.
Track C: [Examples #6](https://github.com/ThorFuchs/Swift-MCP-Examples/issues/6).
Status: source implementation; native acceptance pending.

## Motion system

- Metric values: numeric text transitions, actual values preserved.
- Status and milestone symbols: short replacement transitions, actual outcomes.
- Charts: count/sample/record changes and synchronized selection, not the
  continuously re-anchored wall clock or fabricated traffic.
- Pause/resume: scoped control text transition. No lifecycle-wide animation.
- Four design-token roles with 0.16–0.22 s nominal durations and nil under
  Reduce Motion. No new timers, tasks, repeated pulse or transport operations.
- `ExplorerMotionTests` checks the policy for every motion role.

## Visual review

The fixed viewport capture test uses NSHostingView sizingOptions = [] and
renders the content view instead of the window-frame superview. It fails
on size mismatch. This addresses the suspected capture geometry cause;
it does not prove the previous Activity problem was capture-only.

Five new scenes (11–15) start a real offline loopback host on an ephemeral
port and explicitly run the public SDK guided journey. Require a completed
journey, six exchanges and four terminal handlers before capture. App quit
is checked on success and error paths; no new production startup behavior.
Existing snapshots remain historical artifacts.

## DocC

All six SwiftPM targets have target-local catalogs. The landing pages and
articles document research identity, provider, SDK adapters, CLI, app,
ownership, observability, interaction and accessibility. Inline documentation
covers the central domain types, adapters, projections, owner boundaries
and new motion/UI APIs. Documentation coverage across all internal/public
symbols is measured by the native build; do not assert 100% or warning-free
archives until measured and reviewed.

```bash
swift build --product ResearchExplorerApp
swift test --filter 'MachineRoom(Projection|Analytics|JourneyProjection)Tests'
swift test --filter ExplorerMotionTests
bash Scripts/qualify-re04-local.sh
bash Scripts/snapshot-design-local.sh
bash Scripts/build-docc-local.sh
```

The DocC script uses compiler-emitted symbol graphs and the native DocC CLI
without adding a SwiftPM plugin dependency. It builds all six archives with
warnings as errors and saves coverage reports. No publication is authorized.

## Final native gate

- Real 1440/900/820-point windows, light/dark, actual live Glass/chrome.
- No clipped chart/control or Activity layout; compare actual window height
  with the recorded fixed-size layer captures.
- Repeated real Explore MCP, freeze/resume, selection, cancel and restart.
- VoiceOver, keyboard, Increase Contrast, Reduce Transparency and Reduce Motion.
- Motion must not suggest work when no observation changes; no leaked
  opt-in exchange metadata on source/run change.
- Native tests, exact source SHA, 15 captures and six DocC archives/coverage.
- No release claim, merge, tag or GitHub Actions by M4.
