// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import ExplorerDomain

struct RevisionHistoryTests {
    private let pin = SnapshotID(provider: "mediawiki-rest", project: "enwiki", pageID: "11", revisionID: "22", normalizerVersion: "mediawiki-html-1")
    private func row(_ id: String, size: Int64 = 12) -> RevisionHistoryEntry {
        .init(id: id, timestamp: Date(timeIntervalSince1970: 100), size: size, delta: nil, minor: false)
    }
    private func page(_ rows: [RevisionHistoryEntry], older: Bool = false) -> RevisionHistory {
        .init(pinned: pin, title: "Example", anchor: "22", entries: rows, hasOlder: older)
    }

    @Test func boundedPageAndExactExternalLinks() throws {
        let history = page([row("21"), row("20")], older: true)
        #expect(history.isAdmitted && history.nextAnchor == "20")
        #expect(history.entries[0].permalink?.absoluteString == "https://en.wikipedia.org/w/index.php?oldid=21")
        #expect(history.entries[0].comparisonURL(to: pin.revisionID)?.absoluteString == "https://en.wikipedia.org/w/index.php?oldid=21&diff=22")
        #expect(page([]).isAdmitted && page([]).nextAnchor == nil)
    }

    @Test func deniesUnboundedOrInconsistentHistory() {
        #expect(!page([row("22")]).isAdmitted)
        #expect(!page([row("21"), row("21")]).isAdmitted)
        #expect(!page([row("21", size: -1)]).isAdmitted)
        #expect(!page([], older: true).isAdmitted)
        #expect(!page((30...50).map { row(String($0)) }).isAdmitted)
        for id in ["0", "-1", "01", "+1", "1&diff=2", "9223372036854775808"] {
            #expect(row(id).permalink == nil)
            #expect(!page([row(id)]).isAdmitted)
        }
        #expect(row("21").comparisonURL(to: "21") == nil)
    }
}
