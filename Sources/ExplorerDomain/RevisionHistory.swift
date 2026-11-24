// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Metadata for one publicly returned Wikipedia revision. No editor names,
/// edit comments, raw HTML or content are retained by history browsing.
public struct RevisionHistoryEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let size: Int64
    public let delta: Int64?
    public let minor: Bool

    public init(id: String, timestamp: Date, size: Int64, delta: Int64?, minor: Bool) {
        self.id = id; self.timestamp = timestamp; self.size = size
        self.delta = delta; self.minor = minor
    }

    public static func admitsID(_ id: String) -> Bool {
        guard let value = Int64(id), value > 0 else { return false }
        return String(value) == id
    }

    public var permalink: URL? {
        guard Self.admitsID(id) else { return nil }
        return URL(string: "https://en.wikipedia.org/w/index.php?oldid=\(id)")
    }

    /// Opens the upstream comparison; does not claim local section alignment.
    public func comparisonURL(to revisionID: String) -> URL? {
        guard Self.admitsID(id), Self.admitsID(revisionID), id != revisionID else { return nil }
        return URL(string: "https://en.wikipedia.org/w/index.php?oldid=\(id)&diff=\(revisionID)")
    }
}

/// One bounded page of earlier revisions, requested relative to a pinned
/// revision. The upstream history response is title-scoped: it does not
/// independently attest each revision's page ID. No content is adopted.
public struct RevisionHistory: Sendable, Equatable {
    public static let maximumEntries = 20
    public let pinned: SnapshotID
    public let title: String
    public let anchor: String
    public let entries: [RevisionHistoryEntry]
    public let hasOlder: Bool

    public init(pinned: SnapshotID, title: String, anchor: String,
                entries: [RevisionHistoryEntry], hasOlder: Bool) {
        self.pinned = pinned; self.title = title; self.anchor = anchor
        self.entries = entries; self.hasOlder = hasOlder
    }

    public var nextAnchor: String? {
        guard hasOlder, let last = entries.last, last.id != anchor else { return nil }
        return last.id
    }

    public var isAdmitted: Bool {
        SourceProfile.wikipediaEnglish.admits(pinned)
            && RevisionHistoryEntry.admitsID(pinned.pageID)
            && RevisionHistoryEntry.admitsID(pinned.revisionID)
            && RevisionHistoryEntry.admitsID(anchor)
            && !title.isEmpty && title.utf8.count <= 512
            && entries.count <= Self.maximumEntries
            && Set(entries.map(\.id)).count == entries.count
            && entries.allSatisfy {
                RevisionHistoryEntry.admitsID($0.id) && $0.id != anchor
                    && $0.id != pinned.revisionID && $0.size >= 0
                    && $0.timestamp.timeIntervalSince1970.isFinite
            }
            && (!hasOlder || !entries.isEmpty)
    }
}
