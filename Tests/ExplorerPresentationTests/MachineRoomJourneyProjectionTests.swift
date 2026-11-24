// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import ExplorerPresentation

struct MachineRoomJourneyProjectionTests {
    @Test func fiveMilestonesAndSixRealExchangesAreSeparate() {
        let run = UUID()
        let tools = ["search_articles", "get_article_outline", "read_article_section", "get_section_references"]
        let steps = [step(0, "server/discover + tools/list", nil)] + tools.enumerated().map { step($0.offset + 1, "tools/call", $0.element) }
        let records = [exchange(0, "server/discover", nil), exchange(1, "tools/list", nil)] + tools.enumerated().map { exchange($0.offset + 2, "tools/call", $0.element) }
        let p = project(run, run, steps: steps, records: records)
        #expect(p.isCurrent && p.milestones.count == 5 && p.exchanges.count == 6)
        #expect(p.milestones.first?.validation == .preparationPassed)
        #expect(p.milestones.dropFirst().allSatisfy { $0.validation == .resultPassed })
        #expect(p.exchanges.map(\.id) == Array(1...6))
    }

    @Test func responseDoesNotImplyValidationAndDuplicateObservationsRemainVisible() {
        let run = UUID()
        let steps = [step(0, "tools/call", "search_articles"), step(1, "tools/call", "search_articles", status: .failed, validated: false)]
        let p = project(run, run, steps: steps, records: [exchange(0, "tools/call", "search_articles")])
        #expect(p.milestones[1].observations.count == 2 && p.steps.count == 2)
        #expect(p.milestones[1].validation == .notConfirmed)
        #expect(p.milestones[2].validation == .notObserved)
        #expect(p.exchanges[0].outcome == .response)
    }

    @Test func optOutAndStaleRunSuppressAllExchangeMetadata() {
        let run = UUID(), other = UUID()
        let steps = [step(0, "server/discover + tools/list", nil)]
        let records = [exchange(0, "server/discover", nil)]
        let hidden = project(run, run, steps: steps, records: records, inspect: false, dropped: 3)
        #expect(hidden.isCurrent && hidden.steps.count == 1 && !hidden.inspectionEnabled)
        #expect(hidden.exchanges.isEmpty && hidden.droppedExchanges == nil)
        for p in [project(other, run, steps: steps, records: records), project(nil, run, steps: steps, records: records), project(run, run, steps: steps, records: records, phase: .idle)] {
            #expect(!p.isCurrent && p.phase == nil && p.steps.isEmpty && p.exchanges.isEmpty)
            #expect(p.milestones.allSatisfy { $0.validation == .notObserved })
        }
    }

    @Test func paginationAndRetentionAreNotHardCodedToSix() {
        let run = UUID()
        let records = (0..<40).map { exchange($0, "tools/list", nil) }
        let p = project(run, run, steps: [], records: records, dropped: 2)
        #expect(p.exchanges.count == 32 && p.droppedExchanges == 10)
        #expect(p.exchanges.last?.id == 32)
        #expect(project(run, run, steps: [], records: records, dropped: Int.max).droppedExchanges == nil)
    }

    @Test func invalidMeasurementsAndUnknownNamesAreNotInventedOrExposed() {
        let run = UUID()
        let record = ExchangeRecord(id: 0, method: "untrusted", tool: "secret", requestBytes: -1, messages: 0, responseBytes: 0, outcome: .cancelled, milliseconds: -1)
        let p = project(run, run, steps: [], records: [record], phase: .cancelled)
        let x = p.exchanges[0]
        #expect(x.method == "Other method" && x.tool == nil)
        #expect(x.requestBytes == nil && x.milliseconds == nil)
        #expect(x.responseBytes == 0 && x.messages == 0 && x.outcome == .cancelled)
    }

    private func project(_ current: UUID?, _ owner: UUID?, steps: [MCPJourneyStep], records: [ExchangeRecord], inspect: Bool = true, dropped: Int = 0, phase: MCPJourneyPhase = .completed) -> MachineRoomJourneyProjection {
        .init(currentRunID: current, journeyRunID: owner, phase: phase, steps: steps, inspectionEnabled: inspect, records: records, dropped: dropped)
    }

    private func step(_ id: Int, _ method: String, _ tool: String?, status: MCPJourneyStep.Status = .succeeded, validated: Bool = true) -> MCPJourneyStep {
        .init(id: id, method: method, tool: tool, status: status, validated: validated, milliseconds: 12, revisionID: nil, failure: nil)
    }

    private func exchange(_ id: Int, _ method: String, _ tool: String?) -> ExchangeRecord {
        .init(id: id, method: method, tool: tool, requestBytes: 10, messages: 1, responseBytes: 20, outcome: .response, milliseconds: 3)
    }
}
