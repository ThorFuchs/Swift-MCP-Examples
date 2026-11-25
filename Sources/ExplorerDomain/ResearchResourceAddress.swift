// SPDX-License-Identifier: Apache-2.0
import Foundation

/// An application-owned, cache-only address. It is not an HTTP URL, a
/// persistent locator, or authorization to fetch a Wikipedia revision.
public struct ResearchResourceAddress: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case outline, section(String) }
    public let snapshot: SnapshotID
    public let kind: Kind

    public init?(snapshot: SnapshotID, kind: Kind) {
        let profile: SourceProfile = snapshot.project == "enwiki" ? .wikipediaEnglish : .offlineDemo
        guard profile.admits(snapshot),
              Normalizer.component(snapshot.provider), Normalizer.component(snapshot.project),
              Normalizer.component(snapshot.normalizerVersion) else { return nil }
        if profile == .wikipediaEnglish {
            guard RevisionHistoryEntry.isRevisionID(snapshot.pageID), RevisionHistoryEntry.isRevisionID(snapshot.revisionID) else { return nil }
        }
        if case .section(let part) = kind, !Normalizer.component(part) { return nil }
        self.snapshot = snapshot; self.kind = kind
    }

    public static let outlineTemplate = "wre://knowledge/{provider}/{project}/{page}/{revision}/{normalizer}/outline"
    public static let sectionTemplate = "wre://knowledge/{provider}/{project}/{page}/{revision}/{normalizer}/part/{part}/section"

    public var uri: String {
        let prefix = "wre://knowledge/\(snapshot.provider)/\(snapshot.project)/\(snapshot.pageID)/\(snapshot.revisionID)/\(snapshot.normalizerVersion)"
        switch kind {
        case .outline: return prefix + "/outline"
        case .section(let part): return prefix + "/part/" + part + "/section"
        }
    }

    /// Strict canonical ASCII components. Percent escapes, foreign schemes,
    /// query, fragment, empty components, credentials and traversal are denied.
    public init?(uri: String) {
        let prefix = "wre://knowledge/"
        guard uri.utf8.count <= 1024, uri.hasPrefix(prefix) else { return nil }
        let parts = uri.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6 || parts.count == 8, parts.allSatisfy(Normalizer.component) else { return nil }
        let snapshot = SnapshotID(provider: parts[0], project: parts[1], pageID: parts[2],
                                  revisionID: parts[3], normalizerVersion: parts[4])
        let kind: Kind
        if parts.count == 6 && parts[5] == "outline" { kind = .outline }
        else if parts.count == 8 && parts[5] == "part" && parts[7] == "section" { kind = .section(parts[6]) }
        else { return nil }
        guard let canonical = Self(snapshot: snapshot, kind: kind), canonical.uri == uri else { return nil }
        self = canonical
    }
}
