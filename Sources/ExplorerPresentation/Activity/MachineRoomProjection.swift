// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A read-only, run-scoped projection of the existing observation pipeline.
/// Neither the UI nor this value owns a listener, sampler or task.
public struct MachineRoomProjection: Sendable {
    /// Whether the matched observation is live, historical, absent or transitioning.
    /// No scope implies listener readiness unless the controller reports it.
    public enum Scope: String, Sendable, Equatable {
        case unavailable = "Unavailable"
        case idle = "Not started"
        case awaitingSnapshot = "Awaiting observation"
        case unobservedRun = "Run not observed"
        case starting = "Starting"
        case live = "Live"
        case stopping = "Stopping"
        case lastRun = "Last run"
        case failedRun = "Failed run"
    }

    /// A bounded snapshot of eligible catalogue-handler observation.
    /// Counts describe observed terminal paths, not network requests or all successes.
    public struct Metrics: Sendable {
        /// Currently tracked eligible handler invocations.
        public let active: Int
        /// All terminated eligible handlers, including failures and cancellation.
        public let terminal: UInt64
        /// Observed failed or tool-problem terminal invocations.
        public let failed: UInt64
        /// Observed cancelled terminal invocations, distinct from failures.
        public let cancelled: UInt64
        /// Median duration in the retained five-minute sample, or nil without a sample.
        public let medianMilliseconds: Int64?
        /// Number of retained duration samples used by the median (at most 512).
        public let durationSampleCount: Int
        /// Up to 60 five-second buckets from the existing store.
        public let buckets: [RequestBucket]
        /// Up to 50 retained terminal call events for the same run.
        public let recentCalls: [ActivityEvent]
        /// Sum of bucket counts, or nil when the sum cannot be represented.
        public let windowTerminalCount: UInt64?
        /// True if observation is partial or aggregate counts do not reconcile.
        public let isPartial: Bool

        fileprivate init(snapshot: ActivitySnapshot, runID: UUID) {
            active = snapshot.active
            terminal = snapshot.completed
            failed = snapshot.failed
            cancelled = snapshot.cancelled
            medianMilliseconds = snapshot.durationSampleCount > 0 ? snapshot.medianMilliseconds : nil
            durationSampleCount = snapshot.durationSampleCount
            // The store already bounds these collections. Keep the presentation
            // projection bounded as well and never surface another run's events.
            buckets = Array(snapshot.buckets.suffix(60))
            recentCalls = Array(snapshot.recentCalls.filter { $0.runID == runID }.suffix(50))
            var sum: UInt64 = 0
            var overflow = false
            for bucket in buckets {
                let next = sum.addingReportingOverflow(bucket.calls)
                if next.overflow { overflow = true; break }
                sum = next.partialValue
            }
            windowTerminalCount = overflow ? nil : sum
            // Never subtract before checking the bounds: counts may be partial.
            let inconsistent = failed > terminal || cancelled > terminal - min(failed, terminal)
            isPartial = snapshot.metricsPartial || overflow || inconsistent
        }
    }

    /// Presentation scope derived from the controller and snapshot identity.
    public let scope: Scope
    /// Controller-owned run identity, even while its matching snapshot is unavailable.
    public let runID: UUID?
    /// Nil when no matching observation is available; never substitute measured zeros.
    public let metrics: Metrics?

    /// Controller state and the asynchronously sampled store must name the same
    /// run. After restart or a source switch, suppress the stale store snapshot
    /// until it belongs to the currently selected controller.
    /// - Parameters:
    ///   - phase: The controller's reported phase, or nil without a controller.
    ///   - controllerRunID: Identity of the controller's selected run.
    ///   - snapshot: The existing bounded activity-store observation.
    public init(phase: ServerPhase?, controllerRunID: UUID?, snapshot: ActivitySnapshot) {
        runID = controllerRunID
        guard let phase else {
            scope = .unavailable
            metrics = nil
            return
        }
        guard let id = controllerRunID else {
            scope = phase == .stopped ? .idle : .unobservedRun
            metrics = nil
            return
        }
        guard snapshot.runID == id else {
            switch phase {
            case .starting, .running, .stopping: scope = .awaitingSnapshot
            case .stopped, .failed: scope = .unobservedRun
            }
            metrics = nil
            return
        }
        switch phase {
        case .starting: scope = .starting
        case .running: scope = .live
        case .stopping: scope = .stopping
        case .stopped: scope = .lastRun
        case .failed: scope = .failedRun
        }
        metrics = Metrics(snapshot: snapshot, runID: id)
    }
}
