// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import ExplorerDomain

public enum LiveFailure: Error, Sendable, Equatable {
    case url, redirect, bodyLimit, malformed, unsupportedHTML, identity, expiredCandidate, concurrentLimit
}
public enum WikipediaRoute {
    public static let origin = "https://en.wikipedia.org"
    public static func search(_ query: String, limit: Int) throws -> URL {
        guard !query.isEmpty, query.utf8.count <= 256, (1...20).contains(limit) else { throw LiveFailure.url }
        var c = URLComponents(string: origin + "/w/rest.php/v1/search/page")!
        c.queryItems = [.init(name: "q", value: query), .init(name: "limit", value: String(limit))]
        guard let url = c.url else { throw LiveFailure.url }; return url
    }
    public static func page(_ key: String) throws -> URL {
        guard !key.isEmpty, key.utf8.count <= 1024 else { throw LiveFailure.url }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let segment = key.addingPercentEncoding(withAllowedCharacters: safe), segment != ".", segment != "..",
              let url = URL(string: origin + "/w/rest.php/v1/page/" + segment + "/with_html") else { throw LiveFailure.url }
        return url
    }
    /// Constructs the title-addressed history endpoint from an already
    /// admitted returned key; pagination is a bounded numeric cursor.
    public static func history(_ key: String, olderThan: String? = nil) throws -> URL {
        var components = URLComponents(url: try page(key), resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = String(components.percentEncodedPath.dropLast("/with_html".count)) + "/history"
        if let olderThan {
            guard RevisionHistoryEntry.isRevisionID(olderThan) else { throw LiveFailure.url }
            components.queryItems = [.init(name: "older_than", value: olderThan)]
        }
        guard let url = components.url, allowed(url) else { throw LiveFailure.url }
        return url
    }

    /// Exact revision-addressed REST endpoint; no title, URL or query from the response.
    public static func revision(_ id: String) throws -> URL {
        guard RevisionHistoryEntry.isRevisionID(id),
              let url = URL(string: origin + "/w/rest.php/v1/revision/" + id + "/with_html") else { throw LiveFailure.url }
        return url
    }

    static func isRevisionRoute(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.percentEncodedPath.hasPrefix("/w/rest.php/v1/revision/")
    }

    static func isHistoryRoute(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let path = components.percentEncodedPath
        return path.hasPrefix("/w/rest.php/v1/page/") && path.hasSuffix("/history")
    }

    public static func allowed(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https",
              c.host == "en.wikipedia.org", c.user == nil, c.password == nil, c.port == nil, c.fragment == nil else { return false }
        let p = c.percentEncodedPath
        if p == "/w/rest.php/v1/search/page" {
            let q = c.queryItems ?? []
            return q.count == 2 && Set(q.map(\.name)) == Set(["q", "limit"])
                && (q.first(where: { $0.name == "q" })?.value?.utf8.count ?? 0) <= 256
                && (1...20).contains(Int(q.first(where: { $0.name == "limit" })?.value ?? "") ?? 0)
        }
        if isRevisionRoute(url) {
            let prefix = "/w/rest.php/v1/revision/", suffix = "/with_html"
            guard c.query == nil, p.hasSuffix(suffix), p.count > prefix.count + suffix.count else { return false }
            return RevisionHistoryEntry.isRevisionID(String(p.dropFirst(prefix.count).dropLast(suffix.count)))
        }
        let history = isHistoryRoute(url)
        let prefix = "/w/rest.php/v1/page/", suffix = history ? "/history" : "/with_html"
        guard p.hasPrefix(prefix), p.hasSuffix(suffix) else { return false }
        let segment = String(p.dropFirst(prefix.count).dropLast(suffix.count))
        guard !segment.isEmpty && !segment.contains("/") && segment != "." && segment != ".." && segment.utf8.count <= 3072 else { return false }
        if !history { return c.query == nil }
        if c.query == nil { return true }
        guard let items = c.queryItems, items.count == 1,
              items[0].name == "older_than", let cursor = items[0].value else { return false }
        return RevisionHistoryEntry.isRevisionID(cursor)
    }
}

public struct LiveHTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public let headers: [String: String]
    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status; self.body = body; self.headers = headers
    }
}
/// A transport invocation owns and settles its one iterator before returning.
public protocol LiveTransport: Sendable {
    func get(_ url: URL, deadline: ContinuousClock.Instant) async throws -> LiveHTTPResponse
}
private final class OwnedWikipediaRequest: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var task: URLSessionDataTask?
        var continuation: CheckedContinuation<LiveHTTPResponse, any Error>?
        var response: HTTPURLResponse?
        var body = Data()
        var failure: (any Error)?
        var redirects = 0
        var completed = false
    }
    private let state = Mutex(State())
    private let deadline: ContinuousClock.Instant
    private let allowedURL: @Sendable (URL) -> Bool
    init(deadline: ContinuousClock.Instant, allowedURL: @escaping @Sendable (URL) -> Bool) {
        self.deadline = deadline; self.allowedURL = allowedURL
    }

    func start(session: URLSession, request: URLRequest, continuation: CheckedContinuation<LiveHTTPResponse, any Error>) {
        let task = session.dataTask(with: request)
        let cancelled = state.withLock { value in
            value.task = task; value.continuation = continuation
            return value.failure != nil
        }
        task.resume()
        if cancelled { task.cancel() }
    }
    func cancel(_ failure: any Error) {
        let task = state.withLock { value -> URLSessionDataTask? in
            guard !value.completed else { return nil }
            if value.failure == nil { value.failure = failure }
            return value.task
        }
        task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let allowed = state.withLock { value in
            guard value.failure == nil, value.redirects < 3, let url = request.url,
                  allowedURL(url), request.httpMethod == "GET" else {
                if value.failure == nil { value.failure = LiveFailure.redirect }
                return false
            }
            value.redirects += 1; return true
        }
        completionHandler(allowed ? request : nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let accepted = state.withLock { value in
            guard value.failure == nil, let http = response as? HTTPURLResponse,
                  let url = http.url, allowedURL(url) else {
                if value.failure == nil { value.failure = LiveFailure.redirect }; return false
            }
            let maximum = http.statusCode == 200 ? 4_194_304 : 8192
            guard response.expectedContentLength <= Int64(maximum) else { value.failure = LiveFailure.bodyLimit; return false }
            value.response = http; return true
        }
        completionHandler(accepted ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let stop = state.withLock { value in
            guard value.failure == nil, let response = value.response else { return true }
            guard ContinuousClock.now < deadline else { value.failure = SourceProfile.wikipediaEnglish.problem(.upstreamTimedOut); return true }
            let maximum = response.statusCode == 200 ? 4_194_304 : 8192
            guard data.count <= maximum - value.body.count else { value.failure = LiveFailure.bodyLimit; return true }
            value.body.append(data); return false
        }
        if stop { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let completion = state.withLock { value -> (CheckedContinuation<LiveHTTPResponse, any Error>, Result<LiveHTTPResponse, any Error>)? in
            guard !value.completed, let continuation = value.continuation else { return nil }
            value.completed = true; value.continuation = nil; value.task = nil
            if let failure = value.failure { return (continuation, .failure(failure)) }
            // The request timeout is derived from this deadline: whichever of it and the
            // deadline timer fires first, the outcome is the same deadline (#28).
            if let error = error as? URLError, error.code == .timedOut {
                return (continuation, .failure(SourceProfile.wikipediaEnglish.problem(.upstreamTimedOut)))
            }
            if let error { return (continuation, .failure(error)) }
            guard ContinuousClock.now < deadline else { return (continuation, .failure(SourceProfile.wikipediaEnglish.problem(.upstreamTimedOut))) }
            guard let response = value.response else { return (continuation, .failure(LiveFailure.malformed)) }
            var headers: [String: String] = [:]
            for name in ["Content-Type", "ETag", "Last-Modified", "Retry-After"] {
                if let header = response.value(forHTTPHeaderField: name) {
                    guard header.utf8.count <= 1024 else { return (continuation, .failure(LiveFailure.malformed)) }
                    headers[name] = header
                }
            }
            return (continuation, .success(.init(status: response.statusCode, body: value.body, headers: headers)))
        }
        if let (continuation, result) = completion { continuation.resume(with: result) }
    }
}

/// Each request owns its session, data task, delegate and deadline timer. The
/// data-task completion callback is the settlement boundary, including failures.
public actor WikipediaHTTPTransport: LiveTransport {
    private let configuration: URLSessionConfiguration
    private let allowedURL: @Sendable (URL) -> Bool
    public init() {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil; c.httpCookieStorage = nil; c.urlCredentialStorage = nil
        c.httpShouldSetCookies = false; c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 15; c.timeoutIntervalForResource = 15
        c.httpMaximumConnectionsPerHost = 2
        configuration = c; allowedURL = WikipediaRoute.allowed
    }
    // Internal seam for controlled URLSession fixtures in native tests.
    init(configuration: sending URLSessionConfiguration,
         allowedURL: @escaping @Sendable (URL) -> Bool = WikipediaRoute.allowed) {
        self.configuration = configuration; self.allowedURL = allowedURL
    }
    public func get(_ url: URL, deadline: ContinuousClock.Instant) async throws -> LiveHTTPResponse {
        guard allowedURL(url) else { throw LiveFailure.url }
        try Task.checkCancellation()
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else { throw SourceProfile.wikipediaEnglish.problem(.upstreamTimedOut) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = min(15, Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18)
        request.setValue("ResearchExplorer/0.1 (https://github.com/ThorFuchs)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // History lacks a page identity in its segment envelope. Keep the
        // exact title/cursor URL; never let a redirect silently retarget it.
        // Adding history to the allowlist must not widen prior operations.
        let basePolicy = allowedURL, exactRoute = WikipediaRoute.isHistoryRoute(url) || WikipediaRoute.isRevisionRoute(url)
        let owner = OwnedWikipediaRequest(deadline: deadline, allowedURL: { target in
            guard basePolicy(target) else { return false }
            return exactRoute ? target.absoluteString == url.absoluteString : !WikipediaRoute.isHistoryRoute(target) && !WikipediaRoute.isRevisionRoute(target)
        })
        let session = URLSession(configuration: configuration, delegate: owner, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let timer = Task {
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
                owner.cancel(SourceProfile.wikipediaEnglish.problem(.upstreamTimedOut))
            } catch { /* completion owns and joins the cancelled timer */ }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    owner.start(session: session, request: request, continuation: continuation)
                }
            } onCancel: { owner.cancel(CancellationError()) }
            timer.cancel(); await timer.value
            try Task.checkCancellation()
            return result
        } catch {
            timer.cancel(); await timer.value
            throw error
        }
    }
}
