// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ExplorerPresentation

/// The cockpit consumes the same snapshot as the Activity workspace. It does
/// not fetch, poll, start a server, or manufacture a metric.
struct MachineRoomOverview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let projection: MachineRoomProjection
    /// Opens the retained wall-clock interval in Activity without mutating the store.
    let onInspect: (MachineRoomBucketScope) -> Void
    @State private var pausedProjection: MachineRoomProjection?

    private var chartsPaused: Bool {
        projection.scope == .live && projection.metrics != nil
            && pausedProjection?.scope == .live && pausedProjection?.runID == projection.runID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Server observation")
                    .font(ExplorerDesign.Typography.section)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: ExplorerDesign.Space.xs)
                ExplorerPill(
                    title: projection.scope.rawValue,
                    symbol: projection.scope == .live ? "waveform.path" : "clock",
                    tone: projection.scope == .live ? .accent : .neutral
                )
            }
            Text(scopeDescription)
                .font(ExplorerDesign.Typography.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 174), spacing: ExplorerDesign.Space.sm)],
                spacing: ExplorerDesign.Space.sm
            ) {
                ExplorerMetricTile(
                    title: "Active tool handlers",
                    value: projection.metrics.map { String($0.active) } ?? "Unavailable",
                    symbol: "arrow.up.right"
                )
                ExplorerMetricTile(
                    title: "Terminal calls",
                    value: projection.metrics.map { String($0.terminal) } ?? "Unavailable",
                    symbol: "checkmark.circle"
                )
                ExplorerMetricTile(
                    title: "Failed calls",
                    value: projection.metrics.map { String($0.failed) } ?? "Unavailable",
                    symbol: "exclamationmark.triangle"
                )
                ExplorerMetricTile(
                    title: "Median · 5 min",
                    value: medianLabel,
                    symbol: "clock"
                )
            }
            if let metrics = projection.metrics {
                if metrics.isPartial {
                    Label("Partial observation — these counts may be incomplete.", systemImage: "exclamationmark.triangle.fill")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.primary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ExplorerDesign.Space.md) {
                        Label("Cancelled: \(metrics.cancelled)", systemImage: "stop.circle")
                        Label("\(metrics.durationSampleCount) duration samples", systemImage: "timer")
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
                        Label("Cancelled: \(metrics.cancelled)", systemImage: "stop.circle")
                        Label("\(metrics.durationSampleCount) duration samples", systemImage: "timer")
                    }
                }
                .font(ExplorerDesign.Typography.detail)
                .foregroundStyle(.secondary)
            }
            Text("Terminal includes failures and cancellation. Failed includes tool problems. Only eligible catalogue handlers are counted.")
                .font(ExplorerDesign.Typography.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
                HStack {
                    Text("Analytics")
                        .font(ExplorerDesign.Typography.section)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: ExplorerDesign.Space.xs)
                    if projection.scope == .live, projection.metrics != nil {
                        Button(chartsPaused ? "Resume charts" : "Pause charts", systemImage: chartsPaused ? "play.fill" : "pause.fill") {
                            pausedProjection = chartsPaused ? nil : projection
                        }
                        .buttonStyle(.glass)
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .animation(ExplorerDesign.Motion.animation(.selection, reduceMotion: reduceMotion), value: chartsPaused)
                        .help("Freeze only the charts; live KPIs and the server continue unchanged.")
                    }
                }
                if chartsPaused {
                    Label("Charts paused · KPI values above remain live.", systemImage: "pause.circle")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                }
                let chartProjection = MachineRoomAnalytics.chartProjection(current: projection, paused: pausedProjection)
                RequestActivityChart(projection: chartProjection, onInspect: onInspect)
                if let analytics = MachineRoomAnalytics(projection: chartProjection) {
                    MachineRoomAnalyticsGrid(analytics: analytics)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: projection.scope) {
            if projection.scope != .live { pausedProjection = nil }
        }
        .onChange(of: projection.runID) { pausedProjection = nil }
    }

    private var medianLabel: String {
        guard let metrics = projection.metrics else { return "Unavailable" }
        return metrics.medianMilliseconds.map { "\($0) ms" } ?? "No samples"
    }

    private var scopeDescription: String {
        switch projection.scope {
        case .unavailable: "No local server controller is available."
        case .idle: "Start the local server explicitly to begin observing its handlers."
        case .awaitingSnapshot: "Waiting for the snapshot belonging to this run; previous-run values are hidden."
        case .unobservedRun: "No matching observation is available for this server run."
        case .starting: "The current run is starting; listener readiness is not yet confirmed."
        case .live: "Current server run · refreshed from the existing activity snapshot."
        case .stopping: "Shutdown is in progress; the observed current-run values remain visible."
        case .lastRun: "Most recent server run · not live. The five-minute chart window continues to age."
        case .failedRun: "Last observed failed run; these counts do not establish clean shutdown."
        }
    }
}
