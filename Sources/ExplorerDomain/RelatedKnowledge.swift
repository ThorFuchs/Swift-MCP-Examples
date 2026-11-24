// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A bounded, ordered sample of internal article-title links from the selected
/// normalized section's own content (not its descendants). This is navigation
/// metadata, not a citation or an assertion that a target page exists.
public struct RelatedKnowledge: Codable, Sendable, Equatable {
    public static let maximumTitles = 12
    public static let maximumTitleBytes = 256
    public static let maximumSnapshotTitles = 256
    public static let maximumSnapshotBytes = 32768

    public let titles: [String]
    public let truncated: Bool

    public init(titles: [String], truncated: Bool) {
        self.titles = titles
        self.truncated = truncated
    }

    /// Only the supported relative Parsoid article link form is accepted.
    /// No URL is fetched. Decode once, strip an optional section fragment,
    /// reject namespaces, query strings, traversal and control characters.
    public static func title(fromParsoidHref href: String) -> String? {
        guard href.utf8.count <= 2048, href.hasPrefix("./") else { return nil }
        let raw = String(href.dropFirst(2).prefix(while: { $0 != "#" }))
        guard !raw.contains("?"), let decoded = raw.removingPercentEncoding else { return nil }
        let title = decoded.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isAdmittedTitle(title) ? title : nil
    }

    public static func isAdmittedTitle(_ title: String) -> Bool {
        !title.isEmpty && title.utf8.count <= maximumTitleBytes
            && title == title.trimmingCharacters(in: .whitespacesAndNewlines)
            && !title.hasPrefix("/") && !title.contains("\\") && !title.contains(":")
            && !title.contains("#") && !title.contains("?")
            && !title.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." || $0.isEmpty })
            && !title.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
            })
    }

    /// Recheck owned metadata both at snapshot admission and the SDK client.
    public var isAdmitted: Bool {
        titles.count <= Self.maximumTitles && Set(titles).count == titles.count
            && titles.allSatisfy(Self.isAdmittedTitle)
    }
}
