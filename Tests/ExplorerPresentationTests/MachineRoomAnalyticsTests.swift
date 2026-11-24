// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import Synchronization
@testable import ExplorerPresentation

struct MachineRoomAnalyticsTests {
    @Test func samplesAreBoundedAndRunTotalsAreNotSampleTotals() async throws {
        let ticks = Mutex<Int64>(0)
        let store = ActivityStore(clock: .init(milliseconds: { ticks.withLock { $0 } }, wall: { Date(timeIntervalSince1970: 1000 + Double(ticks.withLock { $0 }) / 1000) }))
        let run = UUID()
        try await store.beginRun(run)
        for i in 0..<56 {
            let token = await store.startCall(run: run, operation: i < 6 ? "get_article_outline" : "search_articles")
            ticks.withLock { $0 += 10 }
            await store.finishCall(token, outcome: i == 55 ? .cancelled : .success)
        }
        await store.localResearch("read_article_section", success: true)
        let p = MachineRoomProjection(phase: .running, controllerRunID: run, snapshot: await store.snapshot())
        let a = try #require(MachineRoomAnalytics(projection: p))
        #expect(a.recentCount == 50 && a.latency.count == 50)
        #expect(a.latency.allSatisfy { $0.milliseconds == 10 && $0.tool == .search })
        #expect(a.tools.map(\.count) == [50, 0, 0, 0])
        #expect(a.outcomeMix?.succeeded == 55 && a.outcomeMix?.cancelled == 1 && a.outcomeMix?.failed == 0)
    }

    @Test func missingDurationsAndOtherToolsNeverBecomeInventedSamples() throws {
        let run = UUID(), now = Date(timeIntervalSince1970: 1000)
        let rows = [event(run, now, .success, "unknown", nil), event(run, now, .toolProblem, "search_articles", 18), event(run, now, .failed, "read_article_section", -1), event(run, now, .started, "search_articles", nil), event(UUID(), now, .success, "search_articles", 1), event(run, now, .success, "get_section_references", 4, origin: .localResearch)]
        let a = try #require(MachineRoomAnalytics(projection: projection(run, recent: rows, completed: 3, failed: 2)))
        #expect(a.recentCount == 3 && a.latency.map(\.milliseconds) == [18])
        #expect(a.tools.map(\.count) == [1, 0, 1, 0, 1])
        #expect(a.outcomeMix?.succeeded == 1 && a.outcomeMix?.failed == 2)
    }

    @Test func partialOrInconsistentCountersSuppressOutcomeMix() throws {
        let run = UUID()
        for p in [projection(run, completed: 4, failed: 1, partial: true), projection(run, completed: 1, failed: 2), projection(run, completed: 2, failed: 1, cancelled: 2)] {
            let a = try #require(MachineRoomAnalytics(projection: p))
            #expect(a.isPartial && a.outcomeMix == nil)
        }
        let zero = try #require(MachineRoomAnalytics(projection: projection(run, completed: 0, failed: 0)))
        #expect(zero.outcomeMix?.succeeded == 0 && zero.recentCount == 0 && zero.latency.isEmpty)
    }

    @Test func bucketSelectionIsHalfOpenAndDoesNotCrossRuns() throws {
        let run = UUID(), start = Date(timeIntervalSince1970: 1000)
        let buckets = [RequestBucket(slot: 4, date: start, calls: 2), RequestBucket(slot: 5, date: start.addingTimeInterval(5), calls: 1)]
        let a = try #require(MachineRoomAnalytics(projection: projection(run, buckets: buckets, completed: 3, failed: 0)))
        #expect(a.bucket(containing: start.addingTimeInterval(-0.001)) == nil)
        #expect(a.bucket(containing: start)?.slot == 4)
        #expect(a.bucket(containing: start.addingTimeInterval(4.999))?.slot == 4)
        #expect(a.bucket(containing: start.addingTimeInterval(5))?.slot == 5)
        #expect(a.bucket(containing: start.addingTimeInterval(10)) == nil)
        #expect(a.scope(slot: 3) == nil)
        let s = try #require(a.scope(slot: 4))
        #expect(s.includes(event(run, start, .success, "search_articles", 1)))
        #expect(!s.includes(event(run, s.end, .success, "search_articles", 1)))
        #expect(!s.includes(event(UUID(), start, .success, "search_articles", 1)))
        #expect(!s.includes(event(run, start, .started, "search_articles", nil)))
        #expect(!s.includes(event(run, start, .success, "search_articles", 1, origin: .localResearch)))
    }

    @Test func pauseCannotCrossRunOrLifecycleBoundary() throws {
        let run = UUID(), other = UUID()
        let paused = projection(run, completed: 1, failed: 0)
        let current = projection(run, completed: 4, failed: 0)
        #expect(MachineRoomAnalytics.chartProjection(current: current, paused: paused).metrics?.terminal == 1)
        #expect(MachineRoomAnalytics.chartProjection(current: current, paused: nil).metrics?.terminal == 4)
        let stopped = projection(run, completed: 4, failed: 0, phase: .stopped)
        #expect(MachineRoomAnalytics.chartProjection(current: stopped, paused: paused).metrics?.terminal == 4)
        let restarted = projection(other, completed: 0, failed: 0)
        #expect(MachineRoomAnalytics.chartProjection(current: restarted, paused: paused).runID == other)
        let awaiting = MachineRoomProjection(phase: .running, controllerRunID: other, snapshot: .empty)
        #expect(MachineRoomAnalytics.chartProjection(current: awaiting, paused: paused).metrics == nil)
        #expect(MachineRoomAnalytics(projection: awaiting) == nil)
    }

    private func projection(_ run: UUID, recent: [ActivityEvent] = [], buckets: [RequestBucket] = [], completed: UInt64, failed: UInt64, cancelled: UInt64 = 0, partial: Bool = false, phase: ServerPhase = .running) -> MachineRoomProjection {
        let snapshot = ActivitySnapshot(events: [], recentCalls: recent, buckets: buckets, runID: run, discarded: 0, retainedBytes: 0, active: 0, completed: completed, failed: failed, cancelled: cancelled, medianMilliseconds: nil, durationSampleCount: 0, metricsPartial: partial)
        return MachineRoomProjection(phase: phase, controllerRunID: run, snapshot: snapshot)
    }

    private func event(_ run: UUID, _ date: Date, _ outcome: EventOutcome, _ tool: String, _ ms: Int64?, origin: EventOrigin = .externalMCP) -> ActivityEvent {
        ActivityEvent(id: UUID(), runID: run, date: date, severity: .info, origin: origin, component: "MCP", operation: tool, summary: "Test fixture", correlation: nil, outcome: outcome, durationMilliseconds: ms)
    }
}
