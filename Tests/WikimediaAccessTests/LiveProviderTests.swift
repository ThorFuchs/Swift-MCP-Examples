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

    @Test func earlierHistoryUsesAdmittedCandidateAndIgnoresUpstreamCursorURLs() async throws {
        let transport = ReplayTransport([response(searchWire), response(#"{"revisions":[{"id":21,"timestamp":"2026-10-20T00:00:00Z","size":125,"delta":-5,"minor":true,"user":{"name":"ignored"},"comment":"ignored"}],"older":"https://evil.example/not-followed"}"#)])
        let provider = WikipediaProvider(transport: transport)
        let page = try await provider.search(query: "Test", project: "enwiki", limit: 1)
        let candidate = try #require(page.candidates.first)
        let pin = SnapshotID(provider: "mediawiki-rest", project: "enwiki", pageID: "11", revisionID: "22", normalizerVersion: "mediawiki-html-1")
        let history = try await provider.history(candidateID: candidate.id, pinned: pin, olderThan: "22")
        #expect(history.isAdmitted && history.entries.map(\.id) == ["21"] && history.nextAnchor == "21")
        #expect(history.entries.first?.delta == -5)
        #expect(await transport.count == 2)
        let urls = await transport.urls
        #expect(urls.last == (try WikipediaRoute.history("Test/Page%?#é", olderThan: "22")))
        #expect(history.entries.first?.permalink?.absoluteString == "https://en.wikipedia.org/w/index.php?oldid=21")
    }

    @Test func historyRouteRejectsOtherOriginsAndUnadmittedParameters() throws {
        let url = try WikipediaRoute.history("A/b%?é", olderThan: "22")
        #expect(WikipediaRoute.allowed(url))
        for id in ["0", "-1", "01", "9223372036854775808", "22/with_html"] {
            #expect(throws: LiveFailure.self) { try WikipediaRoute.history("A", olderThan: id) }
        }
        for value in [
            "https://evil.example/w/rest.php/v1/page/A/history?older_than=22",
            "https://en.wikipedia.org/w/rest.php/v1/page/A/history",
            "https://en.wikipedia.org/w/rest.php/v1/page/A/history?older_than=22&filter=bot",
            "https://en.wikipedia.org/w/rest.php/v1/page/A/history?older_than=22&older_than=21",
            "https://en.wikipedia.org/w/rest.php/v1/page/A/history?older_than=0",
            "https://en.wikipedia.org/w/rest.php/v1/revision/22/with_html"
        ] {
            #expect(!WikipediaRoute.allowed(URL(string: value)!))
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
