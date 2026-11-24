# Explore the Machine Room

Observe the real server and client without generating artificial telemetry.

## Overview

Choose Server, select the offline source, and explicitly start the local
host. The command deck displays the actual host phase and endpoint.

The KPI rail distinguishes unavailable observations from measured zeros.
Activity Pulse shows the five-minute histogram. Latency and tool charts
show recent retained samples. The Outcome Mix shows reconciled run totals
only when observation is coherent and nonpartial.

Pause Charts freezes the displayed charts but leaves the KPI rail and the
server live. Run or lifecycle changes invalidate the freeze. Select a
five-second interval with the chart or the native Picker and inspect
retained Activity rows; clear the filter before exporting.

Enable Record exchange details, then choose Explore MCP. The five
research stages display real validation outcomes. Choose any recorded
exchange in either chart or the Picker to inspect its measured duration,
SDK message sizes and message count. Disable recording to hide exchange
metadata. A transport response does not itself mean schema validation
succeeded.

The dashboard contains no simulated telemetry, fabricated progress, automatic
listener, or background request generator.
