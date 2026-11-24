// SPDX-License-Identifier: Apache-2.0
import Foundation

/// An owned, structured failure with an application error code, public message and recovery guidance.
public struct ExplorerProblem: Error, Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable {
        case invalidArguments = "invalid_arguments", projectNotAllowed = "project_not_allowed"
        case unknownCandidate = "unknown_candidate", absentPage = "absent_page"
        case absentSnapshot = "absent_snapshot", absentSection = "absent_section"
        case revisionMismatch = "revision_mismatch", ambiguousTitle = "ambiguous_title"
        case missingReferences = "missing_references", unsupportedVariant = "unsupported_variant"
        case budgetExceeded = "budget_exceeded", upstreamUnavailable = "upstream_unavailable"
        case upstreamRateLimited = "upstream_rate_limited", upstreamTimedOut = "upstream_timed_out"
        case invalidFixture = "invalid_fixture"
    }
    public let code: Code
    public let message: String
    public let recovery: String
    public init(_ code: Code, _ message: String, recovery: String) {
        self.code = code; self.message = message; self.recovery = recovery
    }
}

/// Finite bounds on normalization, projection and snapshot retention. Invalid configurations are rejected during initialization.
public struct ExplorerLimits: Sendable {
    public let depth, parts, sectionTextBytes, responseBytes, cacheEntries, cacheContentBytes: Int
    public let snapshotTTL: TimeInterval
    public init(depth: Int = 32, parts: Int = 4096, sectionTextBytes: Int = 32768,
                responseBytes: Int = 131072, cacheEntries: Int = 16,
                cacheContentBytes: Int = 33554432, snapshotTTL: TimeInterval = 300) throws {
        guard (1...32).contains(depth), (1...4096).contains(parts),
              (1...32768).contains(sectionTextBytes), (4096...131072).contains(responseBytes),
              (1...16).contains(cacheEntries), (1024...33554432).contains(cacheContentBytes),
              snapshotTTL.isFinite, snapshotTTL > 0, snapshotTTL <= 3600 else {
            throw ExplorerProblem(.invalidArguments, "Limits exceed the example profile.", recovery: "Use the documented finite defaults or lower limits.")
        }
        self.depth = depth; self.parts = parts; self.sectionTextBytes = sectionTextBytes
        self.responseBytes = responseBytes; self.cacheEntries = cacheEntries
        self.cacheContentBytes = cacheContentBytes; self.snapshotTTL = snapshotTTL
    }
}

// This is the owned wre-fixture-1 format, NEVER a Wikimedia wire decoder.
/// The owned fictional fixture format; not a decoder for Wikimedia wire responses.
public struct ArticleSeed: Codable, Sendable {
    public let fixtureKind, formatVersion, project, pageID, revisionID, title, sourceURL, normalizerVersion, license: String
    public let parts: [PartSeed]
    public let references: [ReferenceSeed]?
    public let tables: [TableSeed]?
    public let modifiedAt: String?
    enum CodingKeys: String, CodingKey {
        case fixtureKind = "fixture_kind", formatVersion = "format_version", project
        case pageID = "page_id", revisionID = "revision_id", title, sourceURL = "source_url"
        case normalizerVersion = "normalizer_version", license, parts, references, tables
        case modifiedAt = "modified_at"
    }
}
/// Recursive section input in the owned fixture format.
public struct PartSeed: Codable, Sendable {
    public let id: String
    public let heading, text, kind: String?
    public let citations: [String]?
    public let parts: [PartSeed]?
}
/// Source-supplied reference metadata, including whether the entry is synthetic.
public struct ReferenceSeed: Codable, Sendable, Equatable {
    public let id, title: String
    public let url: String?
    public let synthetic: Bool
    public init(id: String, title: String, url: String?, synthetic: Bool) { self.id = id; self.title = title; self.url = url; self.synthetic = synthetic }
}
/// Bounded fixture table data containing text or integer cells.
public struct TableSeed: Codable, Sendable, Equatable {
    public let id, caption: String
    public let columns: [String]
    public let rows: [[Cell]]
    public enum Cell: Codable, Sendable, Equatable {
        case text(String), integer(Int64)
        public init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .text(s) }
            else { self = .integer(try c.decode(Int64.self)) }
        }
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self { case .text(let s): try c.encode(s); case .integer(let n): try c.encode(n) }
        }
    }
}

/// Complete normalized revision identity: provider, project, page, revision and normalizer version.
public struct SnapshotID: Codable, Sendable, Hashable {
    public let provider: String
    public let project: String
    public let pageID: String
    public let revisionID: String
    public let normalizerVersion: String
    public init(provider: String, project: String, pageID: String, revisionID: String, normalizerVersion: String) {
        self.provider = provider
        self.project = project
        self.pageID = pageID
        self.revisionID = revisionID
        self.normalizerVersion = normalizerVersion
    }
}

/// A part identifier bound to its exact snapshot identity.
public struct PartLocation: Codable, Sendable, Hashable {
    public let snapshot: SnapshotID
    public let partID: String
    public init(snapshot: SnapshotID, partID: String) {
        self.snapshot = snapshot
        self.partID = partID
    }
}

/// A search result offered by the selected provider; not yet a pinned revision.
public struct Candidate: Codable, Sendable, Equatable {
    public let id: String
    public let project: String
    public let pageID: String
    public let title: String
    public let description: String?
    public init(id: String, project: String, pageID: String, title: String, description: String?) {
        self.id = id
        self.project = project
        self.pageID = pageID
        self.title = title
        self.description = description
    }
}

/// Source, retrieval, revision and license metadata for a normalized snapshot.
public struct Provenance: Codable, Sendable, Equatable {
    public let identity: SnapshotID
    public let title: String
    public let sourceURL: String
    public let retrievedAt: String
    public let modifiedAt: String?
    public let language: String?
    public let license: String
    public let synthetic: Bool
    public init(identity: SnapshotID, title: String, sourceURL: String, retrievedAt: String, modifiedAt: String?, language: String?, license: String, synthetic: Bool) {
        self.identity = identity
        self.title = title
        self.sourceURL = sourceURL
        self.retrievedAt = retrievedAt
        self.modifiedAt = modifiedAt
        self.language = language
        self.license = license
        self.synthetic = synthetic
    }
}

/// One normalized part with parent/depth, optional content and citation identifiers.
public struct NormalizedPart: Sendable, Equatable {
    public let id: String
    public let parentID: String?
    public let depth: Int
    public let heading: String?
    public let text: String?
    public let citations: [String]
    /// Optional internal link metadata, not citation evidence.
    public let relatedKnowledge: RelatedKnowledge?
    public init(id: String, parentID: String?, depth: Int, heading: String?, text: String?, citations: [String], relatedKnowledge: RelatedKnowledge? = nil) {
        self.id = id
        self.parentID = parentID
        self.depth = depth
        self.heading = heading
        self.text = text
        self.citations = citations
        self.relatedKnowledge = relatedKnowledge
    }
}

/// An admitted normalized revision and its bounded content and reference metadata.
public struct Snapshot: Sendable {
    public let provenance: Provenance
    public let parts: [NormalizedPart]
    public let references: [ReferenceSeed]?
    public let tables: [TableSeed]?
    public let tableCount: Int
    public let contentBytes: Int
    public init(provenance: Provenance, parts: [NormalizedPart], references: [ReferenceSeed]?, tables: [TableSeed]?, tableCount: Int, contentBytes: Int) {
        self.provenance = provenance
        self.parts = parts
        self.references = references
        self.tables = tables
        self.tableCount = tableCount
        self.contentBytes = contentBytes
    }
}

/// Input to bounded article search within one selected project.
public struct SearchInput: Codable, Sendable {
    public let query: String
    public let project: String
    public let limit: Int?
    public init(query: String, project: String, limit: Int?) {
        self.query = query
        self.project = project
        self.limit = limit
    }
}

/// Resolves a provider-issued candidate into a revision-bound outline.
public struct OutlineInput: Codable, Sendable {
    public let project: String
    public let candidateID: String
    public init(project: String, candidateID: String) {
        self.project = project
        self.candidateID = candidateID
    }
}

/// Requests a bounded passage from a part of an exact cached snapshot.
public struct SectionInput: Codable, Sendable {
    public let snapshot: SnapshotID
    public let part: PartLocation
    public let maxTextBytes: Int?
    public init(snapshot: SnapshotID, part: PartLocation, maxTextBytes: Int?) {
        self.snapshot = snapshot
        self.part = part
        self.maxTextBytes = maxTextBytes
    }
}

/// Requests citation associations and reference metadata for an exact snapshot part.
public struct ReferencesInput: Codable, Sendable {
    public let snapshot: SnapshotID
    public let part: PartLocation
    public init(snapshot: SnapshotID, part: PartLocation) {
        self.snapshot = snapshot
        self.part = part
    }
}

/// A bounded candidate page, including the original admitted query and truncation flag.
public struct SearchPage: Codable, Sendable {
    public let candidates: [Candidate]
    public let truncated: Bool
    public let provider: String
    public let query: String
    public init(candidates: [Candidate], truncated: Bool, provider: String, query: String) {
        self.candidates = candidates
        self.truncated = truncated
        self.provider = provider
        self.query = query
    }
}

/// A hierarchy entry with a revision-bound location and optional heading.
public struct OutlineSection: Codable, Sendable {
    public let location: PartLocation
    public let parentPartID: String?
    public let depth: Int
    public let heading: String?
    public init(location: PartLocation, parentPartID: String?, depth: Int, heading: String?) {
        self.location = location
        self.parentPartID = parentPartID
        self.depth = depth
        self.heading = heading
    }
}

/// A bounded introduction and section hierarchy for one pinned revision.
public struct Outline: Codable, Sendable {
    public let snapshot: SnapshotID
    public let provenance: Provenance
    public let introduction: String?
    public let sections: [OutlineSection]
    public let totalSections: Int
    public let introductionTruncated: Bool
    public let referenceCount: Int?
    public let tableCount: Int
    public let truncated: Bool
    public init(snapshot: SnapshotID, provenance: Provenance, introduction: String?, sections: [OutlineSection], totalSections: Int, introductionTruncated: Bool, referenceCount: Int?, tableCount: Int, truncated: Bool) {
        self.snapshot = snapshot
        self.provenance = provenance
        self.introduction = introduction
        self.sections = sections
        self.totalSections = totalSections
        self.introductionTruncated = introductionTruncated
        self.referenceCount = referenceCount
        self.tableCount = tableCount
        self.truncated = truncated
    }
}

/// Projected plain-text content with explicit availability, truncation and provenance.
public struct SectionPassage: Codable, Sendable {
    public let snapshot: SnapshotID
    public let provenance: Provenance
    public let selectedPartID: String
    public let includedPartIDs: [String]
    public let text: String
    public let textAvailable: Bool
    public let truncated: Bool
    public let continuationSupported: Bool
    /// Bounded related-title metadata for the selected section only; nil if unavailable.
    public let relatedKnowledge: RelatedKnowledge?
    public init(snapshot: SnapshotID, provenance: Provenance, selectedPartID: String, includedPartIDs: [String], text: String, textAvailable: Bool, truncated: Bool, continuationSupported: Bool, relatedKnowledge: RelatedKnowledge? = nil) {
        self.snapshot = snapshot
        self.provenance = provenance
        self.selectedPartID = selectedPartID
        self.includedPartIDs = includedPartIDs
        self.text = text
        self.textAvailable = textAvailable
        self.truncated = truncated
        self.continuationSupported = continuationSupported
        self.relatedKnowledge = relatedKnowledge
    }
}

/// A citation identifier and its source part, with explicit resolution status.
public struct CitationAssociation: Codable, Sendable, Equatable {
    public let partID: String
    public let referenceID: String
    public let resolved: Bool
    public init(partID: String, referenceID: String, resolved: Bool) {
        self.partID = partID
        self.referenceID = referenceID
        self.resolved = resolved
    }
}

/// Projected reference metadata, not a verification of the cited source.
public struct ReferenceEntry: Codable, Sendable {
    public let id: String
    public let title: String
    public let url: String?
    public let synthetic: Bool
    public init(id: String, title: String, url: String?, synthetic: Bool) {
        self.id = id
        self.title = title
        self.url = url
        self.synthetic = synthetic
    }
}

/// Reference entries, citation associations and unresolved identifiers for one section.
public struct SectionReferences: Codable, Sendable {
    public let snapshot: SnapshotID
    public let provenance: Provenance
    public let references: [ReferenceEntry]
    public let associations: [CitationAssociation]
    public let unresolvedIDs: [String]
    public let truncated: Bool
    public let independentlyVerified: Bool
    public init(snapshot: SnapshotID, provenance: Provenance, references: [ReferenceEntry], associations: [CitationAssociation], unresolvedIDs: [String], truncated: Bool, independentlyVerified: Bool) {
        self.snapshot = snapshot
        self.provenance = provenance
        self.references = references
        self.associations = associations
        self.unresolvedIDs = unresolvedIDs
        self.truncated = truncated
        self.independentlyVerified = independentlyVerified
    }
}
