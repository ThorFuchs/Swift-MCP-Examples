// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import ExplorerDomain

struct RelatedKnowledgeTests {
    @Test func onlySupportedRelativeArticleTitlesAreAdmitted() {
        #expect(RelatedKnowledge.title(fromParsoidHref: "./Lagrangian_mechanics#History") == "Lagrangian mechanics")
        #expect(RelatedKnowledge.title(fromParsoidHref: "./Caf%C3%A9") == "Café")
        for href in ["https://en.wikipedia.org/wiki/A", "//en.wikipedia.org/wiki/A", "#here", "./File:A",
                     "./A?redlink=1", "./%2e%2e/A", "./%2FA", "./A%00B", "./A%3AB", "./%", "./A//B", "./"] {
            #expect(RelatedKnowledge.title(fromParsoidHref: href) == nil)
        }
    }

    @Test func rejectsDuplicateAndOverBudgetMetadata() {
        #expect(RelatedKnowledge(titles: ["A", "B"], truncated: false).isAdmitted)
        #expect(!RelatedKnowledge(titles: ["A", "A"], truncated: false).isAdmitted)
        #expect(!RelatedKnowledge(titles: (0..<13).map(String.init), truncated: false).isAdmitted)
        #expect(!RelatedKnowledge(titles: [String(repeating: "é", count: 129)], truncated: false).isAdmitted)
    }
}
