// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import AppKit
import Observation
import ExplorerDomain
import WikimediaAccess
import ExplorerPresentation

enum Workspace: String, CaseIterable, Identifiable { case research = "Research", server = "Server", activity = "Activity"
    var id: String { rawValue }
    var symbol: String { switch self { case .research: "magnifyingglass"; case .server: "server.rack"; case .activity: "waveform.path" } }
}
/// A prepared source: its service plus, for the offline demo only, the prepared revision edit.
struct PreparedSource: Sendable {
    let service: ExplorerService
    let offlineEdit: OfflineRevisionEdit?
}
/// Owns the app's source, research, server, client journey and activity observation.
/// View transitions never own or delay these asynchronous operations.
@MainActor @Observable final class AppLifetime {
    private(set) var profile: SourceProfile
    let termination = AppTerminationController()
    var canSwitchSource: Bool { !isQuitting && !termination.unsettled && bootstrap == nil && server?.phase == .stopped && server?.cleanupDebt == false && !journey.isRunning }
    /// The guided "Explore MCP" client journey against this app's own running server.
    let journey = MCPJourneyController()
    /// Presentation identity only. The SDK controller still owns its task.
    private(set) var journeyOwnerRunID: UUID?
    private(set) var journeyVisualID = UUID()
    let activity: ActivityStore
    var activitySnapshot = ActivitySnapshot.empty
    private(set) var server: ServerController?
    var exporting = false
    var exportProblem: String?
    private var exportCleanupDebt = false
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private let exportWriter: ActivityExportWriter
    @ObservationIgnored private let loadSource: @Sendable (SourceProfile) async throws -> PreparedSource
    @ObservationIgnored private let makeHost: @Sendable (ExplorerService, ActivityStore, UUID) throws -> any ExplorerHTTPHost
    private(set) var service: ExplorerService?
    private(set) var offlineEdit: OfflineRevisionEdit?
    private(set) var research: ResearchController?
    private(set) var researchMode: ResearchExecutionMode = .direct
    private(set) var researchRunID: UUID?
    private(set) var researchModeProblem: String?
    private(set) var collection = ResearchCollection()
    var collectionMessage: String?
    var canCollectEvidence: Bool {
        canChangeResearchMode && researchRouteReady && research?.phase == .section
            && research?.passage?.textAvailable == true && research?.passage?.text.isEmpty == false
    }
    var canChangeResearchMode: Bool { !isQuitting && !termination.unsettled && bootstrap == nil && service != nil }
    var canUseMCPResearch: Bool { canChangeResearchMode && server?.phase == .running && server?.endpoint != nil && server?.runID != nil }
    var researchRouteReady: Bool {
        researchMode == .direct || (researchRunID != nil && server?.runID == researchRunID && server?.phase == .running)
    }
    private(set) var startupProblem: String?
    var destination = Workspace.research
    var activityBucketScope: MachineRoomBucketScope?

    /// A presentation-only historical filter; the store and export schema are unchanged.
    func showActivity(for scope: MachineRoomBucketScope? = nil) {
        activityBucketScope = scope
        destination = .activity
    }

    var searchFocus = UUID()
    var isQuitting = false
    weak var mainWindow: NSWindow?
    @ObservationIgnored private var bootstrap: Task<Void, Never>?
    /// First launch selects the fictional offline collection: no request, no listener (J1).
    init(profile: SourceProfile = .offlineDemo,
         loadSource: @escaping @Sendable (SourceProfile) async throws -> PreparedSource = { try await AppResources.loadSource(profile: $0) },
         makeHost: @escaping @Sendable (ExplorerService, ActivityStore, UUID) throws -> any ExplorerHTTPHost = AppLifetime.defaultHost,
         exportWriter: ActivityExportWriter = ActivityExportWriter()) {
        self.profile = profile; self.loadSource = loadSource; self.makeHost = makeHost
        self.exportWriter = exportWriter; activity = ActivityStore()
    }
    /// Service-only loader (no offline edit affordance), used by focused lifecycle tests.
    convenience init(profile: SourceProfile = .offlineDemo,
                     loadService: @escaping @Sendable (SourceProfile) async throws -> ExplorerService,
                     makeHost: @escaping @Sendable (ExplorerService, ActivityStore, UUID) throws -> any ExplorerHTTPHost = AppLifetime.defaultHost,
                     exportWriter: ActivityExportWriter = ActivityExportWriter()) {
        self.init(profile: profile, loadSource: { PreparedSource(service: try await loadService($0), offlineEdit: nil) },
                  makeHost: makeHost, exportWriter: exportWriter)
    }
    nonisolated static func defaultHost(_ service: ExplorerService, _ activity: ActivityStore, _ id: UUID) throws -> any ExplorerHTTPHost {
        SDKHTTPHost(service: service, activity: activity, runID: id, configuration: try LocalEndpoint(port: 8765))
    }
    private func makeResearch(_ service: ExplorerService, source: SourceProfile, edit: OfflineRevisionEdit?) -> ResearchController {
        let activity = self.activity
        return ResearchController(client: service, source: source, record: { op, ok in
            await activity.localResearch(op, success: ok, profile: service.profile)
        }, offlineEdit: edit)
    }
    /// A mode switch discards transient reader state only after its owner joins.
    /// The query is retained, but no search or transport exchange starts implicitly.
    func selectResearchMode(_ mode: ResearchExecutionMode) {
        guard canChangeResearchMode, let service,
              mode != researchMode || (mode == .mcp && !researchRouteReady) else { return }
        let previousQuery = research?.query ?? ""
        let next: ResearchController
        let run: UUID?
        if mode == .mcp {
            guard canUseMCPResearch, let server, let endpoint = server.endpoint, let id = server.runID else { return }
            do {
                let client = try RunBoundResearchClient(endpoint: endpoint, profile: profile, isCurrent: { [weak server] in
                    server?.phase == .running && server?.runID == id && server?.endpoint == endpoint
                })
                // The actual server handler observer already records these operations.
                // Do not record MCP calls a second time as direct local research.
                next = ResearchController(client: client, source: profile)
                run = id
            } catch {
                researchModeProblem = "Could not construct the selected MCP route. No request was sent."
                return
            }
        } else {
            next = makeResearch(service, source: profile, edit: offlineEdit)
            run = nil
        }
        researchModeProblem = nil
        isQuitting = true
        bootstrap = Task { [self] in
            await research?.shutdown()
            next.query = previousQuery
            research = next
            researchMode = mode
            researchRunID = run
            bootstrap = nil; isQuitting = false
        }
    }

    func waitUntilPrepared() async { await bootstrap?.value }
    func waitUntilExportSettled() async { await exportTask?.value }
    func waitForTerminationSettlement() async { await termination.waitUntilSettled() }
    func prepare() {
        observe()
        guard bootstrap == nil, service == nil, startupProblem == nil, !isQuitting else { return }
        let activity = self.activity, makeHost = self.makeHost
        bootstrap = Task { [self] in
            defer { bootstrap = nil }
            do {
                let prepared = try await loadSource(profile)
                try Task.checkCancellation()
                let service = prepared.service
                self.service = service; offlineEdit = prepared.offlineEdit
                research = makeResearch(service, source: profile, edit: prepared.offlineEdit)
                server = ServerController(activity: activity, factory: { runID in
                    try makeHost(service, activity, runID)
                })
            } catch is CancellationError { /* quit owns and joins bootstrap */ }
            catch { startupProblem = "The selected source could not be prepared. No fictional fallback was substituted. Check the complete app resource bundles." }
        }
    }
    func observe() {
        guard observation == nil else { return }
        observation = Task { [weak self, activity] in
            while !Task.isCancelled {
                let snapshot = await activity.snapshot()
                guard !Task.isCancelled else { break }; self?.activitySnapshot = snapshot
                do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
            }
        }
    }
    /// A new server run starts with no results or inspector records of an earlier run.
    func startServer() {
        guard !isQuitting, !termination.unsettled, let server, server.canStart else { return }
        if researchMode == .mcp || journey.isRunning {
            settleClientOwners { server.start() }
        } else {
            journey.clear(); server.start()
        }
    }
    /// Preserve the direct reader on stop. An MCP reader must join its
    /// operations before a new run can reuse the endpoint.
    func stopServer() {
        guard !isQuitting, !termination.unsettled, let server else { return }
        if researchMode == .mcp {
            settleClientOwners(clearJourney: false) { server.stop() }
        } else {
            journey.cancel(); server.stop()
        }
    }

    func restartServer() {
        guard !isQuitting, !termination.unsettled, let server, server.phase == .running else { return }
        settleClientOwners { server.restart() }
    }

    private func settleClientOwners(clearJourney: Bool = true, then action: @escaping @MainActor () -> Void) {
        guard bootstrap == nil else { return }
        isQuitting = true
        // Invalidate the old route immediately; a stopped/restarted reader
        // remains explicitly unavailable until the user selects a new route.
        if researchMode == .mcp { researchRunID = nil; research?.cancel() }
        journey.cancel()
        bootstrap = Task { [self] in
            if researchMode == .mcp { await research?.shutdown() }
            await journey.cancelAndJoin()
            if clearJourney { journey.clear() }
            action()
            bootstrap = nil; isQuitting = false
        }
    }
    func exploreMCP() {
        guard !isQuitting, !termination.unsettled, !journey.isRunning else { return }
        journeyVisualID = UUID()
        journeyOwnerRunID = server?.phase == .running && server?.endpoint != nil ? server?.runID : nil
        journey.start(endpoint: server?.endpoint, running: server?.phase == .running, source: profile)
    }
    func selectSource(_ profile: SourceProfile) {
        guard profile != self.profile, canSwitchSource else { return }
        isQuitting = true // quiesces every mutating UI action during handoff
        bootstrap = Task { [self] in
            await journey.cancelAndJoin(); journey.clear() // nothing of the old source survives the switch
            await research?.shutdown() // keep the old owner until its actual join
            do {
                let prepared = try await loadSource(profile)
                try Task.checkCancellation()
                let selected = prepared.service
                self.profile = profile; service = selected; offlineEdit = prepared.offlineEdit
                researchMode = .direct; researchRunID = nil; researchModeProblem = nil
                research = makeResearch(selected, source: profile, edit: prepared.offlineEdit)
                server = ServerController(activity: activity, factory: { [activity, makeHost] id in
                    try makeHost(selected, activity, id)
                })
            } catch {
                startupProblem = "Source handoff failed. The old source was not relabelled."
                // The old driver joined before handoff. A failed construction
                // must not leave its retained service with a closed controller.
                // A failed source handoff does not silently route an MCP reader direct.
                if researchMode == .direct, let service { research = makeResearch(service, source: self.profile, edit: offlineEdit) }
                else { researchRunID = nil }
            }
            bootstrap = nil; isQuitting = false
        }
    }
    /// Capture only the settled section currently displayed by the selected route.
    func collectEvidence() {
        guard canCollectEvidence, let reader = research, let outline = reader.outline,
              let part = reader.selectedPart, let passage = reader.passage else { return }
        do {
            try collection.capture(outline: outline, part: part, passage: passage, references: reader.citations,
                                   referenceProblem: reader.referenceProblem?.code, route: researchMode)
            collectionMessage = "Section added to the in-memory collection."
        } catch ResearchCollection.Failure.alreadyCollected {
            collectionMessage = "This exact revision and section are already collected."
        } catch {
            collectionMessage = "Collection admission failed. Check source identity or collection limits."
        }
    }

    func updateEvidenceNote(_ note: String, id: UUID) {
        guard !isQuitting, !termination.unsettled else { return }
        do { try collection.setNote(note, for: id); collectionMessage = nil }
        catch { collectionMessage = "Note not saved: the 4 KiB note or collection limit was reached." }
    }

    func removeEvidence(_ id: UUID) {
        guard !isQuitting, !termination.unsettled else { return }
        collection.remove(id); collectionMessage = nil
    }

    func exportCollection(_ format: ResearchCollection.Format) {
        guard exportTask == nil, !isQuitting, !termination.unsettled, !collection.entries.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Research-Collection." + format.fileExtension
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let snapshot = collection
        exporting = true; collectionMessage = nil
        exportTask = Task { [self] in
            defer { exporting = false; exportTask = nil }
            do {
                try await exportWriter.writeCollection(snapshot, format: format, to: destination)
                collectionMessage = "Collection exported."
            } catch is ExportSettlementFailure {
                exportCleanupDebt = true
                collectionMessage = "Export cleanup remains unresolved; quit will retain this failure."
            } catch is CancellationError {
                collectionMessage = "Collection export cancelled."
            } catch {
                collectionMessage = "Collection export was not completed."
            }
        }
    }

    func export(filter: ActivityFilter) {
        guard exportTask == nil, !isQuitting, !termination.unsettled else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Explorer-activity.json"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        beginExport(filter: filter, destination: destination)
    }
    func beginExport(filter: ActivityFilter, destination: URL) {
        guard exportTask == nil, !isQuitting, !termination.unsettled else { return }
        let snapshot = activitySnapshot
        exporting = true
        exportTask = Task { [self] in
            defer { exporting = false; exportTask = nil }
            do {
                // Bounded writer actor does JSON + disk work away from UI rendering.
                try await exportWriter.encodeAndWrite(snapshot, filter: filter, to: destination)
            } catch is ExportSettlementFailure {
                exportCleanupDebt = true; exportProblem = "Export failed and its owned temporary-file cleanup is unresolved. The app will retain this failure when Quit is requested."
            } catch is CancellationError { exportProblem = "Export was cancelled. Owned partial output was removed." }
            catch { exportProblem = "Export was denied or could not be committed. No provider payload, credentials or arbitrary error description was retained." }
        }
    }
    func quit(waitMilliseconds: Int = 10_000) async -> Bool {
        guard !isQuitting, !termination.unsettled else { return false }
        isQuitting = true
        let clean = await termination.request(waitMilliseconds: waitMilliseconds, settle: { [self] in
            bootstrap?.cancel(); await bootstrap?.value
            await journey.cancelAndJoin(); journey.clear() // client requests end before the server stops; a declined quit keeps the journey usable
            await research?.shutdown()
            exportTask?.cancel(); await exportTask?.value
            let serverClean = await server?.stopAndJoin() ?? true
            guard serverClean, !exportCleanupDebt else { return false }
            observation?.cancel(); await observation?.value; observation = nil
            return true
        }, recover: { [self] in
            // Called only after the old Research driver actually joined.
            if researchMode == .direct, let service { research = makeResearch(service, source: profile, edit: offlineEdit) }
            else { researchRunID = nil }
            isQuitting = false
            if service == nil { startupProblem = nil; prepare() } else { observe() }
        })
        if !clean { isQuitting = false }
        return clean
    }
}
/// Narrow asynchronous termination bridge; no process signals or synchronous actor wait.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var lifetime: AppLifetime?
    private var quitting: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard quitting == nil, let lifetime else { return quitting == nil ? .terminateNow : .terminateCancel }
        quitting = Task {
            let clean = await lifetime.quit()
            sender.reply(toApplicationShouldTerminate: clean)
            if !clean {
                quitting = nil
                let alert = NSAlert(); alert.messageText = "The app has not finished cleanup"
                alert.informativeText = "The app retained unsettled owners. Research becomes available after its old work joins. Server or export cleanup debt remains visible; no join was manufactured."
                alert.addButton(withTitle: "Return to Explorer"); alert.runModal()
            }
        }
        return .terminateLater
    }
}
struct WindowReference: NSViewRepresentable {
    let register: @MainActor (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowProbe { WindowProbe(register: register) }
    func updateNSView(_ view: WindowProbe, context: Context) {}
    final class WindowProbe: NSView {
        let register: @MainActor (NSWindow) -> Void
        init(register: @escaping @MainActor (NSWindow) -> Void) { self.register = register; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() { if let window { register(window) } }
    }
}

/// Finite file/parser startup on its own actor, not the UI executor.
private actor AppResources {
    static let shared = AppResources()
    static func loadSource(profile: SourceProfile) async throws -> PreparedSource { try await shared.load(profile: profile) }
    private func load(profile: SourceProfile) throws -> PreparedSource {
        try Task.checkCancellation()
        switch profile {
        case .offlineDemo:
            let provider = try FixtureProvider.load()
            return .init(service: ExplorerService(provider: provider, limits: try ExplorerLimits()), offlineEdit: .prepared(provider))
        case .wikipediaEnglish: return .init(service: ExplorerService(provider: WikipediaProvider(), limits: try ExplorerLimits()), offlineEdit: nil)
        }
    }
}
