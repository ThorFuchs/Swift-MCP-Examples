// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Charts
import ExplorerPresentation

struct RequestActivityChart: View {
    let projection: MachineRoomProjection
    let onInspect: (MachineRoomBucketScope) -> Void
    @State private var selectedSlot: Int64?

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
                if let metrics = projection.metrics,
                   let analytics = MachineRoomAnalytics(projection: projection) {
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
                    Chart {
                        ForEach(metrics.buckets) { bucket in
                            BarMark(
                                x: .value("Bucket midpoint", bucket.date.addingTimeInterval(2.5)),
                                y: .value("Terminal calls", Double(bucket.calls))
                            )
                            .foregroundStyle(ExplorerDesign.Palette.accent.opacity(selectedSlot == nil || selectedSlot == bucket.slot ? 1 : 0.35))
                            .accessibilityLabel(Text(bucket.date, style: .time))
                            .accessibilityValue("\(bucket.calls) terminal calls")
                        }
                        if let selected = analytics.bucket(slot: selectedSlot) {
                            RuleMark(x: .value("Selected bucket", selected.date.addingTimeInterval(2.5)))
                                .foregroundStyle(Color.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .accessibilityHidden(true)
                        }
                    }
                    .chartXSelection(value: dateSelection(analytics))
                    .chartYScale(domain: 0.0...max(4.0, Double(metrics.buckets.map(\.calls).max() ?? 0)))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxisLabel("Calls / 5 s")
                    .frame(height: 220)
                    .accessibilityLabel("Terminal eligible tool calls over five minutes")
                    .accessibilityValue(accessibleSummary(metrics))
                    selectionControls(analytics)
                    .onChange(of: analytics.buckets.map(\.slot)) {
                        if analytics.bucket(slot: selectedSlot) == nil { selectedSlot = nil }
                    }
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

    private func dateSelection(_ analytics: MachineRoomAnalytics) -> Binding<Date?> {
        Binding(
            get: { analytics.bucket(slot: selectedSlot)?.date.addingTimeInterval(2.5) },
            set: { date in selectedSlot = date.flatMap { analytics.bucket(containing: $0)?.slot } }
        )
    }

    private func slotSelection(_ analytics: MachineRoomAnalytics) -> Binding<Int64?> {
        Binding(
            get: { analytics.bucket(slot: selectedSlot)?.slot },
            set: { slot in selectedSlot = analytics.bucket(slot: slot)?.slot }
        )
    }

    private func selectionControls(_ analytics: MachineRoomAnalytics) -> some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
            Divider()
            Picker("Inspect interval", selection: slotSelection(analytics)) {
                Text("None").tag(nil as Int64?)
                ForEach(analytics.buckets) { bucket in
                    Text("\(bucket.date.formatted(date: .omitted, time: .standard)) · \(bucket.calls) calls")
                        .tag(Optional(bucket.slot))
                }
            }
            .pickerStyle(.menu)
            .help("Select a five-second interval with the keyboard or directly in the chart.")
            if let bucket = analytics.bucket(slot: selectedSlot), let scope = analytics.scope(slot: selectedSlot) {
                Text("\(scope.start.formatted(date: .omitted, time: .standard)) – \(scope.end.formatted(date: .omitted, time: .standard)) · \(bucket.calls) observed terminals")
                    .font(ExplorerDesign.Typography.detail)
                    .monospacedDigit()
                Button("Inspect retained events", systemImage: "list.bullet.rectangle") { onInspect(scope) }
                    .buttonStyle(.glass)
                Text("Activity matches retained terminal events by run and wall-clock time. Clock adjustments or retention can make its count differ from the monotonic histogram.")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
