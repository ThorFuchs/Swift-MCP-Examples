// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Wall-clock drill-down, not a reconstructed monotonic bucket membership.
public struct MachineRoomBucketScope: Sendable, Equatable {
    /// Server run whose retained events may match this interval.
    public let runID: UUID
    /// Monotonic histogram slot identifier.
    public let slot: Int64
    /// Displayed wall-clock interval start (inclusive).
    public let start: Date
    /// Displayed wall-clock interval end (exclusive).
    public var end: Date { start.addingTimeInterval(5) }

    /// Creates a wall-clock filter from a run and its selected bucket.
    public init(runID: UUID, bucket: RequestBucket) {
        self.runID = runID
        slot = bucket.slot
        start = bucket.date
    }

    /// Returns true only for retained eligible terminal events in the same run and half-open wall-clock interval.
    /// This does not assert exact membership in the monotonic histogram.
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
    /// Fixed catalogue-tool grouping, with an explicit Other bucket for unknown names.
    public enum Tool: String, CaseIterable, Sendable {
        case search = "search_articles"
        case outline = "get_article_outline"
        case read = "read_article_section"
        case references = "get_section_references"
        case other = "Other"

        /// Human-readable tool label used in charts.
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

    /// Count of a tool in the retained terminal sample, not a full-run count.
    public struct ToolCount: Identifiable, Sendable {
        public let tool: Tool
        public let count: Int
        public var id: String { tool.rawValue }
    }

    /// A measured nonnegative handler duration with its actual terminal event identity and date.
    public struct LatencySample: Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let tool: Tool
        public let milliseconds: Int64
    }

    /// Reconciled per-run terminal counts. Only available for coherent, nonpartial observation.
    public struct OutcomeMix: Sendable {
        public let succeeded: UInt64
        public let failed: UInt64
        public let cancelled: UInt64
    }

    /// Identity of the run that owns every projected sample.
    public let runID: UUID
    /// The original bounded rolling histogram for this run.
    public let buckets: [RequestBucket]
    /// Number of eligible retained terminal calls used by the secondary charts (at most 50).
    public let recentCount: Int
    /// Measured duration samples; missing or invalid values are omitted.
    public let latency: [LatencySample]
    /// Retained sample grouped by fixed tool vocabulary.
    public let tools: [ToolCount]
    /// Nil when success cannot be inferred safely from coherent complete observed counts.
    public let outcomeMix: OutcomeMix?
    /// Whether the source projection discloses partial observation.
    public let isPartial: Bool

    /// Derives analytics from a matching run projection, or returns nil when no metrics exist.
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

    /// Returns the retained bucket for a stable slot identifier, if it remains available.
    public func bucket(slot: Int64?) -> RequestBucket? {
        guard let slot else { return nil }
        return buckets.first { $0.slot == slot }
    }

    /// Returns the retained bucket containing the displayed date using half-open intervals.
    public func bucket(containing date: Date) -> RequestBucket? {
        buckets.first { date >= $0.date && date < $0.date.addingTimeInterval(5) }
    }

    /// Builds a run-scoped retained-event filter for a selected bucket, if present.
    public func scope(slot: Int64?) -> MachineRoomBucketScope? {
        bucket(slot: slot).map { MachineRoomBucketScope(runID: runID, bucket: $0) }
    }

    /// Pausing is purely visual. Never retain an old run as the current chart.
    /// - Parameters:
    ///   - current: The most recent run-matched projection, always authoritative for lifecycle.
    ///   - paused: An optional frozen chart projection.
    /// - Returns: The frozen projection only while both snapshots belong to the same live run; otherwise the current projection.
    public static func chartProjection(current: MachineRoomProjection, paused: MachineRoomProjection?) -> MachineRoomProjection {
        guard current.scope == .live, let run = current.runID, current.metrics != nil,
              let paused, paused.scope == .live, paused.runID == run, paused.metrics != nil else { return current }
        return paused
    }
}
