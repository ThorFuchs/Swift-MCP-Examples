// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Charts
import ExplorerPresentation

/// Each panel describes its denominator explicitly. All samples are obtained
/// from the same bounded projection as Activity Pulse; no new observer exists.
struct MachineRoomAnalyticsGrid: View {
    let analytics: MachineRoomAnalytics

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 300), spacing: ExplorerDesign.Space.md, alignment: .top)],
            alignment: .leading,
            spacing: ExplorerDesign.Space.md
        ) {
            latencyPanel
            toolPanel
            outcomePanel
        }
    }

    private var latencyPanel: some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                Text("Handler latency")
                    .font(ExplorerDesign.Typography.panel)
                    .accessibilityAddTraits(.isHeader)
                Text("\(analytics.latency.count) measured durations · \(analytics.recentCount) recent retained terminals")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if analytics.latency.isEmpty {
                    emptyChart("No measured durations yet", symbol: "timer")
                } else {
                    Chart(analytics.latency) { sample in
                        PointMark(
                            x: .value("Terminal time", sample.date),
                            y: .value("Duration (ms)", Double(sample.milliseconds))
                        )
                        .foregroundStyle(ExplorerDesign.Palette.accent)
                        .symbolSize(44)
                        .accessibilityLabel("\(sample.tool.title), \(sample.date.formatted(date: .omitted, time: .standard))")
                        .accessibilityValue("\(sample.milliseconds) milliseconds")
                    }
                    .chartYScale(domain: 0.0...max(1.0, Double(analytics.latency.map(\.milliseconds).max() ?? 0)))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                    .chartYAxisLabel("ms")
                    .frame(height: 175)
                    .accessibilityLabel("Recent handler latency samples, in milliseconds")
                }
                Text("Up to 50 retained terminal calls, not the complete latency history. Missing durations are omitted.")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toolPanel: some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                Text("Tool activity")
                    .font(ExplorerDesign.Typography.panel)
                    .accessibilityAddTraits(.isHeader)
                Text("Recent \(analytics.recentCount) retained terminal calls · maximum 50")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if analytics.recentCount == 0 {
                    emptyChart("No retained terminal calls", symbol: "chart.bar.xaxis")
                } else {
                    Chart(analytics.tools) { row in
                        BarMark(x: .value("Calls", row.count), y: .value("Tool", row.tool.title))
                            .foregroundStyle(ExplorerDesign.Palette.accent)
                            .accessibilityLabel(row.tool.title)
                            .accessibilityValue("\(row.count) retained terminals")
                    }
                    .chartXScale(domain: 0...max(1, analytics.tools.map(\.count).max() ?? 0))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .frame(height: 175)
                    .accessibilityLabel("Tool breakdown in retained terminal sample")
                }
                ForEach(analytics.tools) { row in
                    HStack {
                        Text(row.tool.title).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(row.count)").monospacedDigit()
                    }
                    .font(ExplorerDesign.Typography.detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct Slice: Identifiable {
        let title: String
        let count: UInt64
        let color: Color
        let symbol: String
        var id: String { title }
    }

    private func slices(_ mix: MachineRoomAnalytics.OutcomeMix) -> [Slice] {
        [
            Slice(title: "Succeeded", count: mix.succeeded, color: .green, symbol: "checkmark.circle"),
            Slice(title: "Failed", count: mix.failed, color: .red, symbol: "exclamationmark.triangle"),
            Slice(title: "Cancelled", count: mix.cancelled, color: .orange, symbol: "stop.circle")
        ]
    }

    private var outcomePanel: some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                Text("Outcome mix")
                    .font(ExplorerDesign.Typography.panel)
                    .accessibilityAddTraits(.isHeader)
                Text("Observed run totals · eligible terminal handlers")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let mix = analytics.outcomeMix {
                    let values = slices(mix)
                    if values.contains(where: { $0.count > 0 }) {
                        Chart(values.filter { $0.count > 0 }) { slice in
                            SectorMark(angle: .value("Terminal calls", Double(slice.count)), innerRadius: .ratio(0.65))
                                .foregroundStyle(slice.color)
                                .accessibilityLabel(slice.title)
                                .accessibilityValue("\(slice.count) calls")
                        }
                        .frame(height: 175)
                        .accessibilityLabel("Outcome distribution for the observed run")
                    } else {
                        emptyChart("No terminal calls yet", symbol: "chart.pie")
                    }
                    ForEach(values) { slice in
                        HStack {
                            Label(slice.title, systemImage: slice.symbol)
                            Spacer()
                            Text("\(slice.count)").monospacedDigit()
                        }
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.primary)
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    emptyChart("Distribution unavailable", symbol: "exclamationmark.triangle")
                    Text("Observation is partial or totals do not reconcile. Success is not inferred.")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func emptyChart(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(ExplorerDesign.Typography.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 175)
    }
}
