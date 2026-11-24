// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import AppKit
import ExplorerPresentation
import ExplorerDomain

struct ServerView: View {
    @Bindable var lifetime: AppLifetime
    @State private var showConnection = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.lg) {
                ExplorerScreenHeading(
                    eyebrow: "DEVELOPER WORKSPACE",
                    title: "MCP Machine Room",
                    summary: "Research Explorer · MCP 2026-07-28 · \(lifetime.profile.rawValue)"
                )
                if let server = lifetime.server {
                    let projection = MachineRoomProjection(
                        phase: server.phase,
                        controllerRunID: server.runID,
                        snapshot: lifetime.activitySnapshot
                    )
                    commandDeck(server)
                    MachineRoomOverview(projection: projection) { scope in
                        lifetime.showActivity(for: scope)
                    }
                    .id(projection.runID)
                    MCPJourneyView(lifetime: lifetime, journey: lifetime.journey, running: server.phase == .running)
                    recentCalls(projection)
                } else {
                    ContentUnavailableView("Server unavailable", systemImage: "exclamationmark.triangle", description: Text(lifetime.startupProblem ?? "The selected SDK host could not be constructed."))
                }
            }
            .frame(maxWidth: ExplorerDesign.Layout.contentMaxWidth, alignment: .leading)
            .padding(ExplorerDesign.Space.xl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(ExplorerDesign.Palette.canvas)
        .sheet(isPresented: $showConnection) { connectionDetails }
    }

    private func commandDeck(_ server: ServerController) -> some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Local host")
                        .font(ExplorerDesign.Typography.section)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: ExplorerDesign.Space.xs)
                    ExplorerPill(
                        title: server.phase.rawValue,
                        symbol: server.phase == .running ? "checkmark.circle.fill" : server.phase == .failed ? "exclamationmark.triangle" : "circle",
                        tone: server.phase == .running ? .accent : server.phase == .failed ? .caution : .neutral
                    )
                }
                Text(server.endpoint?.url ?? "No listening endpoint · starts explicitly")
                    .font(ExplorerDesign.Typography.mono)
                    .textSelection(.enabled)
                if let run = server.runID {
                    Text("Run: \(run.uuidString)")
                        .font(ExplorerDesign.Typography.mono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let failure = server.failure {
                    Text(failure == .catalogUnavailable
                        ? "Catalog construction failed before listener readiness. Verify the selected SDK resource contract and product; see WRE-S01."
                        : "\(failure.rawValue). \(server.cleanupDebt ? "Cleanup remains unresolved; Start is disabled." : "Review the listener and retry explicitly.")")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if server.cleanupDebt {
                    Label("Cleanup remains unresolved. The host is not known to be joined.", systemImage: "exclamationmark.triangle")
                        .font(ExplorerDesign.Typography.detail)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ExplorerDesign.Space.sm) { hostActions(server) }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) { hostActions(server) }
                }
                Divider()
                Picker("Research source", selection: Binding(get: { lifetime.profile }, set: { lifetime.selectSource($0) })) {
                    ForEach(SourceProfile.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .disabled(!lifetime.canSwitchSource)
                Text("Source changes require a stopped, joined server and settled Research. No request is made at startup.")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Anonymous loopback development access only. Host is checked; browser Origins and supplied Authorization are rejected. Not a public or protected-resource endpoint.", systemImage: "lock.shield")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func hostActions(_ server: ServerController) -> some View {
        if server.canStart {
            Button("Start server", systemImage: "play.fill") { lifetime.startServer() }
                .buttonStyle(.glassProminent)
        } else {
            Button("Stop server", systemImage: "stop.fill") { lifetime.stopServer() }
                .disabled(!server.canStop)
        }
        Button("Restart") { server.restart() }.disabled(server.phase != .running)
        Button("Copy endpoint", systemImage: "doc.on.doc") {
            if let endpoint = server.endpoint {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(endpoint.url, forType: .string)
            }
        }.disabled(server.endpoint == nil)
        Button("Connection details", systemImage: "info.circle") { showConnection = true }
            .disabled(server.endpoint == nil)
    }

    private func recentCalls(_ projection: MachineRoomProjection) -> some View {
        GroupBox("Recent eligible tool calls") {
            if let metrics = projection.metrics, !metrics.recentCalls.isEmpty {
                Table(metrics.recentCalls.reversed()) {
                    TableColumn("Tool", value: \.operation)
                    TableColumn("Duration") { row in Text(row.durationMilliseconds.map { "\($0) ms" } ?? "Unavailable").monospacedDigit() }
                    TableColumn("Outcome") { row in Text(row.outcome.rawValue) }
                }
                .frame(minHeight: 180)
            } else {
                ContentUnavailableView("No retained calls for this run", systemImage: "arrow.left.arrow.right", description: Text("An eligible tool handler must reach a terminal path before it appears here. Local Research is separate."))
            }
            HStack { Spacer(); Button("View activity") { lifetime.showActivity() } }
                .padding(ExplorerDesign.Space.xs)
            Text("Recent 50 retained terminal handlers at most. Calls may come from any client; pre-handler rejections and connection counts are not observed.")
                .font(ExplorerDesign.Typography.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionDetails: some View {
        let recipes = lifetime.server?.endpoint.map { ConnectionRecipe.recipes(for: $0, source: lifetime.profile) } ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connection details").font(ExplorerDesign.Typography.section)
                Text(lifetime.server?.endpoint?.url ?? "Listener not running").font(.body.monospaced()).textSelection(.enabled)
                Text("MCP 2026-07-28 over Streamable HTTP: one stateless POST per request, with MCP-Protocol-Version and Mcp-Method headers and the protocol version and client capabilities in params._meta. There is no initialize handshake, session, GET stream or replay. Anonymous loopback development access only; browser Origins and Authorization are rejected. This is not a protected resource server.")
                    .foregroundStyle(.secondary)
                ForEach(recipes) { recipe in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(recipe.title).font(.headline)
                            Spacer()
                            Button("Copy", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(recipe.curl, forType: .string) }
                        }
                        Text(recipe.curl)
                            .font(ExplorerDesign.Typography.mono)
                            .textSelection(.enabled)
                            .padding(ExplorerDesign.Space.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ExplorerDesign.Palette.control, in: RoundedRectangle(cornerRadius: ExplorerDesign.Radius.small))
                    }
                }
                Text("These exact requests are executed against a live host in this app's tests. A Swift client uses Client with HTTPClientTransport(endpoint:) from Swift-MCP-Server-HTTP; `research-explorer --mcp-client` is the tested stdio client. Each request reaches the same four tool handlers that Activity counts.")
                    .font(.callout)
                HStack {
                    Button("Copy endpoint", systemImage: "doc.on.doc") { if let text = lifetime.server?.endpoint?.url { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } }.disabled(lifetime.server?.endpoint == nil)
                    Spacer(); Button("Done") { showConnection = false }.keyboardShortcut(.defaultAction)
                }
            }.padding(28)
        }.frame(width: 640, height: 620)
    }
}

/// "Explore MCP": a real public-SDK client (Client + HTTPClientTransport) calls this app's own
/// loopback server. Only metadata is shown in the timeline; the tool calls appear in Activity.
struct MCPJourneyView: View {
    @Bindable var lifetime: AppLifetime
    let journey: MCPJourneyController
    let running: Bool
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("A real MCP client in this app connects to the server above over loopback HTTP: server/discover, tools/list, then the four tools. Results are checked against each tool's outputSchema and the requested revision. Nothing is sent until you press Explore MCP.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    if journey.isRunning {
                        Button("Cancel", systemImage: "xmark") { journey.cancel() }
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Explore MCP", systemImage: "arrow.left.arrow.right") { lifetime.exploreMCP() }
                            .buttonStyle(.glassProminent)
                            .disabled(!running)
                            .help(running ? "Runs one guided client journey." : "Start the server first; the journey never starts it.")
                    }
                    Toggle("Record exchange details", isOn: Binding(get: { journey.inspectExchanges }, set: { journey.setInspectExchanges($0) }))
                        .disabled(journey.isRunning)
                        .help("Opt-in for the next run: method, tool, byte counts, messages and timing of each real SDK exchange. Kept in memory for this server run only; never exported.")
                    Spacer()
                    Text(journey.phase.rawValue).foregroundStyle(.secondary)
                }
                if !journey.steps.isEmpty {
                    Table(journey.steps) {
                        TableColumn("Method") { Text($0.method).font(.callout.monospaced()) }
                        TableColumn("Tool") { Text($0.tool ?? "—").font(.callout.monospaced()) }
                        TableColumn("Status") { step in Text(step.status.rawValue) }
                        TableColumn("Validated") { step in Text(step.validated ? "Schema + identity" : "No") }
                        TableColumn("Revision") { step in Text(step.revisionID ?? "—") }
                        TableColumn("Duration") { step in Text("\(step.milliseconds) ms").monospacedDigit() }
                    }.frame(minHeight: 170)
                    ForEach(journey.steps.compactMap(\.failure), id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                }
                if !journey.exchanges.isEmpty {
                    Text("Exchange inspector · \(journey.exchanges.count) real SDK exchanges\(journey.droppedExchanges > 0 ? " · \(journey.droppedExchanges) not retained" : "")")
                        .font(.headline)
                    Table(journey.exchanges) {
                        TableColumn("#") { Text("\($0.id + 1)").monospacedDigit() }.width(28)
                        TableColumn("Method") { Text($0.method).font(.callout.monospaced()) }
                        TableColumn("Tool") { Text($0.tool ?? "—").font(.callout.monospaced()) }
                        TableColumn("Sent") { Text("\($0.requestBytes) B").monospacedDigit() }
                        TableColumn("Received") { record in Text("\(record.responseBytes) B in \(record.messages) message\(record.messages == 1 ? "" : "s")").monospacedDigit() }
                        TableColumn("Outcome") { Text($0.outcome.rawValue) }
                        TableColumn("Duration") { Text("\($0.milliseconds) ms").monospacedDigit() }
                    }.frame(minHeight: 200)
                    Text("Sizes and metadata only: no bodies, arguments, header values or error text are kept. One stateless POST per request; no initialize, no session.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let outline = journey.outline {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(outline.provenance.title).font(.headline)
                        Text("Revision \(outline.snapshot.revisionID) · \(outline.snapshot.provider) · \(outline.provenance.synthetic ? "fictional" : "fetched snapshot")").font(.caption).foregroundStyle(.secondary)
                        if let passage = journey.passage { Text(passage.text).lineLimit(6).textSelection(.enabled) }
                        if let refs = journey.references { Text("\(refs.references.count) references, \(refs.unresolvedIDs.count) unresolved · not independently verified").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        } label: {
            Label("Guided MCP journey", systemImage: "point.3.connected.trianglepath.dotted")
                .font(ExplorerDesign.Typography.panel)
        }
    }
}
