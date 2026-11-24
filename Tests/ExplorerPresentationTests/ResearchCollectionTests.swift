// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import ExplorerDomain
@testable import ExplorerPresentation

struct ResearchCollectionTests {
    private func sample(revision: String = "22", partID: String = "p0", text: String = "Source *text* <script>") -> (Outline, PartLocation, SectionPassage, SectionReferences) {
        let id = SnapshotID(provider: "mediawiki-rest", project: "enwiki", pageID: "11", revisionID: revision, normalizerVersion: "mediawiki-html-1")
        let p = Provenance(identity: id, title: "Example", sourceURL: "https://en.wikipedia.org/w/index.php?curid=11&oldid=\(revision)", retrievedAt: "2026-11-24T20:00:00Z", modifiedAt: nil, language: "en", license: "CC BY-SA 4.0 · https://creativecommons.org/licenses/by-sa/4.0/", synthetic: false)
        let part = PartLocation(snapshot: id, partID: partID)
        let outline = Outline(snapshot: id, provenance: p, introduction: nil, sections: [.init(location: part, parentPartID: nil, depth: 1, heading: "Heading")], totalSections: 1, introductionTruncated: false, referenceCount: 0, tableCount: 0, truncated: false)
        let passage = SectionPassage(snapshot: id, provenance: p, selectedPartID: partID, includedPartIDs: [partID], text: text, textAvailable: true, truncated: true, continuationSupported: false)
        let refs = SectionReferences(snapshot: id, provenance: p, references: [], associations: [], unresolvedIDs: [], truncated: false, independentlyVerified: false)
        return (outline, part, passage, refs)
    }

    @Test func captureAndExportsPreserveExactIdentityAndSeparateNotes() throws {
        var collection = ResearchCollection()
        let (outline, part, passage, refs) = sample()
        let id = try collection.capture(outline: outline, part: part, passage: passage, references: refs, referenceProblem: nil, route: .mcp)
        try collection.setNote("My own observation", for: id)
        let item = try #require(collection.entries.first)
        #expect(item.location == part && item.passage.text == passage.text && item.route == .mcp)
        #expect(item.note == "My own observation" && item.references != nil)
        let json = try JSONSerialization.jsonObject(with: collection.encoded(.json)) as? [String: Any]
        #expect(json?["format"] as? String == "WRE-research-collection-v1")
        let markdown = String(decoding: try collection.encoded(.markdown), as: UTF8.self)
        #expect(markdown.contains("Personal note") && markdown.contains("My own observation"))
        #expect(markdown.contains("Contributors and attribution") && markdown.contains("oldid=22"))
        #expect(markdown.contains("CC BY") && markdown.contains("Text shortened: Yes"))
        #expect(!markdown.contains("<script>") && markdown.contains("&lt;script&gt;"))
    }

    @Test func missingReferencesAndDuplicatesAreDistinctAndMismatchIsRejected() throws {
        var collection = ResearchCollection()
        let (outline, part, passage, refs) = sample()
        #expect(throws: ResearchCollection.Failure.unavailable) {
            try collection.capture(outline: outline, part: part, passage: passage, references: nil, referenceProblem: nil, route: .direct)
        }
        _ = try collection.capture(outline: outline, part: part, passage: passage, references: nil, referenceProblem: .missingReferences, route: .direct)
        #expect(collection.entries[0].references == nil && collection.entries[0].referenceProblem == .missingReferences)
        #expect(throws: ResearchCollection.Failure.alreadyCollected) {
            try collection.capture(outline: outline, part: part, passage: passage, references: refs, referenceProblem: nil, route: .mcp)
        }
        let (_, _, other, _) = sample(revision: "23")
        #expect(throws: ResearchCollection.Failure.inconsistentIdentity) {
            try collection.capture(outline: outline, part: part, passage: other, references: refs, referenceProblem: nil, route: .direct)
        }
        #expect(collection.entries.count == 1)
    }

    @Test func retentionAndNoteLimitsDoNotPartiallyMutate() throws {
        var collection = ResearchCollection()
        for i in 0..<ResearchCollection.maximumEntries {
            let (o, p, s, r) = sample(partID: "p\(i)")
            _ = try collection.capture(outline: o, part: p, passage: s, references: r, referenceProblem: nil, route: .direct)
        }
        let before = collection.retainedBytes
        let (o, p, s, r) = sample(partID: "extra")
        #expect(throws: ResearchCollection.Failure.capacity) {
            try collection.capture(outline: o, part: p, passage: s, references: r, referenceProblem: nil, route: .direct)
        }
        let id = collection.entries[0].id
        #expect(throws: ResearchCollection.Failure.noteTooLarge) {
            try collection.setNote(String(repeating: "é", count: 2049), for: id)
        }
        #expect(collection.retainedBytes == before && collection.entries[0].note.isEmpty)
        collection.remove(id)
        #expect(collection.entries.count == ResearchCollection.maximumEntries - 1 && collection.retainedBytes < before)
    }
}
