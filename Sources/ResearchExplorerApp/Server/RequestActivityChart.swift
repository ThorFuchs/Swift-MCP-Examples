// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Charts
import ExplorerPresentation

struct RequestActivityChart: View {
    let snapshot: ActivitySnapshot
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Request activity").font(ExplorerDesign.Type.section)
                Text("Completed eligible MCP tool calls per 5-second bucket · last 5 minutes")
                    .font(ExplorerDesign.Type.body)
                    .foregroundStyle(.secondary)
                if snapshot.metricsAvailable {
                    Chart(snapshot.buckets) { bucket in
                        BarMark(x: .value("Time", bucket.date), y: .value("Completed calls", bucket.calls))
                            .foregroundStyle(ExplorerDesign.Palette.accent)
                    }
                    .chartYAxisLabel("Calls / 5 s")
                    .frame(height: 180)
                        .accessibilityLabel("Completed MCP tool calls over five minutes")
                        .accessibilityValue("\(snapshot.buckets.reduce(UInt64(0)) { $0 + $1.calls }) observed calls. \(snapshot.metricsPartial ? "Partial observation." : "Catalogue handlers only.")")
                    Text("Median uses \(snapshot.durationSampleCount) retained duration samples, at most 512 within five minutes. Cancelled: \(snapshot.cancelled).").font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Observation unavailable", systemImage: "chart.bar.xaxis", description: Text("Start the server explicitly to begin a new observed run."))
                }
            }.padding(ExplorerDesign.Space.xs)
        }
    }
}
