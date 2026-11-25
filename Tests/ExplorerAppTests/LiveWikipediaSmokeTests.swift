// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import ExplorerDomain
import WikimediaAccess
import ExplorerPresentation
@testable import ResearchExplorerApp

/// Explicit, network-dependent acceptance for the production Wikipedia provider.
/// Uses the normal app source loader and real SDK host, with an ephemeral local
/// port. No replay transport, fixture fallback, external citation fetch, or
/// assertions about a specific mutable revision number.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RE_LIVE_WIKIPEDIA"] == "1",
                             "Opt in to the real public Wikipedia REST API"))
@MainActor struct LiveWikipediaSmokeTests {
    private let query = "Noether's theorem"

    private func withLiveApp(_ body: @MainActor (AppLifetime) async throws -> Void) async throws {
        let app = AppLifetime(makeHost: { service, activity, id in
            SDKHTTPHost(service: service, activity: activity, runID: id,
                        configuration: try LocalEndpoint(port: 0))
        })
        app.prepare()
        await app.waitUntilPrepared()
        do {
            try #require(app.profile == .offlineDemo)
            try #require(app.server?.phase == .stopped)
            try #require(app.canSwitchSource)
            app.selectSource(.wikipediaEnglish)
            await app.waitUntilPrepared()
            try #require(app.profile == .wikipediaEnglish)
            try #require(app.server?.phase == .stopped)
            try #require(app.server?.endpoint == nil)
            let reader = try #require(app.research)
            try #require(reader.source == .wikipediaEnglish)
            try #require(reader.page == nil && reader.outline == nil && reader.offlineEdit == nil)
            print("LIVE_WIKI source=WikipediaEnglish initial_listener=none")
            try await body(app)
        } catch {
            #expect(await app.quit(waitMilliseconds: 10_000))
            throw error
        }
        try #require(await app.quit(waitMilliseconds: 10_000))
    }

    private func checkOutline(_ outline: Outline, candidatePage: String? = nil) throws {
        let id = outline.snapshot
        try #require(id.project == "enwiki" && id.provider == "mediawiki-rest")
        try #require(SourceProfile.wikipediaEnglish.admits(id))
        try #require((Int64(id.pageID) ?? 0) > 0 && (Int64(id.revisionID) ?? 0) > 0)
        if let candidatePage { try #require(id.pageID == candidatePage) }
        try #require(outline.provenance.identity == id && !outline.provenance.synthetic)
        try #require(outline.provenance.language == "en")
        try #require(!outline.provenance.license.isEmpty && !outline.provenance.retrievedAt.isEmpty)
        let link = try #require(URLComponents(string: outline.provenance.sourceURL))
        try #require(link.scheme == "https" && link.host == "en.wikipedia.org")
        try #require(link.queryItems?.contains { $0.name == "oldid" && $0.value == id.revisionID } == true)
        try #require(!outline.sections.isEmpty)
        try #require(outline.sections.allSatisfy { $0.location.snapshot == id })
    }

    private func checkPassage(_ passage: SectionPassage, outline: Outline, maximumBytes: Int) throws {
        try #require(passage.snapshot == outline.snapshot && passage.provenance.identity == outline.snapshot)
        try #require(!passage.provenance.synthetic && passage.textAvailable)
        try #require(!passage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try #require(passage.text.utf8.count <= maximumBytes)
        try #require(outline.sections.contains { $0.location.partID == passage.selectedPartID })
    }

    private func checkReferences(_ references: SectionReferences, outline: Outline) throws {
        try #require(references.snapshot == outline.snapshot && references.provenance.identity == outline.snapshot)
        try #require(!references.provenance.synthetic && !references.independentlyVerified)
        try #require(references.references.allSatisfy { !$0.synthetic })
        try #require(references.references.count <= 20 && references.associations.count <= 64)
    }

    /// The same ResearchController used by the actual reader; no MCP listener is
    /// involved. Resolve the returned candidate, then read the pinned snapshot.
    @Test func directReaderUsesRealWikipedia() async throws {
        try await withLiveApp { app in
            let reader = try #require(app.research)
            print("LIVE_WIKI direct stage=search")
            reader.query = self.query
            reader.search()
            await reader.waitUntilIdle()
            if let problem = reader.problem { print("LIVE_WIKI direct problem=\(problem.code.rawValue)") }
            try #require(reader.problem == nil)
            let page = try #require(reader.page)
            try #require(page.provider == "mediawiki-rest")
            let candidate = try #require(page.candidates.first {
                $0.title.caseInsensitiveCompare(self.query) == .orderedSame
            }, "Expected the exact article among the returned candidates; no fixture fallback")
            print("LIVE_WIKI direct stage=outline page=\(candidate.pageID) candidates=\(page.candidates.count)")
            reader.open(candidate)
            await reader.waitUntilIdle()
            if let problem = reader.problem { print("LIVE_WIKI direct problem=\(problem.code.rawValue)") }
            try #require(reader.problem == nil)
            let outline = try #require(reader.outline)
            try self.checkOutline(outline, candidatePage: candidate.pageID)
            try #require(reader.presentation.permalink != nil)
            print("LIVE_WIKI direct stage=section revision=\(outline.snapshot.revisionID) sections=\(outline.sections.count)")
            let part = try #require(outline.sections.first?.location)
            reader.read(part)
            await reader.waitUntilIdle()
            if let problem = reader.problem { print("LIVE_WIKI direct problem=\(problem.code.rawValue)") }
            if let problem = reader.referenceProblem { print("LIVE_WIKI direct references_problem=\(problem.code.rawValue)") }
            try #require(reader.problem == nil && reader.referenceProblem == nil)
            let passage = try #require(reader.passage)
            let references = try #require(reader.citations)
            try self.checkPassage(passage, outline: outline, maximumBytes: 32768)
            try #require(passage.selectedPartID == part.partID)
            try self.checkReferences(references, outline: outline)
            // Reference metadata must be present; an uncited section is legal.
            try #require(app.server?.phase == .stopped && app.server?.endpoint == nil)
            let observation = await app.activity.snapshot()
            try #require(!observation.metricsAvailable)
            print("LIVE_WIKI direct verified revision=\(outline.snapshot.revisionID) text_bytes=\(passage.text.utf8.count) refs=\(references.references.count) unresolved=\(references.unresolvedIDs.count)")
        }
        print("LIVE_WIKI DIRECT PASS joined=true")
    }

    /// The built-in Explore MCP action uses the public SDK client and its real
    /// loopback HTTP transport, backed by the same selected live service.
    @Test func guidedMCPUsesRealWikipedia() async throws {
        try await withLiveApp { app in
            print("LIVE_WIKI mcp stage=host_start")
            app.startServer()
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            while app.server?.phase != .running {
                if app.server?.phase == .failed {
                    print("LIVE_WIKI mcp host_failure=\(app.server?.failure?.rawValue ?? "unknown")")
                }
                try #require(ContinuousClock.now < deadline && app.server?.phase != .failed)
                try await Task.sleep(for: .milliseconds(20))
            }
            let run = try #require(app.server?.runID)
            try #require(app.server?.endpoint?.host == "127.0.0.1")
            app.journey.setInspectExchanges(true)
            print("LIVE_WIKI mcp stage=guided_journey")
            app.exploreMCP()
            await app.journey.waitUntilFinished()
            for step in app.journey.steps {
                // Only the controller's owned method/tool/outcome metadata.
                print("LIVE_WIKI mcp step=\(step.method) tool=\(step.tool ?? "-") status=\(step.status.rawValue) ms=\(step.milliseconds)")
            }
            if let problem = app.journey.problem { print("LIVE_WIKI mcp problem=\(problem.code.rawValue)") }
            if let failure = app.journey.steps.last?.failure {
                print("LIVE_WIKI mcp owned_failure=\(failure)")
            }
            try #require(app.journey.phase == .completed)
            try #require(app.journeyOwnerRunID == run && !app.journey.isRunning)
            let steps = app.journey.steps
            try #require(steps.count == 5 && steps.allSatisfy { $0.status == .succeeded && $0.validated })
            let exchanges = app.journey.exchanges
            try #require(exchanges.count >= 6 && exchanges.count <= 32 && app.journey.droppedExchanges == 0)
            try #require(exchanges.first?.method == "server/discover")
            try #require(exchanges.contains { $0.method == "tools/list" })
            try #require(exchanges.filter { $0.method == "tools/call" }.compactMap(\.tool) ==
                         ["search_articles", "get_article_outline", "read_article_section", "get_section_references"])
            try #require(exchanges.allSatisfy { $0.outcome == .response })
            let outline = try #require(app.journey.outline)
            let passage = try #require(app.journey.passage)
            let references = try #require(app.journey.references)
            try self.checkOutline(outline)
            try self.checkPassage(passage, outline: outline, maximumBytes: 4096)
            try self.checkReferences(references, outline: outline)
            let observation = await app.activity.snapshot()
            try #require(observation.runID == run && observation.active == 0)
            try #require(observation.completed == 4 && observation.failed == 0 && observation.cancelled == 0)
            try #require(!observation.metricsPartial)
            print("LIVE_WIKI mcp verified page=\(outline.snapshot.pageID) revision=\(outline.snapshot.revisionID) exchanges=\(exchanges.count) terminal_handlers=\(observation.completed) text_bytes=\(passage.text.utf8.count) refs=\(references.references.count) unresolved=\(references.unresolvedIDs.count)")
        }
        print("LIVE_WIKI MCP PASS joined=true")
    }

    /// R1–R3: user-selected live research through the actual interactive MCP
    /// route, one related-title search, then export the previously pinned evidence.
    @Test func interactiveLiveResearchCollectsEvidence() async throws {
        try await withLiveApp { app in
            print("LIVE_WIKI interactive stage=host_start")
            app.startServer()
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            while app.server?.phase != .running {
                try #require(ContinuousClock.now < deadline && app.server?.phase != .failed)
                try await Task.sleep(for: .milliseconds(20))
            }
            app.selectResearchMode(.mcp)
            await app.waitUntilPrepared()
            try #require(app.researchMode == .mcp && app.researchRouteReady)
            let reader = try #require(app.research)
            reader.query = self.query
            reader.search(); await reader.waitUntilIdle()
            if let problem = reader.problem { print("LIVE_WIKI interactive search_problem=\(problem.code.rawValue)") }
            let candidate = try #require(reader.page?.candidates.first {
                $0.title.caseInsensitiveCompare(self.query) == .orderedSame
            })
            reader.open(candidate); await reader.waitUntilIdle()
            if let problem = reader.problem { print("LIVE_WIKI interactive outline_problem=\(problem.code.rawValue)") }
            let outline = try #require(reader.outline)
            try self.checkOutline(outline, candidatePage: candidate.pageID)
            let part = try #require(outline.sections.first?.location)
            reader.read(part); await reader.waitUntilIdle()
            if let problem = reader.problem { print("LIVE_WIKI interactive section_problem=\(problem.code.rawValue)") }
            try #require(reader.phase == .section && reader.problem == nil && reader.referenceProblem == nil)
            let passage = try #require(reader.passage)
            let refs = try #require(reader.citations)
            try self.checkPassage(passage, outline: outline, maximumBytes: 32768)
            try self.checkReferences(refs, outline: outline)
            let related = try #require(passage.relatedKnowledge)
            try #require(related.isAdmitted)
            let title = try #require(related.titles.first, "The selected live article must contain a retained eligible related title")
            let first = await app.activity.snapshot()
            try #require(first.completed == 4 && first.failed == 0 && !first.metricsPartial)
            try #require(!first.events.contains { $0.origin == .localResearch })
            app.collectEvidence()
            let evidence = try #require(app.collection.entries.first)
            try #require(evidence.location == part && evidence.route == .mcp)
            app.collectEvidence()
            try #require(app.collection.entries.count == 1)
            app.updateEvidenceNote("Research qualification note", id: evidence.id)
            // A related link is an explicit search hint, not a direct arbitrary URL fetch.
            reader.query = title
            reader.search(); await reader.waitUntilIdle()
            if let problem = reader.problem { print("LIVE_WIKI interactive related_problem=\(problem.code.rawValue)") }
            try #require(reader.problem == nil && reader.page?.provider == "mediawiki-rest")
            try #require(reader.page?.query == title)
            let next = await app.activity.snapshot()
            try #require(next.completed == 5 && next.failed == 0 && !next.metricsPartial)
            app.selectResearchMode(.direct); await app.waitUntilPrepared()
            try #require(app.researchMode == .direct && app.collection.entries.count == 1)
            try #require(app.collection.entries.first?.location == part)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let writer = ActivityExportWriter()
            for format in ResearchCollection.Format.allCases {
                let url = directory.appendingPathComponent("evidence." + format.fileExtension)
                try await writer.writeCollection(app.collection, format: format, to: url)
                let exported = try Data(contentsOf: url)
                try #require(!exported.isEmpty && exported.count <= ResearchCollection.maximumExportBytes)
                let content = String(decoding: exported, as: UTF8.self)
                try #require(content.contains(outline.snapshot.revisionID) && content.contains("Research qualification note"))
            }
            print("LIVE_WIKI interactive verified revision=\(outline.snapshot.revisionID) related_titles=\(related.titles.count) terminal_handlers=\(next.completed) collection_entries=\(app.collection.entries.count) formats=2")
        }
        print("LIVE_WIKI INTERACTIVE PASS joined=true")
    }

    /// R4a uses the existing app reader and real public history endpoint.
    /// History never replaces the already admitted article or section.
    @Test func directReaderExploresRevisionHistory() async throws {
        try await withLiveApp { app in
            let reader = try #require(app.research)
            try #require(reader.supportsRevisionHistory && app.researchMode == .direct)
            reader.query = self.query
            reader.search(); await reader.waitUntilIdle()
            let candidate = try #require(reader.page?.candidates.first {
                $0.title.caseInsensitiveCompare(self.query) == .orderedSame
            })
            reader.open(candidate); await reader.waitUntilIdle()
            let outline = try #require(reader.outline)
            let part = try #require(outline.sections.first?.location)
            reader.read(part); await reader.waitUntilIdle()
            try #require(reader.phase == .section && reader.problem == nil)
            let passage = try #require(reader.passage)
            let oldReferenceProblem = reader.referenceProblem?.code
            let oldReferences = reader.citations?.references.count
            print("LIVE_WIKI history stage=recent revision=\(outline.snapshot.revisionID)")
            reader.loadRevisionHistory()
            await reader.waitUntilIdle()
            if let problem = reader.revisionHistoryProblem { print("LIVE_WIKI history problem=\(problem.code.rawValue)") }
            try #require(reader.revisionHistoryProblem == nil)
            let history = try #require(reader.revisionHistory)
            try #require(!history.entries.isEmpty && history.entries.count <= 20)
            try #require(history.requestedSnapshot == outline.snapshot)
            try #require(history.entries.allSatisfy { $0.permalink?.host == "en.wikipedia.org" })
            var loadedOlder = false
            if let cursor = history.olderCursor {
                print("LIVE_WIKI history stage=older cursor=\(cursor)")
                reader.loadRevisionHistory(older: true); await reader.waitUntilIdle()
                if let problem = reader.revisionHistoryProblem { print("LIVE_WIKI history older_problem=\(problem.code.rawValue)") }
                try #require(reader.revisionHistoryProblem == nil)
                let older = try #require(reader.revisionHistory)
                try #require(!older.entries.contains { $0.revisionID == cursor })
                try #require(older.entries.count <= 20)
                loadedOlder = true
            }
            try #require(reader.outline?.snapshot == outline.snapshot && reader.selectedPart == part)
            try #require(reader.passage?.text == passage.text && reader.passage?.snapshot == passage.snapshot)
            try #require(reader.citations?.references.count == oldReferences && reader.referenceProblem?.code == oldReferenceProblem)
            try #require(app.server?.phase == .stopped && app.server?.endpoint == nil)
            let observation = await app.activity.snapshot()
            try #require(!observation.metricsAvailable)
            try #require(observation.events.contains { $0.origin == .localResearch && $0.operation == "get_article_history" })
            print("LIVE_WIKI history verified rows=\(history.entries.count) older_loaded=\(loadedOlder) pinned=\(outline.snapshot.revisionID)")
        }
        print("LIVE_WIKI HISTORY PASS joined=true")
    }

    /// R4b: independently resolve one real historical revision and compare
    /// separately chosen sections before adopting its exact cached identity.
    @Test func directReaderReadsHistoricalRevision() async throws {
        try await withLiveApp { app in
            let reader = try #require(app.research)
            reader.query = self.query; reader.search(); await reader.waitUntilIdle()
            let candidate = try #require(reader.page?.candidates.first { $0.title.caseInsensitiveCompare(self.query) == .orderedSame })
            reader.open(candidate); await reader.waitUntilIdle()
            let pinned = try #require(reader.outline)
            let part = try #require(pinned.sections.first?.location)
            reader.read(part); await reader.waitUntilIdle()
            let original = try #require(reader.passage)
            reader.loadRevisionHistory(); await reader.waitUntilIdle()
            let history = try #require(reader.revisionHistory)
            let entry = try #require(history.entries.first { $0.revisionID != pinned.snapshot.revisionID })
            print("LIVE_WIKI historical stage=preview page=\(pinned.snapshot.pageID) pinned=\(pinned.snapshot.revisionID) requested=\(entry.revisionID)")
            reader.previewHistoricalRevision(entry); await reader.waitUntilIdle()
            if let problem = reader.revisionHistoryProblem { print("LIVE_WIKI historical problem=\(problem.code.rawValue)") }
            try #require(reader.revisionHistoryProblem == nil)
            let preview = try #require(reader.historicalPreview)
            let expected = HistoricalRevisionInput(pinned: pinned.snapshot, revisionID: entry.revisionID).expectedSnapshot
            try #require(preview.outline.snapshot == expected)
            try self.checkOutline(preview.outline, candidatePage: pinned.snapshot.pageID)
            let olderPart = try #require(preview.outline.sections.first?.location)
            reader.readHistoricalSection(olderPart); await reader.waitUntilIdle()
            let older = try #require(reader.historicalPreview?.passage)
            try self.checkPassage(older, outline: preview.outline, maximumBytes: 8192)
            try #require(reader.outline?.snapshot == pinned.snapshot && reader.passage?.text == original.text)
            reader.adoptHistoricalRevision()
            try #require(reader.outline?.snapshot == expected && reader.selectedPart == nil && reader.isReadingHistoricalRevision)
            reader.read(olderPart); await reader.waitUntilIdle()
            try #require(reader.passage?.snapshot == expected)
            if !HistoricalRevisionLicense.permitsCollection(older.provenance) {
                try #require(!app.canCollectEvidence)
            }
            reader.refreshOutline(); await reader.waitUntilIdle()
            try #require(reader.outline?.snapshot == expected && reader.problem == nil)
            let observation = await app.activity.snapshot()
            try #require(!observation.metricsAvailable && app.server?.phase == .stopped)
            print("LIVE_WIKI historical verified revision=\(expected.revisionID) text_bytes=\(older.text.utf8.count) shareable=\(HistoricalRevisionLicense.permitsCollection(older.provenance))")
        }
        print("LIVE_WIKI HISTORICAL PASS joined=true")
    }
}
