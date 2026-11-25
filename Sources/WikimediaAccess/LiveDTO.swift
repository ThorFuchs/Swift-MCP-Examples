// SPDX-License-Identifier: Apache-2.0
import Foundation
import JSON
import ExplorerDomain

struct RESTSearch: Decodable, Sendable {
    struct Page: Decodable, Sendable { let id: Int64; let key, title: String; let description: String? }
    let pages: [Page]
}
public struct RESTPage: Decodable, Sendable {
    public struct Revision: Decodable, Sendable { public let id: Int64; public let timestamp: String }
    public struct License: Decodable, Sendable { public let url, title: String }
    public let id: Int64
    public let key, title: String
    public let latest: Revision
    public let contentModel: String
    public let license: License
    public let html: String
    enum CodingKeys: String, CodingKey { case id, key, title, latest, contentModel = "content_model", license, html }
}
/// MediaWiki history segment. Unknown fields (including user and comment)
/// are deliberately not decoded into the owned presentation model.
struct RESTHistory: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        let id: Int64
        let timestamp: String
        let size: Int64
        let delta: Int64?
        let minor: Bool
    }
    let revisions: [Row]
    let older: String?
}

/// The documented revision envelope, distinct from RESTPage. Only metadata
/// required for admission is decoded; no editor identifiers/comments retained.
struct RESTHistoricalRevision: Decodable, Sendable {
    struct Page: Decodable, Sendable { let id: Int64; let key, title: String }
    let id: Int64
    let timestamp: String
    let page: Page
    let contentModel: String
    let html: String
    let license: RESTPage.License?
    enum CodingKeys: String, CodingKey { case id, timestamp, page, contentModel = "content_model", html, license }

    /// Adapt the verified revision envelope to the existing normalizer input.
    /// The marker is not a claim about the actual historical license.
    func normalizationInput(for input: HistoricalRevisionInput) throws -> RESTPage {
        guard input.isAdmitted, String(id) == input.revisionID,
              String(page.id) == input.pinned.pageID, contentModel == "wikitext",
              !page.key.isEmpty, page.key.utf8.count <= 1024,
              !page.title.isEmpty, page.title.utf8.count <= 512,
              timestamp.utf8.count <= 40, ISO8601DateFormatter().date(from: timestamp) != nil else { throw LiveFailure.identity }
        _ = try WikipediaRoute.page(page.key)
        let admittedLicense = license ?? .init(url: HistoricalRevisionLicense.policyURL, title: HistoricalRevisionLicense.missingTitle)
        guard !admittedLicense.title.isEmpty else { throw LiveFailure.malformed }
        return RESTPage(id: page.id, key: page.key, title: page.title, latest: .init(id: id, timestamp: timestamp),
                        contentModel: contentModel, license: admittedLicense, html: html)
    }
}

enum RESTCodec {
    static func decode<T: Decodable & Sendable>(_ type: T.Type, _ data: Data) throws -> T {
        guard data.count <= 4_194_304 else { throw LiveFailure.bodyLimit }
        var limits = JSONLimits.balanced
        limits[.inputBytes] = 4_194_304; limits[.stringBytes] = 4_194_304
        limits[.maxDepth] = 32; limits[.workUnits] = 64_000_000
        let parsed = try JSONParser(options: .init(limits: limits)).parseWithReport(Array(data)).result
        return try JSONValueDecoder(options: .init(limits: limits)).decodeWithReport(type, from: parsed).result
    }
}
