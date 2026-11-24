// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import Synchronization
@testable import ExplorerPresentation

struct MachineRoomProjectionTests {
    @Test func idleDoesNotDisplayUnobservedZerosOrPreviousSource() async throws {
        let store = ActivityStore()
        let empty = await store.snapshot()
        let absent = MachineRoomProjection(phase: nil, controllerRunID: nil, snapshot: empty)
        #expect(absent.scope == .unavailable && absent.metrics == nil)
        let idle = MachineRoomProjection(phase: .stopped, controllerRunID: nil, snapshot: empty)
        #expect(idle.scope == .idle && idle.metrics == nil)

        let oldRun = UUID()
        try await store.beginRun(oldRun)
        let token = await store.startCall(run: oldRun, operation: "search_articles")
        await store.finishCall(token, outcome: .success)
        let old = await store.snapshot()
        // A new controller created by source switching has no run ID, even
        // though the shared ActivityStore still has the previous run.
        let switched = MachineRoomProjection(phase: .stopped, controllerRunID: nil, snapshot: old)
        #expect(switched.scope == .idle && switched.metrics == nil)
    }

    @Test func matchingSnapshotHasDistinctLifecycleScopes() async throws {
        let store = ActivityStore()
        let run = UUID()
        try await store.beginRun(run)
        let snapshot = await store.snapshot()
        let pairs: [(ServerPhase, MachineRoomProjection.Scope)] = [
            (.starting, .starting), (.running, .live), (.stopping, .stopping),
            (.stopped, .lastRun), (.failed, .failedRun)
        ]
        for (phase, expected) in pairs {
            let p = MachineRoomProjection(phase: phase, controllerRunID: run, snapshot: snapshot)
            #expect(p.scope == expected && p.runID == run)
            #expect(p.metrics != nil)
        }
        let m = try #require(MachineRoomProjection(phase: .running, controllerRunID: run, snapshot: snapshot).metrics)
        #expect(m.active == 0 && m.terminal == 0 && m.failed == 0 && m.cancelled == 0)
        #expect(m.medianMilliseconds == nil && m.durationSampleCount == 0)
        #expect(m.buckets.count == 60 && m.windowTerminalCount == 0 && !m.isPartial)
    }

    @Test func staleSnapshotNeverAppearsAsNewRunDuringRestart() async throws {
        let store = ActivityStore()
        let oldRun = UUID(), newRun = UUID()
        try await store.beginRun(oldRun)
        let token = await store.startCall(run: oldRun, operation: "search_articles")
        await store.finishCall(token, outcome: .success)
        let stale = await store.snapshot()
        for phase in [ServerPhase.starting, .running, .stopping] {
            let p = MachineRoomProjection(phase: phase, controllerRunID: newRun, snapshot: stale)
            #expect(p.scope == .awaitingSnapshot && p.metrics == nil)
        }
        let failed = MachineRoomProjection(phase: .failed, controllerRunID: newRun, snapshot: stale)
        #expect(failed.scope == .unobservedRun && failed.metrics == nil)
        try await store.beginRun(newRun)
        let next = await store.snapshot()
        let p = MachineRoomProjection(phase: .running, controllerRunID: newRun, snapshot: next)
        #expect(p.scope == .live)
        let metrics = try #require(p.metrics)
        #expect(metrics.terminal == 0 && metrics.recentCalls.isEmpty)
        #expect(next.events.contains { $0.runID == oldRun })
    }

    @Test func terminalCountsUseRealStoreSemanticsAndExcludeDirectResearch() async throws {
        let ticks = Mutex<Int64>(0)
        let store = ActivityStore(clock: .init(milliseconds: { ticks.withLock { $0 } }, wall: { Date(timeIntervalSince1970: 1000) }))
        let run = UUID()
        try await store.beginRun(run)
        for outcome in [EventOutcome.success, .toolProblem, .failed, .cancelled] {
            let token = await store.startCall(run: run, operation: "read_article_section")
            ticks.withLock { $0 += 125 }
            await store.finishCall(token, outcome: outcome)
        }
        await store.localResearch("search_articles", success: true)
        let active = await store.startCall(run: run, operation: "get_article_outline")
        let p = MachineRoomProjection(phase: .running, controllerRunID: run, snapshot: await store.snapshot())
        let m = try #require(p.metrics)
        #expect(m.active == 1 && m.terminal == 4 && m.failed == 2 && m.cancelled == 1)
        #expect(m.windowTerminalCount == 4 && m.medianMilliseconds == 125 && m.durationSampleCount == 4)
        #expect(m.recentCalls.count == 4 && m.recentCalls.allSatisfy { $0.runID == run && $0.origin == .externalMCP })
        #expect(!m.isPartial)
        await store.finishCall(active, outcome: .cancelled)
        await store.markPartial()
        let partial = try #require(MachineRoomProjection(phase: .stopping, controllerRunID: run, snapshot: await store.snapshot()).metrics)
        #expect(partial.isPartial && partial.terminal == 5 && partial.cancelled == 2)
    }

    @Test func lastRunTotalsRemainButRollingWindowAges() async throws {
        let ticks = Mutex<Int64>(0)
        let store = ActivityStore(clock: .init(milliseconds: { ticks.withLock { $0 } }, wall: { Date(timeIntervalSince1970: 1000) }))
        let run = UUID()
        try await store.beginRun(run)
        let token = await store.startCall(run: run, operation: "search_articles")
        ticks.withLock { $0 = 100 }
        await store.finishCall(token, outcome: .success)
        ticks.withLock { $0 = 310_000 }
        let p = MachineRoomProjection(phase: .stopped, controllerRunID: run, snapshot: await store.snapshot())
        let m = try #require(p.metrics)
        #expect(p.scope == .lastRun && m.terminal == 1 && m.windowTerminalCount == 0)
        #expect(m.medianMilliseconds == nil && m.durationSampleCount == 0)
    }

    @Test func boundedProjectionRejectsOverflowWithoutInventingZero() throws {
        let run = UUID()
        let snapshot = ActivitySnapshot(
            events: [], recentCalls: [], buckets: (0..<61).map { index in
                RequestBucket(slot: Int64(index), date: Date(timeIntervalSince1970: Double(index * 5)), calls: index == 59 ? UInt64.max : 1)
            }, runID: run, discarded: 0, retainedBytes: 0, active: 0,
            completed: UInt64.max, failed: 0, cancelled: 0,
            medianMilliseconds: nil, durationSampleCount: 0, metricsPartial: false
        )
        let m = try #require(MachineRoomProjection(phase: .running, controllerRunID: run, snapshot: snapshot).metrics)
        #expect(m.buckets.count == 60 && m.buckets.first?.slot == 1)
        #expect(m.windowTerminalCount == nil && m.isPartial)
    }
}
