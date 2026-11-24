// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Read-only view of one guided journey. Planned milestones are not exchanges.
/// No traffic acquisition, timers, timestamp reconstruction or payload access.
public struct MachineRoomJourneyProjection: Sendable {
    /// Five planned workflow stages; preparation may contain multiple actual exchanges.
    public enum Stage: String, CaseIterable, Sendable {
        case prepare = "Prepare"
        case search = "Search"
        case outline = "Outline"
        case read = "Read"
        case references = "References"

        fileprivate func matches(_ step: MCPJourneyStep) -> Bool {
            switch self {
            case .prepare: return step.tool == nil && (step.method == "server/discover + tools/list" || step.method == "server/discover")
            case .search: return step.method == "tools/call" && step.tool == "search_articles"
            case .outline: return step.method == "tools/call" && step.tool == "get_article_outline"
            case .read: return step.method == "tools/call" && step.tool == "read_article_section"
            case .references: return step.method == "tools/call" && step.tool == "get_section_references"
            }
        }
    }

    /// Validation evidence from the latest observed milestone, not from transport success.
    public enum Validation: String, Sendable {
        case notObserved = "Not observed"
        case preparationPassed = "Protocol + catalogue checked"
        case resultPassed = "Schema + identity checked"
        case notConfirmed = "Validation not confirmed"
    }

    /// One planned stage and all retained observations matching it, in observation order.
    public struct Milestone: Identifiable, Sendable {
        /// Planned workflow stage.
        public let stage: Stage
        /// Actual retained matching step observations; may be empty or repeated.
        public let observations: [MCPJourneyStep]
        public var id: String { stage.rawValue }
        /// Last retained matching step, if any.
        public var latest: MCPJourneyStep? { observations.last }
        /// Distinguishes preparation checks, tool result checks and unconfirmed validation.
        public var validation: Validation {
            guard let latest else { return .notObserved }
            guard latest.status == .succeeded, latest.validated else { return .notConfirmed }
            return stage == .prepare ? .preparationPassed : .resultPassed
        }
    }

    /// Sanitized view of one retained opt-in SDK transport record.
    public struct Exchange: Identifiable, Sendable {
        /// One-based retained order, not a transport request ID or start timestamp.
        public let id: Int
        /// Known protocol method, or Other method when unrecognized.
        public let method: String
        /// Recognized catalogue tool, if applicable.
        public let tool: String?
        /// Measured exchange duration, or nil for an invalid measurement.
        public let milliseconds: Int?
        /// Outgoing SDK request-body bytes, not HTTP or TLS framing.
        public let requestBytes: Int?
        /// Delivered incoming SDK message bytes, not TCP traffic.
        public let responseBytes: Int?
        /// Delivered SDK message count; nil if invalid.
        public let messages: Int?
        /// Transport outcome, not proof of JSON-RPC success or result validation.
        public let outcome: ExchangeRecord.Outcome
        /// Ordinal and known method/tool for synchronized chart selection.
        public var label: String { "#\(id) · \(tool ?? method)" }
    }

    /// Actual journey phase, or nil for an idle or mismatched run.
    public let phase: MCPJourneyPhase?
    /// True only for a non-idle journey owned by the selected server run.
    public let isCurrent: Bool
    /// Exactly five planned stages; unobserved stages carry no synthetic progress.
    public let milestones: [Milestone]
    /// At most eight actual step observations for the matching run.
    public let steps: [MCPJourneyStep]
    /// True only when inspection is opted in and the journey belongs to the selected run.
    public let inspectionEnabled: Bool
    /// At most 32 sanitized opt-in records for the matching run; otherwise empty.
    public let exchanges: [Exchange]
    /// Known unretained count, or nil when inspection is unavailable or count overflows.
    public let droppedExchanges: Int?

    /// Projects an existing journey without starting a task or recording traffic.
    /// - Parameters:
    ///   - currentRunID: Identity of the selected server run.
    ///   - journeyRunID: Run that owned the guided journey at its start.
    ///   - phase: Actual controller phase.
    ///   - steps: Actual retained milestone observations.
    ///   - inspectionEnabled: Current explicit inspection preference.
    ///   - records: Retained SDK exchange metadata, never request or response bodies.
    ///   - dropped: Count already reported as not retained.
    public init(currentRunID: UUID?, journeyRunID: UUID?, phase: MCPJourneyPhase,
                steps: [MCPJourneyStep], inspectionEnabled: Bool, records: [ExchangeRecord], dropped: Int) {
        let current = currentRunID != nil && currentRunID == journeyRunID && phase != .idle
        let visibleSteps = current ? Array(steps.prefix(8)) : []
        let inspection = current && inspectionEnabled
        self.isCurrent = current
        self.phase = current ? phase : nil
        self.steps = visibleSteps
        milestones = Stage.allCases.map { stage in
            Milestone(stage: stage, observations: visibleSteps.filter { stage.matches($0) })
        }
        self.inspectionEnabled = inspection
        let knownTools = ["search_articles", "get_article_outline", "read_article_section", "get_section_references"]
        exchanges = inspection ? records.prefix(32).enumerated().map { offset, record in
            let method = ["server/discover", "tools/list", "tools/call"].contains(record.method) ? record.method : "Other method"
            let tool = method == "tools/call" ? record.tool.flatMap { knownTools.contains($0) ? $0 : nil } : nil
            return Exchange(id: offset + 1, method: method, tool: tool,
                milliseconds: Self.nonnegative(record.milliseconds), requestBytes: Self.nonnegative(record.requestBytes),
                responseBytes: Self.nonnegative(record.responseBytes), messages: Self.nonnegative(record.messages), outcome: record.outcome)
        } : []
        if inspection, dropped >= 0 {
            let total = dropped.addingReportingOverflow(max(0, records.count - 32))
            droppedExchanges = total.overflow ? nil : total.partialValue
        } else {
            droppedExchanges = nil
        }
    }

    private static func nonnegative(_ value: Int) -> Int? { value >= 0 ? value : nil }
}
