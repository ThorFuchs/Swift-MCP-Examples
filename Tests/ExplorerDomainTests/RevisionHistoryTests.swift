// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import ExplorerDomain

struct RevisionHistoryTests {
    private let snapshot = SnapshotID(provider: "mediawiki-rest", project: "enwiki", pageID: "11", revisionID: "22", normalizerVersion: "mediawiki-html-1")

    private func row(_ id: String, _ time: String = "2026-10-21T00:00:00Z", size: Int64 = 100) -> RevisionHistoryEntry {
        .init(revisionID: id, timestamp: time, size: size, delta: nil, minor: false)
    }

    @Test func validSegmentRetainsExactIDsAndConstructsPermalink() throws {
        let page = RevisionHistoryPage(requestedSnapshot: snapshot, requestedTitle: "Test", entries: [row("22"), row("21", "2026-10-20T00:00:00Z")], hasOlder: true)
        #expect(page.isAdmitted(for: .init(candidateID: "c", snapshot: snapshot)))
        #expect(page.olderCursor == "21")
        #expect(page.entries[1].permalink?.absoluteString == "https://en.wikipedia.org/w/index.php?oldid=21")
        #expect(!page.isAdmitted(for: .init(candidateID: "c", snapshot: snapshot, olderThan: "21")))
    }

    @Test func invalidIdentityOrderAndBoundsAreDenied() {
        for bad in ["0", "-1", "01", "1?x", "9223372036854775808"] {
            #expect(!RevisionHistoryEntry.isRevisionID(bad))
            #expect(row(bad).permalink == nil)
        }
        let input = RevisionHistoryInput(candidateID: "c", snapshot: snapshot)
        for rows in [[row("22"), row("22")],
                     [row("21", "2026-10-20T00:00:00Z"), row("22")],
                     [row("22", "invalid")], [row("22", size: -1)],
                     (1...21).map { row(String($0)) }] {
            #expect(!RevisionHistoryPage(requestedSnapshot: snapshot, requestedTitle: "Test", entries: rows, hasOlder: false).isAdmitted(for: input))
        }
        #expect(!RevisionHistoryPage(requestedSnapshot: snapshot, requestedTitle: "Test", entries: [], hasOlder: true).isAdmitted(for: input))
        #expect(RevisionHistoryPage(requestedSnapshot: snapshot, requestedTitle: "Test", entries: [], hasOlder: false).isAdmitted(for: input))
    }
}
