// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Read-only view of one guided journey. Planned milestones are not exchanges.
/// No traffic acquisition, timers, timestamp reconstruction or payload access.
public struct MachineRoomJourneyProjection: Sendable {
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

    public enum Validation: String, Sendable {
        case notObserved = "Not observed"
        case preparationPassed = "Protocol + catalogue checked"
        case resultPassed = "Schema + identity checked"
        case notConfirmed = "Validation not confirmed"
    }

    public struct Milestone: Identifiable, Sendable {
        public let stage: Stage
        public let observations: [MCPJourneyStep]
        public var id: String { stage.rawValue }
        public var latest: MCPJourneyStep? { observations.last }
        public var validation: Validation {
            guard let latest else { return .notObserved }
            guard latest.status == .succeeded, latest.validated else { return .notConfirmed }
            return stage == .prepare ? .preparationPassed : .resultPassed
        }
    }

    public struct Exchange: Identifiable, Sendable {
        public let id: Int
        public let method: String
        public let tool: String?
        public let milliseconds: Int?
        public let requestBytes: Int?
        public let responseBytes: Int?
        public let messages: Int?
        public let outcome: ExchangeRecord.Outcome
        public var label: String { "#\(id) · \(tool ?? method)" }
    }

    public let phase: MCPJourneyPhase?
    public let isCurrent: Bool
    public let milestones: [Milestone]
    public let steps: [MCPJourneyStep]
    public let inspectionEnabled: Bool
    public let exchanges: [Exchange]
    public let droppedExchanges: Int?

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
