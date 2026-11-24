// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A user-requested history segment for an admitted search candidate.
/// The snapshot scopes the reader context, not the identity of each history row.
public struct RevisionHistoryInput: Sendable {
    public let candidateID: String
    public let snapshot: SnapshotID
    /// An explicit older-than cursor derived from a returned history row.
    public let olderThan: String?

    public init(candidateID: String, snapshot: SnapshotID, olderThan: String? = nil) {
        self.candidateID = candidateID
        self.snapshot = snapshot
        self.olderThan = olderThan
    }
}

/// Public revision metadata only. No editor names, IP addresses or edit comments
/// are retained. A listed revision is not yet an admitted article snapshot.
public struct RevisionHistoryEntry: Identifiable, Sendable, Equatable {
    public let revisionID: String
    public let timestamp: String
    public let size: Int64
    public let delta: Int64?
    public let minor: Bool
    public var id: String { revisionID }
    public var date: Date? { ISO8601DateFormatter().date(from: timestamp) }

    public init(revisionID: String, timestamp: String, size: Int64, delta: Int64?, minor: Bool) {
        self.revisionID = revisionID
        self.timestamp = timestamp
        self.size = size
        self.delta = delta
        self.minor = minor
    }

    /// A deliberately constructed external permalink, not an API-supplied URL.
    public var permalink: URL? {
        guard Self.isRevisionID(revisionID) else { return nil }
        return URL(string: "https://en.wikipedia.org/w/index.php?oldid=\(revisionID)")
    }

    public static func isRevisionID(_ value: String) -> Bool {
        value.utf8.count <= 19 && LiveSnapshotAdmission.decimal(value)
            && (Int64(value) ?? 0) > 0
    }
}

/// At most one bounded REST history segment. Its requested snapshot is
/// presentation context; the title-addressed REST history does not prove
/// that every returned revision belongs to that exact page ID.
public struct RevisionHistoryPage: Sendable, Equatable {
    public static let maximumEntries = 20
    public let requestedSnapshot: SnapshotID
    public let requestedTitle: String
    public let entries: [RevisionHistoryEntry]
    public let hasOlder: Bool

    public init(requestedSnapshot: SnapshotID, requestedTitle: String,
                entries: [RevisionHistoryEntry], hasOlder: Bool) {
        self.requestedSnapshot = requestedSnapshot
        self.requestedTitle = requestedTitle
        self.entries = entries
        self.hasOlder = hasOlder
    }

    /// Use a returned ID, never a supplied pagination URL.
    public var olderCursor: String? { hasOlder ? entries.last?.revisionID : nil }

    /// Validate bounds, identity context and the newest-first order before publication.
    public func isAdmitted(for input: RevisionHistoryInput) -> Bool {
        guard requestedSnapshot == input.snapshot,
              SourceProfile.wikipediaEnglish.admits(requestedSnapshot),
              RevisionHistoryEntry.isRevisionID(requestedSnapshot.pageID),
              RevisionHistoryEntry.isRevisionID(requestedSnapshot.revisionID),
              !requestedTitle.isEmpty, requestedTitle.utf8.count <= 512,
              entries.count <= Self.maximumEntries,
              !hasOlder || !entries.isEmpty,
              Set(entries.map(\.revisionID)).count == entries.count else { return false }
        var previous: Date?
        for entry in entries {
            guard RevisionHistoryEntry.isRevisionID(entry.revisionID),
                  entry.revisionID != input.olderThan,
                  entry.timestamp.utf8.count <= 40,
                  let date = entry.date, entry.size >= 0 else { return false }
            if let previous, date > previous { return false }
            previous = date
        }
        return true
    }
}
