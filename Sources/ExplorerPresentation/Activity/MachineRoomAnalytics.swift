// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Wall-clock drill-down, not a reconstructed monotonic bucket membership.
public struct MachineRoomBucketScope: Sendable, Equatable {
    public let runID: UUID
    public let slot: Int64
    public let start: Date
    public var end: Date { start.addingTimeInterval(5) }

    public init(runID: UUID, bucket: RequestBucket) {
        self.runID = runID
        slot = bucket.slot
        start = bucket.date
    }

    public func includes(_ event: ActivityEvent) -> Bool {
        event.runID == runID && Self.isTerminalHandler(event)
            && event.date >= start && event.date < end
    }

    fileprivate static func isTerminalHandler(_ event: ActivityEvent) -> Bool {
        guard event.origin == .externalMCP else { return false }
        switch event.outcome {
        case .success, .toolProblem, .failed, .cancelled: return true
        case .started, .stopped: return false
        }
    }
}

/// Bounded derived data. No telemetry acquisition, historical extrapolation or
/// new retention policy. The chart samples are not the full run totals.
public struct MachineRoomAnalytics: Sendable {
    public enum Tool: String, CaseIterable, Sendable {
        case search = "search_articles"
        case outline = "get_article_outline"
        case read = "read_article_section"
        case references = "get_section_references"
        case other = "Other"

        public var title: String {
            switch self {
            case .search: "Search"
            case .outline: "Outline"
            case .read: "Read"
            case .references: "References"
            case .other: "Other"
            }
        }
    }

    public struct ToolCount: Identifiable, Sendable {
        public let tool: Tool
        public let count: Int
        public var id: String { tool.rawValue }
    }

    public struct LatencySample: Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let tool: Tool
        public let milliseconds: Int64
    }

    public struct OutcomeMix: Sendable {
        public let succeeded: UInt64
        public let failed: UInt64
        public let cancelled: UInt64
    }

    public let runID: UUID
    public let buckets: [RequestBucket]
    public let recentCount: Int
    public let latency: [LatencySample]
    public let tools: [ToolCount]
    public let outcomeMix: OutcomeMix?
    public let isPartial: Bool

    public init?(projection: MachineRoomProjection) {
        guard let run = projection.runID, let metrics = projection.metrics else { return nil }
        runID = run
        buckets = metrics.buckets
        isPartial = metrics.isPartial
        let recent = metrics.recentCalls.filter { $0.runID == run && MachineRoomBucketScope.isTerminalHandler($0) }
        recentCount = recent.count
        var counts: [Tool: Int] = [:]
        latency = recent.compactMap { event in
            guard let ms = event.durationMilliseconds, ms >= 0 else { return nil }
            return LatencySample(id: event.id, date: event.date, tool: Tool(rawValue: event.operation) ?? .other, milliseconds: ms)
        }
        for event in recent {
            counts[Tool(rawValue: event.operation) ?? .other, default: 0] += 1
        }
        tools = Tool.allCases.compactMap { tool in
            let count = counts[tool, default: 0]
            return tool == .other && count == 0 ? nil : ToolCount(tool: tool, count: count)
        }
        if !metrics.isPartial, metrics.failed <= metrics.terminal,
           metrics.cancelled <= metrics.terminal - metrics.failed {
            outcomeMix = OutcomeMix(succeeded: metrics.terminal - metrics.failed - metrics.cancelled,
                                    failed: metrics.failed, cancelled: metrics.cancelled)
        } else {
            outcomeMix = nil
        }
    }

    public func bucket(slot: Int64?) -> RequestBucket? {
        guard let slot else { return nil }
        return buckets.first { $0.slot == slot }
    }

    public func bucket(containing date: Date) -> RequestBucket? {
        buckets.first { date >= $0.date && date < $0.date.addingTimeInterval(5) }
    }

    public func scope(slot: Int64?) -> MachineRoomBucketScope? {
        bucket(slot: slot).map { MachineRoomBucketScope(runID: runID, bucket: $0) }
    }

    /// Pausing is purely visual. Never retain an old run as the current chart.
    public static func chartProjection(current: MachineRoomProjection, paused: MachineRoomProjection?) -> MachineRoomProjection {
        guard current.scope == .live, let run = current.runID, current.metrics != nil,
              let paused, paused.scope == .live, paused.runID == run, paused.metrics != nil else { return current }
        return paused
    }
}
