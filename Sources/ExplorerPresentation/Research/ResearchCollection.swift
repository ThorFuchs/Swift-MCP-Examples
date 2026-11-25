// SPDX-License-Identifier: Apache-2.0
import Foundation
import ExplorerDomain

/// Explicitly collected evidence, independent of the expiring provider cache.
/// Captured source content and the user's note remain separate.
public struct ResearchEvidence: Codable, Sendable, Identifiable {
    public let id: UUID
    public let capturedAt: Date
    public let heading: String
    public let route: ResearchExecutionMode
    public let passage: SectionPassage
    public let references: SectionReferences?
    public let referenceProblem: ExplorerProblem.Code?
    public let contributorsURL: String?
    public fileprivate(set) var note: String
    public var location: PartLocation { .init(snapshot: passage.snapshot, partID: passage.selectedPartID) }
}

/// Bounded in-memory working dossier. No automatic persistence, network access
/// or diagnostic logging. Captured evidence remains available after cache expiry.
public struct ResearchCollection: Sendable {
    public static let maximumEntries = 16
    public static let maximumEncodedEntryBytes = 131072
    public static let maximumRetainedBytes = 524288
    public static let maximumNoteBytes = 4096
    public static let maximumExportBytes = 4194304

    public enum Failure: Error, Sendable, Equatable {
        case unavailable, inconsistentIdentity, alreadyCollected, capacity, noteTooLarge, unknownEntry
    }
    public enum Format: String, CaseIterable, Sendable {
        case markdown = "Markdown"
        case json = "JSON"
        public var fileExtension: String { self == .markdown ? "md" : "json" }
    }
    public private(set) var entries: [ResearchEvidence] = []
    private var sizes: [UUID: Int] = [:]
    public var retainedBytes: Int { sizes.values.reduce(0, +) }

    public init() {}

    /// Capture exactly the displayed section and its reference evidence.
    /// Missing reference metadata is distinct from an observed empty list.
    @discardableResult
    public mutating func capture(outline: Outline, part: PartLocation, passage: SectionPassage,
                                 references: SectionReferences?, referenceProblem: ExplorerProblem.Code?,
                                 route: ResearchExecutionMode, capturedAt: Date = Date()) throws -> UUID {
        guard passage.textAvailable, !passage.text.isEmpty,
              passage.text.utf8.count <= 32768, capturedAt.timeIntervalSince1970.isFinite else { throw Failure.unavailable }
        guard part.snapshot == outline.snapshot, passage.snapshot == part.snapshot,
              passage.provenance.identity == part.snapshot,
              passage.selectedPartID == part.partID,
              outline.provenance.identity == part.snapshot,
              let section = outline.sections.first(where: { $0.location == part }),
              Self.admitted(passage.provenance),
              passage.includedPartIDs.count <= 128,
              passage.includedPartIDs.allSatisfy(Normalizer.component),
              passage.relatedKnowledge?.isAdmitted != false else { throw Failure.inconsistentIdentity }
        let heading = section.heading ?? "Introduction"
        guard heading.utf8.count <= 512 else { throw Failure.inconsistentIdentity }
        if let references {
            guard referenceProblem == nil, references.snapshot == part.snapshot,
                  references.provenance.identity == part.snapshot,
                  Self.admitted(references.provenance), !references.independentlyVerified,
                  references.references.count <= 20, references.associations.count <= 64,
                  references.unresolvedIDs.count <= 64,
                  references.references.allSatisfy({
                      Normalizer.component($0.id) && $0.title.utf8.count <= 512 && ($0.url?.utf8.count ?? 0) <= 2048
                  }),
                  references.associations.allSatisfy({ Normalizer.component($0.partID) && Normalizer.component($0.referenceID) }),
                  references.unresolvedIDs.allSatisfy(Normalizer.component) else { throw Failure.inconsistentIdentity }
        } else if referenceProblem == nil {
            throw Failure.unavailable
        }
        guard !entries.contains(where: { $0.location == part }) else { throw Failure.alreadyCollected }
        guard entries.count < Self.maximumEntries else { throw Failure.capacity }
        let attribution = passage.provenance.synthetic ? nil : "https://en.wikipedia.org/w/index.php?curid=\(part.snapshot.pageID)&action=history"
        let item = ResearchEvidence(id: UUID(), capturedAt: capturedAt, heading: heading, route: route,
                                    passage: passage, references: references, referenceProblem: referenceProblem,
                                    contributorsURL: attribution, note: "")
        let size = try Self.entrySize(item)
        guard size <= Self.maximumRetainedBytes - retainedBytes else { throw Failure.capacity }
        entries.append(item); sizes[item.id] = size
        return item.id
    }

    /// Update only the user's note, never the captured source evidence.
    public mutating func setNote(_ note: String, for id: UUID) throws {
        guard note.utf8.count <= Self.maximumNoteBytes else { throw Failure.noteTooLarge }
        guard let index = entries.firstIndex(where: { $0.id == id }), let previousSize = sizes[id] else { throw Failure.unknownEntry }
        var next = entries[index]; next.note = note
        let size = try Self.entrySize(next)
        guard size <= Self.maximumRetainedBytes - (retainedBytes - previousSize) else { throw Failure.capacity }
        entries[index] = next; sizes[id] = size
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }; sizes[id] = nil
    }

    /// Versioned JSON or attributed Markdown. Untrusted text is escaped as
    /// text, not interpreted as authored Markdown or active HTML.
    public func encoded(_ format: Format, generatedAt: Date = Date()) throws -> Data {
        guard !entries.isEmpty, generatedAt.timeIntervalSince1970.isFinite else { throw Failure.unavailable }
        try Task.checkCancellation()
        let result: Data
        switch format {
        case .json:
            struct Document: Encodable {
                let format = "WRE-research-collection-v1"
                let generatedAt: Date
                let entries: [ResearchEvidence]
                let citationMetadataIndependentlyVerified = false
                let sourceNotice = "Normalized plain-text excerpts; per-entry source license and attribution apply. User notes are separate."
            }
            result = try Self.encoder().encode(Document(generatedAt: generatedAt, entries: entries))
        case .markdown:
            var text = "# Research Collection\n\nGenerated: \(ISO8601DateFormatter().string(from: generatedAt))\n\n"
            text += "Source excerpts are normalized plain-text projections. Per-entry license and attribution apply. Reference metadata is not independently verified. Personal notes are separate from source text.\n\n"
            for entry in entries {
                try Task.checkCancellation()
                let p = entry.passage, provenance = p.provenance, id = p.snapshot
                text += "## \(Self.escape(provenance.title)) — \(Self.escape(entry.heading))\n\n"
                text += "- Source: \(provenance.synthetic ? "Fictional offline demo" : "Wikipedia English")\n"
                text += "- Execution route: \(entry.route.rawValue)\n"
                text += "- Page / revision / part: \(Self.escape(id.pageID)) / \(Self.escape(id.revisionID)) / \(Self.escape(p.selectedPartID))\n"
                text += "- Provider / project / normalizer: \(Self.escape(id.provider)) / \(Self.escape(id.project)) / \(Self.escape(id.normalizerVersion))\n"
                text += "- Retrieved: \(Self.escape(provenance.retrievedAt))\n"
                text += "- Captured: \(ISO8601DateFormatter().string(from: entry.capturedAt))\n"
                text += "- License: \(Self.escape(provenance.license))\n"
                if let contributorsURL = entry.contributorsURL {
                    text += "- Source revision: <\(provenance.sourceURL)>\n"
                    text += "- Contributors and attribution: <\(contributorsURL)>\n"
                } else {
                    text += "- Source revision: \(Self.escape(provenance.sourceURL))\n"
                }
                text += "- Text shortened: \(p.truncated ? "Yes" : "No")\n\n"
                text += "### Source excerpt\n\n"
                text += p.text.components(separatedBy: .newlines).map { "> " + Self.escape($0) }.joined(separator: "\n") + "\n\n"
                text += "### Reference metadata (unverified)\n\n"
                if let refs = entry.references {
                    if refs.references.isEmpty && refs.unresolvedIDs.isEmpty { text += "No cited references in the returned projection.\n" }
                    for ref in refs.references {
                        text += "- \(Self.escape(ref.id)): \(Self.escape(ref.title))"
                        if let url = ref.url { text += " — \(Self.escape(url))" }
                        text += "\n"
                    }
                    if !refs.unresolvedIDs.isEmpty { text += "Unresolved: \(Self.escape(refs.unresolvedIDs.joined(separator: ", ")))\n" }
                    if refs.truncated { text += "Reference projection truncated.\n" }
                } else {
                    text += "Unavailable: \(entry.referenceProblem?.rawValue ?? "unknown") (not an empty reference list).\n"
                }
                if !entry.note.isEmpty { text += "\n### Personal note\n\n\(Self.escape(entry.note))\n" }
                text += "\n---\n\n"
                guard text.utf8.count <= Self.maximumExportBytes else { throw Failure.capacity }
            }
            result = Data(text.utf8)
        }
        guard result.count <= Self.maximumExportBytes else { throw Failure.capacity }
        return result
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func entrySize(_ item: ResearchEvidence) throws -> Int {
        let size = try encoder().encode(item).count
        guard size <= maximumEncodedEntryBytes else { throw Failure.capacity }
        return size
    }

    private static func admitted(_ p: Provenance) -> Bool {
        let id = p.identity
        let profile: SourceProfile = p.synthetic ? .offlineDemo : .wikipediaEnglish
        guard HistoricalRevisionLicense.permitsCollection(p), profile.admits(id), p.title.utf8.count <= 512,
              !p.license.isEmpty, p.license.utf8.count <= 2048,
              p.sourceURL.utf8.count <= 2048, p.retrievedAt.utf8.count <= 128,
              (p.modifiedAt?.utf8.count ?? 0) <= 128, (p.language?.utf8.count ?? 0) <= 128 else { return false }
        if p.synthetic { return p.sourceURL.hasPrefix("fixture://") }
        return LiveSnapshotAdmission.decimal(id.pageID) && LiveSnapshotAdmission.decimal(id.revisionID)
            && p.sourceURL == "https://en.wikipedia.org/w/index.php?curid=\(id.pageID)&oldid=\(id.revisionID)"
    }

    private static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\\", "\u{0060}", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", ".", "!", "|", "~":
                result += "\\"; result.append(character)
            default: result.append(character)
            }
        }
        return result
    }
}

/// Reuse the existing bounded file writer. This is an explicit user document
/// export, not a diagnostic/Activity export.
extension ActivityExportWriter {
    public func writeCollection(_ collection: ResearchCollection, format: ResearchCollection.Format, to destination: URL) async throws {
        let data = try collection.encoded(format)
        try await write(data, to: destination)
    }
}
