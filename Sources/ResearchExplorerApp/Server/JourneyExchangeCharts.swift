// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Charts
import ExplorerPresentation

/// Five planned stages; status, duration and validation come from actual observations.
struct JourneyMilestoneRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let projection: MachineRoomJourneyProjection

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: ExplorerDesign.Space.sm)], alignment: .leading, spacing: ExplorerDesign.Space.sm) {
            ForEach(projection.milestones) { milestone in
                milestoneTile(milestone)
            }
        }
    }

    private func milestoneTile(_ milestone: MachineRoomJourneyProjection.Milestone) -> some View {
        let latest = milestone.latest
        let tone: Color = latest?.status == .succeeded ? .green : latest?.status == .failed ? .red : latest?.status == .cancelled ? .orange : .secondary
        let symbol = latest?.status == .succeeded ? "checkmark.circle" : latest?.status == .failed ? "exclamationmark.triangle" : latest?.status == .cancelled ? "stop.circle" : "circle.dashed"
        return VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tone)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .animation(ExplorerDesign.Motion.animation(.status, reduceMotion: reduceMotion), value: symbol)
                    .accessibilityHidden(true)
                Text(milestone.stage.rawValue).font(ExplorerDesign.Typography.panel)
            }
            Text(latest?.status.rawValue ?? "Not observed")
                .font(ExplorerDesign.Typography.detail)
                .foregroundStyle(.secondary)
            if let latest {
                Text(latest.milliseconds >= 0 ? "\(latest.milliseconds) ms" : "Duration unavailable")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                Text(milestone.validation.rawValue)
                    .font(ExplorerDesign.Typography.detail)
                    .fixedSize(horizontal: false, vertical: true)
                if milestone.observations.count > 1 {
                    Text("\(milestone.observations.count) observations · latest shown")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(ExplorerDesign.Space.sm)
        .background(ExplorerDesign.Palette.control, in: RoundedRectangle(cornerRadius: ExplorerDesign.Radius.small))
        .accessibilityElement(children: .combine)
    }
}

/// Both charts select the same retained record. Ordinals are retention order,
/// not reconstructed start times or a network waterfall.
struct JourneyExchangeCharts: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let projection: MachineRoomJourneyProjection
    @State private var selectedKey: String?

    private var exchanges: [MachineRoomJourneyProjection.Exchange] { projection.exchanges }

    private func key(_ exchange: MachineRoomJourneyProjection.Exchange) -> String {
        "#\(exchange.id)"
    }

    private var selected: MachineRoomJourneyProjection.Exchange? {
        exchanges.first { key($0) == selectedKey }
    }

    private var selection: Binding<String?> {
        Binding(get: { selected.map { key($0) } }, set: { value in
            selectedKey = exchanges.first { key($0) == value }.map { key($0) }
        })
    }

    private var chartHeight: CGFloat { CGFloat(max(170, exchanges.count * 34)) }

    private var largestBytes: Double {
        let sent = exchanges.compactMap(\.requestBytes).max() ?? 0
        let received = exchanges.compactMap(\.responseBytes).max() ?? 0
        return Double(max(1, max(sent, received)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
            ExplorerPanel {
                VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                    HStack {
                        Text("Exchange inspector")
                            .font(ExplorerDesign.Typography.section)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: ExplorerDesign.Space.xs)
                        ExplorerPill(title: "Opt-in", symbol: "eye", tone: .accent)
                    }
                    Text("\(exchanges.count) retained SDK exchanges · up to 32 per guided journey")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                    if let dropped = projection.droppedExchanges {
                        if dropped > 0 {
                            Label("\(dropped) additional exchanges not retained", systemImage: "exclamationmark.triangle")
                                .font(ExplorerDesign.Typography.detail)
                        }
                    } else {
                        Label("Dropped-record count unavailable", systemImage: "exclamationmark.triangle")
                            .font(ExplorerDesign.Typography.detail)
                    }
                    Text("Records appear when an exchange finishes and the controller publishes its metadata. A normal journey has six exchanges; catalogue pagination can add more. No payloads, headers, arguments or credentials are displayed here.")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if exchanges.isEmpty {
                        ContentUnavailableView("No retained exchanges yet", systemImage: "arrow.left.arrow.right", description: Text("Enable recording before starting the guided journey. Only actual retained records appear here."))
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        Picker("Inspect exchange", selection: selection) {
                            Text("None").tag(nil as String?)
                            ForEach(exchanges) { record in
                                Text(record.label).tag(Optional(key(record)))
                            }
                        }
                        .pickerStyle(.menu)
                        .help("Choose a retained record with the keyboard or select it in either chart.")
                        if let selected {
                            exchangeDetails(selected)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !exchanges.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: ExplorerDesign.Space.md, alignment: .top)], alignment: .leading, spacing: ExplorerDesign.Space.md) {
                    durationChart
                    bytesChart
                }
                ExplorerPanel {
                    VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                        Text("Retained exchange records")
                            .font(ExplorerDesign.Typography.panel)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(exchanges) { record in
                            Button {
                                selectedKey = key(record)
                            } label: {
                                HStack(alignment: .top, spacing: ExplorerDesign.Space.sm) {
                                    Text(key(record)).font(ExplorerDesign.Typography.mono)
                                    VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
                                        Text(record.tool ?? record.method).font(ExplorerDesign.Typography.mono)
                                        Text("\(record.outcome.rawValue) · \(durationLabel(record.milliseconds)) · \(bytesLabel(record.requestBytes)) sent / \(bytesLabel(record.responseBytes)) received")
                                            .font(ExplorerDesign.Typography.detail)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    if selectedKey == key(record) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(ExplorerDesign.Palette.accent)
                                    }
                                }
                                .padding(ExplorerDesign.Space.xs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedKey == key(record) ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: exchanges.map(\.id)) {
            if selected == nil { selectedKey = nil }
        }
    }

    private var durationChart: some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                Text("Exchange duration").font(ExplorerDesign.Typography.panel)
                    .accessibilityAddTraits(.isHeader)
                Text("Measured transport-exchange duration · ms · retained order")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                if exchanges.contains(where: { $0.milliseconds != nil }) {
                    Chart {
                        ForEach(exchanges) { record in
                            if let duration = record.milliseconds {
                                BarMark(x: .value("Duration (ms)", Double(duration)), y: .value("Record", key(record)))
                                    .foregroundStyle(ExplorerDesign.Palette.accent.opacity(selectedKey == nil || selectedKey == key(record) ? 1 : 0.3))
                                    .accessibilityLabel(Text(record.label))
                                    .accessibilityValue(Text("\(duration) milliseconds"))
                            }
                        }
                    }
                    .chartYScale(domain: exchanges.reversed().map { key($0) })
                    .chartXScale(domain: 0.0...max(1.0, Double(exchanges.compactMap(\.milliseconds).max() ?? 0)))
                    .chartYSelection(value: selection)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartXAxisLabel("ms")
                    .frame(height: chartHeight)
                    .animation(ExplorerDesign.Motion.animation(.chart, reduceMotion: reduceMotion), value: exchanges.map(\.id))
                    .animation(ExplorerDesign.Motion.animation(.selection, reduceMotion: reduceMotion), value: selectedKey)
                    .accessibilityLabel("Duration by retained SDK exchange")
                } else {
                    Text("No measured durations").foregroundStyle(.secondary)
                }
                Text("No shared start timestamps are recorded; this is not a waterfall.")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bytesChart: some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                Text("SDK message bytes").font(ExplorerDesign.Typography.panel)
                    .accessibilityAddTraits(.isHeader)
                Text("Outgoing request body and incoming delivered messages · bytes")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                if exchanges.contains(where: { $0.requestBytes != nil || $0.responseBytes != nil }) {
                    Chart {
                        ForEach(exchanges) { record in
                            if let bytes = record.requestBytes {
                                BarMark(x: .value("Bytes", Double(bytes)), y: .value("Record", key(record)))
                                    .position(by: .value("Direction", "Sent"), axis: .vertical)
                                    .foregroundStyle(ExplorerDesign.Palette.accent.opacity(selectedKey == nil || selectedKey == key(record) ? 1 : 0.3))
                                    .accessibilityLabel(Text("\(record.label), sent"))
                                    .accessibilityValue(Text("\(bytes) bytes"))
                            }
                            if let bytes = record.responseBytes {
                                BarMark(x: .value("Bytes", Double(bytes)), y: .value("Record", key(record)))
                                    .position(by: .value("Direction", "Received"), axis: .vertical)
                                    .foregroundStyle(Color.secondary.opacity(selectedKey == nil || selectedKey == key(record) ? 0.85 : 0.25))
                                    .accessibilityLabel(Text("\(record.label), received"))
                                    .accessibilityValue(Text("\(bytes) bytes"))
                            }
                        }
                    }
                    .chartYScale(domain: exchanges.reversed().map { key($0) })
                    .chartXScale(domain: 0.0...largestBytes)
                    .chartYSelection(value: selection)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartXAxisLabel("B")
                    .frame(height: chartHeight)
                    .animation(ExplorerDesign.Motion.animation(.chart, reduceMotion: reduceMotion), value: exchanges.map(\.id))
                    .animation(ExplorerDesign.Motion.animation(.selection, reduceMotion: reduceMotion), value: selectedKey)
                    .accessibilityLabel("Sent and received SDK message bytes by retained exchange")
                    HStack {
                        Label("Sent", systemImage: "square.fill").foregroundStyle(ExplorerDesign.Palette.accent)
                        Label("Received", systemImage: "square.fill").foregroundStyle(.secondary)
                    }
                    .font(ExplorerDesign.Typography.detail)
                } else {
                    Text("No byte measurements").foregroundStyle(.secondary)
                }
                Text("SDK message sizes only, not HTTP/TLS framing or network traffic.")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exchangeDetails(_ record: MachineRoomJourneyProjection.Exchange) -> some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
            Text(record.label).font(ExplorerDesign.Typography.mono)
                .textSelection(.enabled)
            LabeledContent("Transport outcome", value: record.outcome.rawValue)
            LabeledContent("Duration", value: durationLabel(record.milliseconds))
            LabeledContent("Sent SDK body", value: bytesLabel(record.requestBytes))
            LabeledContent("Received SDK messages", value: bytesLabel(record.responseBytes))
            LabeledContent("Delivered message count", value: record.messages.map { String($0) } ?? "Unavailable")
            Text("A transport response does not establish JSON-RPC success or schema/identity validation. See the separate milestone observations.")
                .font(ExplorerDesign.Typography.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(ExplorerDesign.Typography.body)
        .padding(ExplorerDesign.Space.sm)
        .background(ExplorerDesign.Palette.control, in: RoundedRectangle(cornerRadius: ExplorerDesign.Radius.small))
    }

    private func durationLabel(_ value: Int?) -> String { value.map { "\($0) ms" } ?? "Unavailable" }
    private func bytesLabel(_ value: Int?) -> String { value.map { "\($0) B" } ?? "Unavailable" }
}
