// SPDX-License-Identifier: Apache-2.0
import Foundation
import Observation
import ExplorerDomain
import ExplorerMCP

/// Main-actor owner of interactive research state and revision-pinned presentation.
@MainActor @Observable public final class ResearchController {
    public let source: ResearchSource
    public var query = ""
    public private(set) var phase = ResearchPhase.idle
    public private(set) var page: SearchPage?
    public private(set) var candidate: Candidate?
    public private(set) var outline: Outline?
    public private(set) var selectedPart: PartLocation?
    public private(set) var passage: SectionPassage?
    public private(set) var citations: SectionReferences?
    public private(set) var problem: ExplorerProblem?
    public private(set) var referenceProblem: ExplorerProblem?
    /// Explicit revision check; never replaces `outline`, `passage` or `citations`.
    public private(set) var comparison: RevisionComparison?
    /// One title-addressed segment for the current article; never a replacement snapshot.
    public private(set) var revisionHistory: RevisionHistoryPage?
    public private(set) var revisionHistoryProblem: ExplorerProblem?
    public private(set) var loadingRevisionHistory = false
    public private(set) var historicalPreview: HistoricalResearchPreview?
    private var adoptedHistoricalInput: HistoricalRevisionInput?
    public var isReadingHistoricalRevision: Bool { adoptedHistoricalInput != nil }
    public var supportsRevisionHistory: Bool { source == .wikipediaEnglish && client is any RevisionHistoryClient }
    /// Present only for the offline demo source.
    public let offlineEdit: OfflineRevisionEdit?
    public private(set) var offlineEditPublished = false
    public var isBusy: Bool { [.searching, .opening, .reading, .references, .comparing, .publishing].contains(phase) }
    @ObservationIgnored private let client: any ResearchClient
    @ObservationIgnored private let record: @Sendable (String, Bool) async -> Void
    private enum Action {
        case search(String), open(Candidate), read(Outline, PartLocation), tour
        case compare(Candidate, Outline, PartLocation?), publishEdit
        case history(RevisionHistoryInput)
        case historical(HistoricalRevisionInput)
        case reopenHistorical(HistoricalRevisionInput)
        case historicalSection(pinned: SnapshotID, preview: Outline, part: PartLocation)
    }
    @ObservationIgnored private var pending: (UInt64, Action)?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var driver: Task<Void, Never>?
    @ObservationIgnored private var closed = false

    public init(client: any ResearchClient, source: ResearchSource = .offlineDemo, record: @escaping @Sendable (String, Bool) async -> Void = { _, _ in },
                offlineEdit: OfflineRevisionEdit? = nil) {
        self.client = client; self.source = source; self.record = record
        // A simulated edit is meaningful only for fictional data; live sources change upstream.
        self.offlineEdit = source == .offlineDemo ? offlineEdit : nil
    }
    public func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, q.utf8.count <= 256 else {
            cancel(); problem = PublicProblems.project(.invalidArguments); phase = .problem; return
        }
        clearRevisionHistory()
        candidate = nil; outline = nil; selectedPart = nil; passage = nil; citations = nil; comparison = nil
        enqueue(.search(q), phase: .searching)
    }
    public func open(_ candidate: Candidate) {
        clearRevisionHistory()
        self.candidate = candidate; outline = nil; selectedPart = nil; passage = nil; citations = nil; comparison = nil
        enqueue(.open(candidate), phase: .opening)
    }
    /// One click: search the collection, open the Observatory and read its telescope section with
    /// references. Offline demo only; it never reaches a live provider.
    public func exploreOfflineCollection() {
        guard source == .offlineDemo else { return }
        query = OfflineTour.query
        page = nil; candidate = nil; outline = nil; selectedPart = nil; passage = nil; citations = nil; comparison = nil
        enqueue(.tour, phase: .searching)
    }
    /// Loads one history segment without replacing the pinned article or its citations.
    /// Older pages are requested explicitly using the last admitted row's ID.
    public func loadRevisionHistory(older: Bool = false) {
        guard !closed, !isBusy, supportsRevisionHistory, let candidate, let outline,
              candidate.pageID == outline.snapshot.pageID else { return }
        let cursor = older ? revisionHistory?.olderCursor : nil
        if older && (cursor == nil || revisionHistory?.requestedSnapshot != outline.snapshot) { return }
        revisionHistoryProblem = nil
        enqueue(.history(.init(candidateID: candidate.id, snapshot: outline.snapshot, olderThan: cursor)), phase: .comparing, preserveResearchProblems: true)
    }

    /// Load only a row returned in the currently displayed history segment.
    public func previewHistoricalRevision(_ entry: RevisionHistoryEntry) {
        guard !closed, !isBusy, supportsRevisionHistory, let outline,
              let history = revisionHistory, history.requestedSnapshot == outline.snapshot,
              history.entries.contains(entry) else { return }
        let input = HistoricalRevisionInput(pinned: outline.snapshot, revisionID: entry.revisionID)
        guard input.isAdmitted else { return }
        historicalPreview = nil; revisionHistoryProblem = nil
        enqueue(.historical(input), phase: .comparing, preserveResearchProblems: true)
    }

    /// Select a section of the historical outline independently of the pinned
    /// reader. Ordinal part IDs never imply cross-revision correspondence.
    public func readHistoricalSection(_ part: PartLocation) {
        guard !closed, !isBusy, let outline, let preview = historicalPreview?.outline,
              preview.sections.contains(where: { $0.location == part }) else { return }
        historicalPreview = .init(outline: preview)
        revisionHistoryProblem = nil
        enqueue(.historicalSection(pinned: outline.snapshot, preview: preview, part: part),
                phase: .comparing, preserveResearchProblems: true)
    }

    /// Explicitly adopt the verified historical outline in the ordinary reader.
    /// No current revision is silently substituted and no section is mapped.
    public func adoptHistoricalRevision() {
        guard !closed, !isBusy, let preview = historicalPreview?.outline, let outline,
              preview.snapshot.pageID == outline.snapshot.pageID,
              preview.snapshot != outline.snapshot else { return }
        let input = HistoricalRevisionInput(pinned: outline.snapshot, revisionID: preview.snapshot.revisionID)
        guard input.isAdmitted, input.expectedSnapshot == preview.snapshot else { return }
        clearRevisionHistory()
        adoptedHistoricalInput = input
        self.outline = preview; selectedPart = nil; passage = nil; citations = nil
        comparison = nil; problem = nil; referenceProblem = nil; phase = .outline
    }

    private func clearRevisionHistory() {
        revisionHistory = nil; revisionHistoryProblem = nil; loadingRevisionHistory = false; historicalPreview = nil; adoptedHistoricalInput = nil
    }

    /// Explicitly asks the source for the candidate's current revision and, when it differs,
    /// compares the selected section. The pinned revision stays what the reader shows.
    public func compareWithLatestRevision() {
        guard !isBusy, let candidate, let outline else { return }
        comparison = nil
        enqueue(.compare(candidate, outline, selectedPart), phase: .comparing)
    }
    /// Switches the reader to the compared latest revision: an explicit user decision.
    public func adoptLatestRevision() {
        guard !isBusy, let comparison, !comparison.latestIsPinned, outline?.snapshot == comparison.pinned else { return }
        let part = comparison.partID.flatMap { id in comparison.latest.sections.first { $0.location.partID == id }?.location }
        clearRevisionHistory()
        outline = comparison.latest; self.comparison = nil
        selectedPart = nil; passage = nil; citations = nil; problem = nil; referenceProblem = nil; phase = .outline
        if let part { read(part) }
    }
    /// Offline demo only: publishes the prepared upstream edit. Open outlines remain pinned.
    public func publishOfflineEdit() {
        guard !isBusy, offlineEdit != nil, !offlineEditPublished else { return }
        enqueue(.publishEdit, phase: .publishing)
    }
    public func read(_ part: PartLocation) {
        guard let outline, outline.snapshot == part.snapshot,
              outline.sections.contains(where: { $0.location == part }) else {
            cancel(); problem = PublicProblems.project(.revisionMismatch); phase = .problem; return
        }
        selectedPart = part; passage = nil; citations = nil; comparison = nil
        enqueue(.read(outline, part), phase: .reading)
    }
    public func back() {
        cancel(); clearRevisionHistory(); candidate = nil; outline = nil; passage = nil; citations = nil; selectedPart = nil; comparison = nil
        problem = nil; referenceProblem = nil; phase = page == nil ? .idle : .candidates
    }
    public func refreshOutline() {
        if let input = adoptedHistoricalInput {
            guard !closed, !isBusy, outline?.snapshot == input.expectedSnapshot else { return }
            enqueue(.reopenHistorical(input), phase: .opening)
        } else if let candidate { open(candidate) }
    }
    public func cancel() {
        generation &+= 1; pending = nil; worker?.cancel()
        let wasHistory = loadingRevisionHistory
        loadingRevisionHistory = false
        if wasHistory { phase = restingPhase() }
        else if isBusy { phase = .cancelled }
    }
    public func waitUntilIdle() async { await driver?.value }
    public func shutdown() async { closed = true; cancel(); await driver?.value }

    // One driver, one worker and one replacement, regardless of click rate.
    // Superseded work is cancelled AND joined before the next service operation.
    private func enqueue(_ action: Action, phase: ResearchPhase, preserveResearchProblems: Bool = false) {
        guard !closed else { return }
        generation &+= 1; pending = (generation, action); worker?.cancel()
        switch action {
        case .history, .historical, .historicalSection: loadingRevisionHistory = true
        default: loadingRevisionHistory = false
        }
        if !preserveResearchProblems { problem = nil; referenceProblem = nil }
        self.phase = phase
        guard driver == nil else { return }
        driver = Task { [self] in
            while let (token, action) = pending {
                pending = nil
                let task = Task { await self.perform(action, token: token) }
                worker = task; await task.value; worker = nil
            }
            driver = nil
        }
    }
    private func current(_ token: UInt64) -> Bool { token == generation && !closed && !Task.isCancelled }
    private func perform(_ action: Action, token: UInt64) async {
        // Multi-step actions record each completed step; `operation` names the step in progress.
        var operation = ""
        do {
            switch action {
            case .search(let q):
                operation = "search_articles"
                let result = try await client.search(.init(query: q, project: source.project, limit: 10))
                guard current(token) else { return }
                page = result; phase = result.candidates.isEmpty ? .empty : .candidates
            case .open(let candidate):
                operation = "get_article_outline"
                let result = try await client.outline(.init(project: candidate.project, candidateID: candidate.id))
                guard current(token), self.candidate == candidate else { return }
                outline = result; phase = .outline
            case .read(let outline, let part):
                operation = "read_article_section"
                guard try await readSection(outline, part, token: token) else { return }
            case .tour:
                operation = "search_articles"
                let result = try await client.search(.init(query: OfflineTour.query, project: source.project, limit: 10))
                guard current(token) else { return }
                page = result
                guard let candidate = result.candidates.first(where: { $0.id == OfflineTour.candidateID }) else {
                    throw PublicProblems.project(.unknownCandidate)
                }
                await record(operation, true)
                operation = "get_article_outline"; self.candidate = candidate; phase = .opening
                let opened = try await client.outline(.init(project: candidate.project, candidateID: candidate.id))
                guard current(token) else { return }
                outline = opened; phase = .outline
                guard let part = opened.sections.first(where: { $0.location.partID == OfflineTour.partID })?.location else {
                    throw PublicProblems.project(.absentSection)
                }
                await record(operation, true)
                operation = "read_article_section"; selectedPart = part; phase = .reading
                guard try await readSection(opened, part, token: token) else { return }
            case .history(let input):
                operation = "get_article_history"
                do {
                    guard let historyClient = client as? any RevisionHistoryClient else { throw source.problem(.unsupportedVariant) }
                    let result = try await historyClient.history(input)
                    guard current(token), outline?.snapshot == input.snapshot, candidate?.id == input.candidateID else { return }
                    guard result.isAdmitted(for: input) else { throw source.problem(.unsupportedVariant) }
                    revisionHistory = result; loadingRevisionHistory = false; phase = restingPhase()
                } catch is CancellationError { throw CancellationError() }
                catch {
                    guard current(token) else { return }
                    revisionHistoryProblem = publicProblem(error)
                    loadingRevisionHistory = false; phase = restingPhase()
                    await record(operation, false)
                    return
                }
            case .reopenHistorical(let input):
                operation = "open_historical_revision"
                guard let historicalClient = client as? any RevisionHistoryClient else { throw source.problem(.unsupportedVariant) }
                let result = try await historicalClient.historicalOutline(input)
                guard current(token), outline?.snapshot == input.expectedSnapshot else { return }
                guard result.snapshot == input.expectedSnapshot, result.provenance.identity == result.snapshot,
                      result.sections.allSatisfy({ $0.location.snapshot == result.snapshot }) else { throw source.problem(.revisionMismatch) }
                outline = result; selectedPart = nil; passage = nil; citations = nil
                historicalPreview = nil; comparison = nil; phase = .outline
            case .historical(let input):
                operation = "open_historical_revision"
                do {
                    guard let historicalClient = client as? any RevisionHistoryClient else { throw source.problem(.unsupportedVariant) }
                    let result = try await historicalClient.historicalOutline(input)
                    guard current(token), outline?.snapshot == input.pinned else { return }
                    guard result.snapshot == input.expectedSnapshot, result.provenance.identity == result.snapshot,
                          result.sections.allSatisfy({ $0.location.snapshot == result.snapshot }) else {
                        throw source.problem(.revisionMismatch)
                    }
                    historicalPreview = .init(outline: result)
                    loadingRevisionHistory = false; phase = restingPhase()
                } catch is CancellationError { throw CancellationError() }
                catch {
                    guard current(token) else { return }
                    revisionHistoryProblem = publicProblem(error)
                    loadingRevisionHistory = false; phase = restingPhase()
                    await record(operation, false); return
                }
            case .historicalSection(let pinned, let preview, let part):
                operation = "read_historical_section"
                do {
                    let result = try await client.section(.init(snapshot: preview.snapshot, part: part, maxTextBytes: 8192))
                    guard current(token), outline?.snapshot == pinned,
                          historicalPreview?.outline.snapshot == preview.snapshot else { return }
                    guard result.snapshot == preview.snapshot, result.provenance.identity == preview.snapshot,
                          result.selectedPartID == part.partID else { throw source.problem(.revisionMismatch) }
                    historicalPreview = .init(outline: preview, passage: result)
                    loadingRevisionHistory = false; phase = restingPhase()
                } catch is CancellationError { throw CancellationError() }
                catch {
                    guard current(token) else { return }
                    revisionHistoryProblem = publicProblem(error)
                    loadingRevisionHistory = false; phase = restingPhase()
                    await record(operation, false); return
                }
            case .compare(let candidate, let pinned, let part):
                operation = "get_article_outline"
                let latest = try await client.outline(.init(project: candidate.project, candidateID: candidate.id))
                guard current(token) else { return }
                var passage = RevisionComparison.Passage.notCompared
                // Live normalizer part IDs are ordinals within a revision.
                // They cannot establish semantic section correspondence across revisions.
                if source == .offlineDemo, let part, latest.snapshot != pinned.snapshot {
                    await record(operation, true)
                    operation = "read_article_section"
                    // Re-read the pinned text from its own snapshot: an expired pin is reported, not replaced.
                    let old = try await client.section(.init(snapshot: pinned.snapshot, part: part, maxTextBytes: 32768))
                    if let moved = latest.sections.first(where: { $0.location.partID == part.partID })?.location {
                        let new = try await client.section(.init(snapshot: latest.snapshot, part: moved, maxTextBytes: 32768))
                        passage = old.text == new.text ? .unchanged(new.text) : .changed(pinned: old.text, latest: new.text)
                    } else { passage = .absentInLatest }
                }
                guard current(token), outline?.snapshot == pinned.snapshot, selectedPart == part else { return }
                comparison = .init(pinned: pinned.snapshot, latest: latest,
                                   partID: source == .offlineDemo ? part?.partID : nil, passage: passage)
                phase = restingPhase()
            case .publishEdit:
                await offlineEdit?.publish()
                offlineEditPublished = true // the source changed even if this action was superseded
                guard current(token) else { return }
                phase = restingPhase()
            }
            if !operation.isEmpty { await record(operation, true) }
        } catch is CancellationError {
            if token == generation, !closed {
                let wasHistory = loadingRevisionHistory
                loadingRevisionHistory = false
                phase = wasHistory ? restingPhase() : .cancelled
            }
            if !operation.isEmpty { await record(operation, false) }
        } catch {
            guard current(token) else { return }
            problem = publicProblem(error); phase = .problem
            if !operation.isEmpty { await record(operation, false) }
        }
    }
    /// False when superseded: nothing landed and the step is not recorded as completed.
    private func readSection(_ outline: Outline, _ part: PartLocation, token: UInt64) async throws -> Bool {
        let text = try await client.section(.init(snapshot: outline.snapshot, part: part, maxTextBytes: 32768))
        guard current(token), self.outline?.snapshot == outline.snapshot, selectedPart == part else { return false }
        passage = text; phase = .references
        do {
            let refs = try await client.references(.init(snapshot: outline.snapshot, part: part))
            guard current(token), selectedPart == part else { return false }
            citations = refs; phase = .section
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard current(token) else { return false }
            referenceProblem = publicProblem(error); phase = .section
        }
        return true
    }
    private func restingPhase() -> ResearchPhase {
        if passage != nil || citations != nil || referenceProblem != nil { return .section }
        if outline != nil { return .outline }
        if let page { return page.candidates.isEmpty ? .empty : .candidates }
        return .idle
    }
    private func publicProblem(_ error: any Error) -> ExplorerProblem {
        if let failure = error as? MCPResearchFailure {
            return .init(.upstreamUnavailable, "MCP research failed.", recovery: MCPJourneyController.describe(failure))
        }
        return source.problem((error as? ExplorerProblem)?.code ?? .upstreamUnavailable)
    }
}
