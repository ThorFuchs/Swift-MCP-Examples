// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import ExplorerDomain
@testable import WikimediaAccess

private actor ReplayTransport: LiveTransport {
    var replies: [LiveHTTPResponse]; private(set) var urls: [URL] = []
    init(_ replies: [LiveHTTPResponse]) { self.replies = replies }
    func get(_ url: URL, deadline: ContinuousClock.Instant) throws -> LiveHTTPResponse {
        urls.append(url); guard !replies.isEmpty else { throw LiveFailure.malformed }; return replies.removeFirst()
    }
    var count: Int { urls.count }
}
private let searchWire = #"{"pages":[{"id":11,"key":"Test/Page%?#é","title":"Test","description":null}]}"#
private func response(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> LiveHTTPResponse {
    .init(status: status, body: Data(body.utf8), headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a })
}
// Synthetic REST and DOM fixture, not an upstream payload capture.
private func pageWire(html: String, id: Int64 = 11, revision: Int64 = 22) throws -> RESTPage {
    struct Envelope: Encodable, Sendable {
        struct Revision: Encodable, Sendable { let id: Int64; let timestamp = "2026-10-21T00:00:00Z" }
        struct License: Encodable, Sendable { let url = "https://creativecommons.org/licenses/by-sa/4.0/"; let title = "CC BY-SA 4.0" }
        let id: Int64; let key = "Test"; let title = "Test"; let latest: Revision
        let content_model = "wikitext"; let license = License(); let html: String
    }
    let value = try JSONValueEncoder().encodeWithReport(Envelope(id: id, latest: .init(id: revision), html: html)).result
    return try JSONValueDecoder().decodeWithReport(RESTPage.self, from: value).result
}
import JSON
private func html(_ content: String, revision: Int = 22, version: String = "2.8.0") -> String {
    "<html about='//en.wikipedia.org/wiki/Special:Redirect/revision/\(revision)'><head><meta property='mw:htmlVersion' content='\(version)'><meta property='mw:pageId' content='11'></head><body data-mw-html-version='\(version)'>\(content)</body></html>"
}
@Suite struct LiveProviderTests {
    @Test func titleSegmentAndRedirectOriginAreExact() throws {
        let page = try WikipediaRoute.page("a/b%?#é")
        #expect(page.absoluteString.hasSuffix("a%2Fb%25%3F%23%C3%A9/with_html"))
        #expect(WikipediaRoute.allowed(page))
        for bad in ["http://en.wikipedia.org/w/rest.php/v1/search/page?q=x&limit=1", "https://en.wikipedia.org.evil/w/rest.php/v1/page/A/with_html", "https://u@en.wikipedia.org/w/rest.php/v1/page/A/with_html", "https://en.wikipedia.org:443/w/rest.php/v1/page/A/with_html", "https://en.wikipedia.org/wiki/A"] {
            #expect(!WikipediaRoute.allowed(URL(string: bad)!))
        }
    }
    @Test func searchIsNotStartupAndOnlyOpaqueAdmittedCandidatesResolve() async throws {
        let transport = ReplayTransport([response(searchWire)])
        let provider = WikipediaProvider(transport: transport)
        #expect(await transport.count == 0)
        let result = try await provider.search(query: "Test", project: "enwiki", limit: 1)
        #expect(result.provider == "mediawiki-rest" && result.truncated)
        let candidate = try #require(result.candidates.first)
        #expect(candidate.id.hasPrefix("c_") && !candidate.id.contains("Test"))
        await #expect(throws: ExplorerProblem.self) { try await provider.resolve(candidateID: "foreign", project: "enwiki") }
        #expect(await transport.count == 1)
    }
    @Test func retryOnlyPermittedStatusesWithinAttemptCeiling() async throws {
        let transport = ReplayTransport([response("{}", status: 429, headers: ["Retry-After": "0"]), response(searchWire)])
        let result = try await WikipediaProvider(transport: transport).search(query: "Test", project: "enwiki", limit: 1)
        #expect(result.candidates.count == 1)
        let denied = ReplayTransport([response("{}", status: 503, headers: ["Retry-After": "3"])])
        do { _ = try await WikipediaProvider(transport: denied).search(query: "Test", project: "enwiki", limit: 1); Issue.record("Expected unavailable") }
        catch let error as ExplorerProblem { #expect(error.code == .upstreamUnavailable) }
        #expect(await denied.count == 1)
    }
    @Test func malformedMissingAndEmptyAreDistinct() async throws {
        let empty = WikipediaProvider(transport: ReplayTransport([response(#"{"pages":[]}"#)]))
        #expect(try await empty.search(query: "Test", project: "enwiki", limit: 1).candidates.isEmpty)
        for (body, status, expected) in [("broken", 200, ExplorerProblem.Code.upstreamUnavailable), ("{}", 404, .absentPage)] {
            do { _ = try await WikipediaProvider(transport: ReplayTransport([response(body, status: status)])).search(query: "Test", project: "enwiki", limit: 1); Issue.record("Expected typed failure") }
            catch let error as ExplorerProblem { #expect(error.code == expected) }
        }
    }
    @Test func bodyAdmissionDoesNotTrustInjectedTransport() async throws {
        let value = LiveHTTPResponse(status: 200, body: Data(repeating: 32, count: 4_194_305), headers: ["Content-Type": "application/json"])
        do { _ = try await WikipediaProvider(transport: ReplayTransport([value])).search(query: "x", project: "enwiki", limit: 1); Issue.record("Expected cap") }
        catch let error as ExplorerProblem { #expect(error.code == .budgetExceeded) }
    }
    @Test func nestedOwnTextCitationsUnicodeAndProvenance() async throws {
        let page = try pageWire(html: html("<section data-mw-section-id='0'><p>Lead &amp; café</p><section data-mw-section-id='-1'><h2>Child</h2><p>Child text<sup class='mw-ref'><a href='./Test#cite_note-x'>[1]</a></sup></p></section><ol class='references'><li id='cite_note-x'><span class='mw-cite-backlink'>↑</span><span class='mw-reference-text'>Source title</span></li></ol><script>bad()</script><table><tr><td>table omitted</td></tr></table></section>"))
        let (snapshot, evidence) = try await MediaWikiNormalizer().normalize(page, retrievedAt: Date(), limits: ExplorerLimits())
        #expect(snapshot.parts.count == 2)
        #expect(snapshot.parts[1].parentID == snapshot.parts[0].id)
        #expect(snapshot.parts[0].text?.contains("café") == true)
        #expect(snapshot.parts[0].text?.contains("Child text") == false)
        #expect(snapshot.parts[0].text?.contains("Source title") == false)
        #expect(snapshot.parts[1].citations == ["r0"])
        #expect(snapshot.references?.first?.title == "Source title")
        #expect(!snapshot.provenance.synthetic && snapshot.provenance.language == "en")
        #expect(snapshot.provenance.sourceURL.contains("oldid=22"))
        #expect(evidence.htmlVersion == "2.8.0" && evidence.htmlSHA256.count == 64)
    }
    @Test func relatedKnowledgeIsBoundedScopedAndDoesNotFetchTargets() async throws {
        let links = (0..<16).map { "<a rel='mw:WikiLink' href='./Topic_\($0)'>topic</a>" }.joined()
        let page = try pageWire(html: html("<section data-mw-section-id='0'><p>" + links
            + "<a rel='mw:WikiLink' href='./Topic_0#section'>duplicate</a>"
            + "<a rel='mw:WikiLink' href='./File:Image'>file</a>"
            + "<a rel='mw:WikiLink' href='https://evil.example/wiki/Injected'>external</a>"
            + "<a rel='mw:WikiLink' href='./Test'>self</a>"
            + "<a href='./NotMarked'>ordinary anchor</a>"
            + "</p><section data-mw-section-id='1'><p><a rel='mw:WikiLink' href='./Caf%C3%A9'>child</a></p></section></section>"))
        let (snapshot, _) = try await MediaWikiNormalizer().normalize(page, retrievedAt: Date(), limits: ExplorerLimits())
        let root = try #require(snapshot.parts.first?.relatedKnowledge)
        #expect(root.titles == (0..<12).map { "Topic \($0)" } && root.truncated)
        #expect(snapshot.parts[1].relatedKnowledge?.titles == ["Café"])
        let passage = try SnapshotProjection.section(snapshot, part: .init(snapshot: snapshot.provenance.identity, partID: snapshot.parts[0].id), maximumBytes: 4096)
        #expect(passage.relatedKnowledge == root)
        #expect(passage.text.contains("child"))
    }


    @Test func historyUsesOnlyAdmittedCandidateAndNumericCursor() async throws {
        let wire = #"{"revisions":[{"id":22,"timestamp":"2026-10-21T00:00:00Z","size":100,"delta":-5,"minor":true,"user":{"name":"not retained"},"comment":"not retained"},{"id":21,"timestamp":"2026-10-20T00:00:00Z","size":105,"delta":null,"minor":false}],"older":"https://evil.example/never-follow"}"#
        let older = #"{"revisions":[{"id":20,"timestamp":"2026-10-19T00:00:00Z","size":90,"delta":null,"minor":false}]}"#
        let transport = ReplayTransport([response(searchWire), response(wire), response(older)])
        let provider = WikipediaProvider(transport: transport)
        let candidate = try #require(try await provider.search(query: "Test", project: "enwiki", limit: 1).candidates.first)
        let snapshot = SnapshotID(provider: "mediawiki-rest", project: "enwiki", pageID: "11", revisionID: "22", normalizerVersion: "mediawiki-html-1")
        let input = RevisionHistoryInput(candidateID: candidate.id, snapshot: snapshot)
        let page = try await provider.history(input)
        #expect(page.entries.map(\.revisionID) == ["22", "21"] && page.olderCursor == "21")
        #expect(page.entries[0].delta == -5 && page.entries[1].delta == nil && page.entries[0].minor)
        #expect(page.requestedSnapshot == snapshot)
        let next = try await provider.history(.init(candidateID: candidate.id, snapshot: snapshot, olderThan: page.olderCursor))
        #expect(next.entries.map(\.revisionID) == ["20"] && next.olderCursor == nil)
        let urls = await transport.urls
        #expect(urls.count == 3)
        #expect(urls[1] == (try WikipediaRoute.history("Test/Page%?#é")))
        #expect(urls[2] == (try WikipediaRoute.history("Test/Page%?#é", olderThan: "21")))
        #expect(urls.allSatisfy { $0.host == "en.wikipedia.org" })
        await #expect(throws: ExplorerProblem.self) {
            try await provider.history(.init(candidateID: "unknown", snapshot: snapshot))
        }
        #expect(await transport.count == 3)
    }


    @Test func historicalRevisionUsesExactEnvelopeAndDeniesForeignPage() async throws {
        let pinned = SnapshotID(provider: "mediawiki-rest", project: "enwiki", pageID: "11", revisionID: "22", normalizerVersion: "mediawiki-html-1")
        let input = HistoricalRevisionInput(pinned: pinned, revisionID: "21")
        let body = html("<section data-mw-section-id='0'><p>Older article text.</p></section>", revision: 21)
        func wire(page: Int, revision: Int) throws -> String {
            let value: [String: Any] = ["id": revision, "timestamp": "2026-10-20T00:00:00Z",
                "page": ["id": page, "key": "Test", "title": "Test"], "content_model": "wikitext", "html": body]
            return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        }
        let transport = ReplayTransport([response(try wire(page: 11, revision: 21))])
        let provider = WikipediaProvider(transport: transport)
        let service = ExplorerService(provider: provider, limits: try ExplorerLimits())
        let outline = try await service.historicalOutline(input)
        #expect(outline.snapshot == input.expectedSnapshot)
        #expect(outline.provenance.license == HistoricalRevisionLicense.unavailable)
        let part = try #require(outline.sections.first?.location)
        let passage = try await service.section(.init(snapshot: outline.snapshot, part: part, maxTextBytes: 4096))
        #expect(passage.text.contains("Older article text."))
        #expect(!HistoricalRevisionLicense.permitsCollection(passage.provenance))
        await #expect(throws: ExplorerProblem.self) {
            try await service.shareableSection(.init(snapshot: outline.snapshot, part: part, maxTextBytes: 4096))
        }
        await #expect(throws: ExplorerProblem.self) {
            try await service.cachedOutline(outline.snapshot)
        }
        let again = try await service.historicalOutline(input)
        #expect(again.snapshot == outline.snapshot)
        let urls = await transport.urls
        #expect(urls == [try WikipediaRoute.revision("21")])
        for (page, revision) in [(12,21), (11,20)] {
            let foreign = WikipediaProvider(transport: ReplayTransport([response(try wire(page: page, revision: revision))]))
            await #expect(throws: ExplorerProblem.self) { try await foreign.historicalRevision(input) }
        }
        for bad in ["0", "01", "21/other", "21?x", "9223372036854775808"] {
            #expect(throws: LiveFailure.self) { try WikipediaRoute.revision(bad) }
        }
        #expect(!WikipediaRoute.allowed(URL(string: "https://en.wikipedia.org/w/rest.php/v1/revision/21/with_html?x=1")!))
    }

    @Test func historyRejectsMalformedSegmentsAndRoutes() async throws {
        let id = SnapshotID(provider: "mediawiki-rest", project: "enwiki", pageID: "11", revisionID: "22", normalizerVersion: "mediawiki-html-1")
        for body in [
            #"{"revisions":[{"id":22,"timestamp":"invalid","size":100,"minor":false}]}"#,
            #"{"revisions":[{"id":0,"timestamp":"2026-10-21T00:00:00Z","size":100,"minor":false}]}"#,
            #"{"revisions":[],"older":"anything"}"#,
            #"{"revisions":[{"id":22,"timestamp":"2026-10-21T00:00:00Z","size":-1,"minor":false}]}"#,
            #"{"revisions":[{"id":22,"timestamp":"2026-10-21T00:00:00Z","size":100,"minor":false},{"id":22,"timestamp":"2026-10-21T00:00:00Z","size":100,"minor":false}]}"#
        ] {
            let transport = ReplayTransport([response(searchWire), response(body)])
            let provider = WikipediaProvider(transport: transport)
            let candidate = try #require(try await provider.search(query: "Test", project: "enwiki", limit: 1).candidates.first)
            await #expect(throws: ExplorerProblem.self) {
                try await provider.history(.init(candidateID: candidate.id, snapshot: id))
            }
            #expect(await transport.count == 2)
        }
        #expect(throws: LiveFailure.self) { try WikipediaRoute.history("Test", olderThan: "0") }
        #expect(throws: LiveFailure.self) { try WikipediaRoute.history("Test", olderThan: "9223372036854775808") }
        let good = try WikipediaRoute.history("Test", olderThan: "21")
        #expect(WikipediaRoute.allowed(good))
        for bad in ["https://en.wikipedia.org/w/rest.php/v1/page/Test/history?older_than=21&newer_than=22",
                    "https://en.wikipedia.org/w/rest.php/v1/page/Test/history?older_than=0",
                    "https://en.wikipedia.org/w/rest.php/v1/page/Test/history?filter=bot",
                    "https://en.wikipedia.org.evil/w/rest.php/v1/page/Test/history",
                    "https://en.wikipedia.org/w/rest.php/v1/page/Test/Other/history"] {
            #expect(!WikipediaRoute.allowed(URL(string: bad)!))
        }
    }

    @Test func versionAndRevisionConflictsAreDenied() async throws {
        let normalizer = MediaWikiNormalizer()
        for raw in [html("<section data-mw-section-id='0'>x</section>", revision: 23), html("<section data-mw-section-id='0'>x</section>", version: "9.0.0")] {
            let page = try pageWire(html: raw)
            await #expect(throws: LiveFailure.self) { try await normalizer.normalize(page, retrievedAt: Date(), limits: ExplorerLimits()) }
        }
    }
    @Test func duplicateTargetsStayUnresolvedAndNoCitationFetchOccurs() async throws {
        let raw = html("<section data-mw-section-id='0'><p>Text<sup class='mw-ref'><a href='#cite_note-x'>1</a></sup></p><ol class='references'><li id='cite_note-x'>A</li><li id='cite_note-x'>B</li></ol></section>")
        let (snapshot, _) = try await MediaWikiNormalizer().normalize(pageWire(html: raw), retrievedAt: Date(), limits: ExplorerLimits())
        #expect(snapshot.references?.isEmpty == true)
        #expect(snapshot.parts.first?.citations == ["u0"])
    }
    @Test func normalizedDepthAndInputCapsAreDenials() async throws {
        let raw = html(String(repeating: "<section data-mw-section-id='-1'>", count: 33) + "text" + String(repeating: "</section>", count: 33))
        let page = try pageWire(html: raw)
        await #expect(throws: LiveFailure.self) { try await MediaWikiNormalizer().normalize(page, retrievedAt: Date(), limits: ExplorerLimits()) }
    }
}
