// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Explicit request for a different revision of the same admitted page.
/// The response must prove both page and revision identities independently.
public struct HistoricalRevisionInput: Sendable {
    public let pinned: SnapshotID
    public let revisionID: String

    public init(pinned: SnapshotID, revisionID: String) {
        self.pinned = pinned
        self.revisionID = revisionID
    }

    public var isAdmitted: Bool {
        SourceProfile.wikipediaEnglish.admits(pinned)
            && RevisionHistoryEntry.isRevisionID(pinned.pageID)
            && RevisionHistoryEntry.isRevisionID(pinned.revisionID)
            && RevisionHistoryEntry.isRevisionID(revisionID)
            && pinned.revisionID != revisionID
    }

    public var expectedSnapshot: SnapshotID {
        .init(provider: pinned.provider, project: pinned.project, pageID: pinned.pageID,
              revisionID: revisionID, normalizerVersion: pinned.normalizerVersion)
    }
}

/// The revision endpoint does not guarantee a license field. Do not copy a
/// current-page license onto an old revision. This owned marker permits local
/// reading, but blocks collection and MCP resource export of the excerpt.
public enum HistoricalRevisionLicense {
    public static let missingTitle = "Historical revision license not supplied; verify original before reuse"
    public static let policyURL = "https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use"
    public static let unavailable = missingTitle + " · " + policyURL

    public static func permitsCollection(_ provenance: Provenance) -> Bool {
        provenance.license != unavailable
    }
}
