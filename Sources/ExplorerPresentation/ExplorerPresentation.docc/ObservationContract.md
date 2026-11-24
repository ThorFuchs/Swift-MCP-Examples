# Observation contract

Read chart denominators, run identity and retention correctly.

## Overview

The activity store observes admitted catalogue handlers from any client.
It also retains redacted direct-research and lifecycle events separately.
It does not observe all HTTP requests, connections, pre-handler rejections
or network traffic.

| Value | Meaning |
| --- | --- |
| Active | Currently tracked eligible handler invocations. |
| Terminal | All observed terminal calls, including failures and cancellation. |
| Failed | Tool problems plus failed handler terminal paths. |
| Cancelled | Distinct observed cancelled terminal paths. |
| Median | Retained measured durations within five minutes, at most 512 samples. |
| Activity Pulse | 60 five-second completion buckets, not arrivals. |
| Tool activity | At most 50 recent retained eligible terminal calls. |
| Handler latency | Nonnegative measured durations from that retained sample. |
| Outcome mix | Reconciled observed run totals, absent when partial or inconsistent. |

The projection requires matching controller and snapshot run IDs. Idle
and unmatched observations are unavailable, not measured zero. The last-run
view may keep its observed totals while the rolling window ages. Pause
freezes only charts of the same live run, not the server or live KPI values.

A selected histogram slot is rendered using a wall-clock interval. The Activity
drill-down filters retained terminal events by that run and interval; retention
and clock adjustment can make its row count differ from the histogram.
The app disables export during this specialized interval selection.

Observation loss and arithmetic inconsistency are disclosed. A distribution
must not infer success from incomplete counts.
