// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import ExplorerDomain

struct ResearchResourceAddressTests {
    private let live = SnapshotID(provider: "mediawiki-rest", project: "enwiki", pageID: "11", revisionID: "22", normalizerVersion: "mediawiki-html-1")
    private let offline = SnapshotID(provider: "synthetic-fixture", project: "fixture-enwiki", pageID: "observatory", revisionID: "r1", normalizerVersion: "fixture-1")

    @Test func canonicalAddressesPreserveEveryIdentityComponent() throws {
        for id in [live, offline] {
            for kind in [ResearchResourceAddress.Kind.outline, .section("p2")] {
                let address = try #require(ResearchResourceAddress(snapshot: id, kind: kind))
                #expect(ResearchResourceAddress(uri: address.uri) == address)
                #expect(address.snapshot == id && address.kind == kind)
            }
        }
        let address = try #require(ResearchResourceAddress(snapshot: live, kind: .outline))
        #expect(address.uri == "wre://knowledge/mediawiki-rest/enwiki/11/22/mediawiki-html-1/outline")
    }

    @Test func foreignMalformedAndNoncanonicalAddressesAreDenied() throws {
        let uri = try #require(ResearchResourceAddress(snapshot: live, kind: .section("p2"))).uri
        for bad in [uri + "?latest=1", uri + "#x", uri + "/", uri.replacingOccurrences(of: "wre://", with: "https://"),
                    uri.replacingOccurrences(of: "/11/", with: "/011/"),
                    uri.replacingOccurrences(of: "/22/", with: "/%32%32/"),
                    uri.replacingOccurrences(of: "/p2/", with: "/../"),
                    uri.replacingOccurrences(of: "/enwiki/", with: "/fixture-enwiki/"),
                    uri.replacingOccurrences(of: "mediawiki-html-1", with: "other"),
                    uri.replacingOccurrences(of: "/11/", with: "//")] {
            #expect(ResearchResourceAddress(uri: bad) == nil)
        }
        #expect(ResearchResourceAddress(snapshot: live, kind: .section("p/2")) == nil)
    }

    @Test func historicalInputChangesOnlyRevisionAndRejectsOtherSource() {
        let input = HistoricalRevisionInput(pinned: live, revisionID: "21")
        #expect(input.isAdmitted)
        #expect(input.expectedSnapshot.pageID == live.pageID && input.expectedSnapshot.revisionID == "21")
        #expect(input.expectedSnapshot.provider == live.provider && input.expectedSnapshot.normalizerVersion == live.normalizerVersion)
        #expect(!HistoricalRevisionInput(pinned: live, revisionID: "22").isAdmitted)
        #expect(!HistoricalRevisionInput(pinned: live, revisionID: "0").isAdmitted)
        #expect(!HistoricalRevisionInput(pinned: offline, revisionID: "21").isAdmitted)
    }
}
