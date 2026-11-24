// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Charts
import ExplorerPresentation

struct RequestActivityChart: View {
    let projection: MachineRoomProjection

    var body: some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
                Text("Activity Pulse")
                    .font(ExplorerDesign.Typography.section)
                    .accessibilityAddTraits(.isHeader)
                Text("Terminal eligible tool-handler calls · 5-second buckets · last 5 minutes")
                    .font(ExplorerDesign.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let metrics = projection.metrics {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: ExplorerDesign.Space.md) {
                            windowSummary(metrics)
                            Spacer(minLength: ExplorerDesign.Space.xs)
                            Text(projection.scope.rawValue).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
                            windowSummary(metrics)
                            Text(projection.scope.rawValue).foregroundStyle(.secondary)
                        }
                    }
                    .font(ExplorerDesign.Typography.detail)
                    Chart(metrics.buckets) { bucket in
                        BarMark(
                            x: .value("Bucket start", bucket.date),
                            y: .value("Terminal calls", Double(bucket.calls))
                        )
                        .foregroundStyle(ExplorerDesign.Palette.accent)
                        .accessibilityLabel(Text(bucket.date, style: .time))
                        .accessibilityValue("\(bucket.calls) terminal calls")
                    }
                    .chartYScale(domain: 0.0...max(4.0, Double(metrics.buckets.map(\.calls).max() ?? 0)))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxisLabel("Calls / 5 s")
                    .frame(height: 220)
                    .accessibilityLabel("Terminal eligible tool calls over five minutes")
                    .accessibilityValue(accessibleSummary(metrics))
                    if metrics.windowTerminalCount == 0 {
                        Text("No eligible handler completions observed in this window.")
                            .font(ExplorerDesign.Typography.detail)
                            .foregroundStyle(.secondary)
                    }
                    Text("Median: up to 512 retained duration samples within five minutes. This is handler activity, not all HTTP requests or network traffic.")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ContentUnavailableView(
                        "No observation yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("A matching server-run snapshot is required before the chart can display measured values.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 170)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func windowSummary(_ metrics: MachineRoomProjection.Metrics) -> some View {
        Text(metrics.windowTerminalCount.map { "\($0) observed in window" } ?? "Window total unavailable")
            .font(ExplorerDesign.Typography.panel)
            .monospacedDigit()
    }

    private func accessibleSummary(_ metrics: MachineRoomProjection.Metrics) -> String {
        let count = metrics.windowTerminalCount.map { "\($0) observed terminal calls." } ?? "Window total unavailable."
        return "\(projection.scope.rawValue). \(count) \(metrics.isPartial ? "Partial observation." : "Catalogue handlers only.")"
    }
}
