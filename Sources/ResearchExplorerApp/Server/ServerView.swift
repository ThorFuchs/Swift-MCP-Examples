// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import AppKit
import ExplorerPresentation
import ExplorerDomain

/// Native Machine Room: explicit host controls, run-scoped server analytics
/// and a separately scoped, opt-in client journey.
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
        Button("Restart") { lifetime.restartServer() }.disabled(server.phase != .running)
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

/// The guided client remains owned by MCPJourneyController. This view projects
/// actual milestones and opt-in exchanges; no additional MCP request is made.
struct MCPJourneyView: View {
    @Bindable var lifetime: AppLifetime
    let journey: MCPJourneyController
    let running: Bool
    @State private var showObservations = false

    private var projection: MachineRoomJourneyProjection {
        MachineRoomJourneyProjection(
            currentRunID: lifetime.server?.runID,
            journeyRunID: lifetime.journeyOwnerRunID,
            phase: journey.phase,
            steps: journey.steps,
            inspectionEnabled: journey.inspectExchanges,
            records: journey.exchanges,
            dropped: journey.droppedExchanges
        )
    }

    var body: some View {
        let presentation = projection
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
            ExplorerPanel {
                VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Client ↔ Server")
                            .font(ExplorerDesign.Typography.section)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: ExplorerDesign.Space.xs)
                        ExplorerPill(
                            title: presentation.phase?.rawValue ?? (journey.isRunning ? "Previous journey settling" : "Ready"),
                            symbol: presentation.phase == .completed ? "checkmark.circle" : presentation.phase == .failed ? "exclamationmark.triangle" : "arrow.left.arrow.right",
                            tone: presentation.phase == .failed ? .caution : presentation.phase == .running ? .accent : .neutral
                        )
                    }
                    Text("A genuine public-SDK client talks to this app's explicitly started loopback HTTP server. No requests are sent until you press Explore MCP.")
                        .font(ExplorerDesign.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: ExplorerDesign.Space.md) { controls }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) { controls }
                    }
                    HStack(spacing: ExplorerDesign.Space.sm) {
                        Label("MCPClient", systemImage: "macwindow")
                            .font(ExplorerDesign.Typography.panel)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(ExplorerDesign.Palette.accent)
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        Label("MCPServer", systemImage: "server.rack")
                            .font(ExplorerDesign.Typography.panel)
                    }
                    .padding(ExplorerDesign.Space.sm)
                    .background(ExplorerDesign.Palette.control, in: RoundedRectangle(cornerRadius: ExplorerDesign.Radius.small))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("MCP client and loopback HTTP server")
                    Text("Planned milestones · actual recorded outcomes")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                    JourneyMilestoneRail(projection: presentation)
                    if !presentation.steps.isEmpty {
                        DisclosureGroup("Recorded milestone details (\(presentation.steps.count))", isExpanded: $showObservations) {
                            VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                                ForEach(presentation.steps) { step in
                                    VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
                                        Text(step.tool ?? step.method).font(ExplorerDesign.Typography.mono)
                                            .textSelection(.enabled)
                                        Text("\(step.status.rawValue) · \(step.milliseconds >= 0 ? "\(step.milliseconds) ms" : "Duration unavailable")")
                                            .font(ExplorerDesign.Typography.detail)
                                            .foregroundStyle(.secondary)
                                        if let revision = step.revisionID {
                                            Text("Revision \(revision)").font(ExplorerDesign.Typography.detail)
                                        }
                                        if let failure = step.failure {
                                            Label(failure, systemImage: "exclamationmark.triangle")
                                                .font(ExplorerDesign.Typography.detail)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Divider()
                                }
                            }
                            .padding(.top, ExplorerDesign.Space.sm)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if presentation.inspectionEnabled {
                JourneyExchangeCharts(projection: presentation)
                    .id(lifetime.journeyVisualID)
            }
            if presentation.isCurrent, let outline = journey.outline {
                ExplorerPanel {
                    VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                        Text("Research result").font(ExplorerDesign.Typography.panel)
                            .accessibilityAddTraits(.isHeader)
                        Text(outline.provenance.title).font(ExplorerDesign.Typography.section)
                        Text("Revision \(outline.snapshot.revisionID) · \(outline.snapshot.provider) · \(outline.provenance.synthetic ? "fictional" : "fetched snapshot")")
                            .font(ExplorerDesign.Typography.detail)
                            .foregroundStyle(.secondary)
                        if let passage = journey.passage {
                            Text(passage.text).lineLimit(6).textSelection(.enabled)
                        }
                        if let refs = journey.references {
                            Text("\(refs.references.count) references, \(refs.unresolvedIDs.count) unresolved · not independently verified")
                                .font(ExplorerDesign.Typography.detail)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: lifetime.journeyVisualID) { showObservations = false }
        .onChange(of: lifetime.server?.runID) { showObservations = false }
    }

    @ViewBuilder private var controls: some View {
        if journey.isRunning {
            HStack(spacing: ExplorerDesign.Space.xs) {
                Button("Cancel", systemImage: "xmark") { journey.cancel() }
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Client journey running")
            }
        } else {
            Button("Explore MCP", systemImage: "arrow.left.arrow.right") { lifetime.exploreMCP() }
                .buttonStyle(.glassProminent)
                .disabled(!running)
                .help(running ? "Runs one guided client journey." : "Start the server first; the journey never starts it.")
        }
        Toggle("Record exchange details", isOn: Binding(get: { journey.inspectExchanges }, set: { journey.setInspectExchanges($0) }))
            .disabled(journey.isRunning)
            .help("Opt in before starting a journey. Turning this off hides exchange metadata; existing retained records are cleared by the next journey or the existing clear lifecycle.")
    }
}
