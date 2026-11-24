// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import AppKit
import SwiftUI
import QuartzCore
import ExplorerDomain
import WikimediaAccess
import ExplorerPresentation
@testable import ResearchExplorerApp

/// Opt-in native review captures. The actual viewport is rendered, not its
/// enclosing window-frame view. No image is rescaled to hide layout defects.
/// Window-server materials are not captured by CALayer; review the real
/// window separately for Liquid Glass, vibrancy and accessibility.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RE_SNAPSHOT_DIR"] != nil, "Set RE_SNAPSHOT_DIR to render review screenshots"))
@MainActor struct ReaderSnapshotTests {
    private enum Content {
        case app(tour: Bool, query: String?)
        case workspace(Workspace)
        case evidence(query: String, section: Int)
        case machineRoom(RoomCapture)
    }
    private enum RoomCapture { case dashboard, analytics, exchanges, activity }
    private enum CaptureFailure: Error { case hostNotReady, missingObservation }
    private struct Shot { let name: String; let size: CGSize; let dark: Bool; let readerSize: Double; let content: Content }

    private func render(_ shot: Shot, into directory: URL) async throws {
        UserDefaults.standard.set(shot.readerSize, forKey: "readerSize")
        let provider = try FixtureProvider.load()
        let service = ExplorerService(provider: provider, limits: try ExplorerLimits())
        let app = AppLifetime(profile: .offlineDemo, loadSource: { _ in
            PreparedSource(service: service, offlineEdit: .prepared(provider))
        }, makeHost: { service, activity, id in
            SDKHTTPHost(service: service, activity: activity, runID: id, configuration: try LocalEndpoint(port: 0))
        })
        app.prepare(); await app.waitUntilPrepared()
        do {
            let research = try #require(app.research)
            let root: AnyView
            switch shot.content {
            case .app(let tour, let query):
                if tour { research.exploreOfflineCollection(); await research.waitUntilIdle() }
                if let query { research.query = query; research.search(); await research.waitUntilIdle() }
                root = AnyView(ExplorerRootView(lifetime: app))
            case .workspace(let destination):
                app.destination = destination
                root = AnyView(ExplorerRootView(lifetime: app))
            case .evidence(let query, let section):
                research.query = query; research.search(); await research.waitUntilIdle()
                research.open(try #require(research.page?.candidates.first)); await research.waitUntilIdle()
                for _ in 0...section { research.readAdjacent(1); await research.waitUntilIdle() }
                root = AnyView(EvidencePane(model: research, presentation: research.presentation))
            case .machineRoom(let capture):
                root = try await machineRoom(capture, app: app)
            }
            try await capture(root, shot: shot, into: directory)
        } catch {
            #expect(await app.quit(waitMilliseconds: 5000))
            throw error
        }
        #expect(await app.quit(waitMilliseconds: 5000))
    }

    /// Review-only explicit server start. Every data point is emitted by the
    /// real SDK and original offline fixture, never a fabricated snapshot.
    private func machineRoom(_ capture: RoomCapture, app: AppLifetime) async throws -> AnyView {
        app.destination = .server
        app.startServer()
        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while app.server?.phase != .running {
            guard ContinuousClock.now < deadline, app.server?.phase != .failed else {
                throw CaptureFailure.hostNotReady
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        app.journey.setInspectExchanges(true)
        app.exploreMCP()
        await app.journey.waitUntilFinished()
        try #require(app.journey.phase == .completed)
        try #require(app.journey.exchanges.count == 6)
        let snapshot = await app.activity.snapshot()
        app.activitySnapshot = snapshot
        let projection = MachineRoomProjection(phase: app.server?.phase, controllerRunID: app.server?.runID, snapshot: snapshot)
        guard let metrics = projection.metrics, metrics.terminal == 4,
              let analytics = MachineRoomAnalytics(projection: projection) else {
            throw CaptureFailure.missingObservation
        }
        let journey = MachineRoomJourneyProjection(currentRunID: app.server?.runID,
            journeyRunID: app.journeyOwnerRunID, phase: app.journey.phase,
            steps: app.journey.steps, inspectionEnabled: app.journey.inspectExchanges,
            records: app.journey.exchanges, dropped: app.journey.droppedExchanges)
        try #require(journey.isCurrent && journey.inspectionEnabled && journey.exchanges.count == 6)
        switch capture {
        case .dashboard:
            return AnyView(ExplorerRootView(lifetime: app))
        case .analytics:
            return AnyView(ScrollView {
                MachineRoomAnalyticsGrid(analytics: analytics)
                    .padding(ExplorerDesign.Space.xl)
            }.background(ExplorerDesign.Palette.canvas))
        case .exchanges:
            return AnyView(ScrollView {
                JourneyExchangeCharts(projection: journey)
                    .padding(ExplorerDesign.Space.xl)
            }.background(ExplorerDesign.Palette.canvas))
        case .activity:
            app.destination = .activity
            return AnyView(ExplorerRootView(lifetime: app))
        }
    }

    private func capture(_ root: AnyView, shot: Shot, into directory: URL) async throws {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: root
            .frame(width: shot.size.width, height: shot.size.height)
            .clipped()
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            })
        // Do not let a large ideal content height grow the test window.
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: shot.size), styleMask: [.titled, .resizable, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: shot.dark ? .darkAqua : .aqua)
        window.title = "Research Explorer"
        window.contentView = hosting
        window.setContentSize(shot.size)
        hosting.wantsLayer = true
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded(); window.displayIfNeeded(); CATransaction.flush()
            try await Task.sleep(for: .milliseconds(100))
        }
        let view = try #require(window.contentView)
        let scale = window.backingScaleFactor, bounds = view.bounds
        try #require(abs(bounds.width - shot.size.width) <= 1)
        try #require(abs(bounds.height - shot.size.height) <= 1)
        print("RE_CAPTURE \(shot.name) points=\(bounds.width)x\(bounds.height) scale=\(scale)")
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        context.cgContext.setFillColor((shot.dark ? NSColor.black : NSColor.white).cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
        context.cgContext.scaleBy(x: scale, y: scale)
        try #require(view.layer).render(in: context.cgContext)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appending(path: "\(shot.name).png"))
    }

    @Test func renderReviewScreenshots() async throws {
        let directory = URL(filePath: try #require(ProcessInfo.processInfo.environment["RE_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let priorReaderSize = UserDefaults.standard.object(forKey: "readerSize")
        defer {
            if let priorReaderSize { UserDefaults.standard.set(priorReaderSize, forKey: "readerSize") }
            else { UserDefaults.standard.removeObject(forKey: "readerSize") }
        }
        let shots = [
            Shot(name: "01-first-run-light", size: .init(width: 1280, height: 800), dark: false, readerSize: 17, content: .app(tour: false, query: nil)),
            Shot(name: "02-reader-wide-light", size: .init(width: 1440, height: 900), dark: false, readerSize: 17, content: .app(tour: true, query: nil)),
            Shot(name: "03-reader-wide-dark", size: .init(width: 1440, height: 900), dark: true, readerSize: 17, content: .app(tour: true, query: nil)),
            Shot(name: "04-reader-compact-light", size: .init(width: 900, height: 640), dark: false, readerSize: 17, content: .app(tour: true, query: nil)),
            Shot(name: "05-reader-large-article-text-dark", size: .init(width: 1440, height: 900), dark: true, readerSize: 24, content: .app(tour: true, query: nil)),
            Shot(name: "06-search-results-light", size: .init(width: 1280, height: 800), dark: false, readerSize: 17, content: .app(tour: false, query: "Riverglass")),
            Shot(name: "07-evidence-cited-light", size: .init(width: 340, height: 760), dark: false, readerSize: 17, content: .evidence(query: "Riverglass Observatory", section: 1)),
            Shot(name: "08-evidence-metadata-missing-dark", size: .init(width: 340, height: 640), dark: true, readerSize: 17, content: .evidence(query: "lantern", section: 0)),
            Shot(name: "09-server-idle-light", size: .init(width: 1440, height: 900), dark: false, readerSize: 17, content: .workspace(.server)),
            Shot(name: "10-activity-empty-dark", size: .init(width: 1440, height: 900), dark: true, readerSize: 17, content: .workspace(.activity)),
            Shot(name: "11-machine-room-live-light", size: .init(width: 1440, height: 900), dark: false, readerSize: 17, content: .machineRoom(.dashboard)),
            Shot(name: "12-machine-room-analytics-dark", size: .init(width: 1440, height: 900), dark: true, readerSize: 17, content: .machineRoom(.analytics)),
            Shot(name: "13-machine-room-exchanges-light", size: .init(width: 1440, height: 900), dark: false, readerSize: 17, content: .machineRoom(.exchanges)),
            Shot(name: "14-activity-observed-dark", size: .init(width: 1440, height: 900), dark: true, readerSize: 17, content: .machineRoom(.activity)),
            Shot(name: "15-machine-room-compact-dark", size: .init(width: 900, height: 640), dark: true, readerSize: 17, content: .machineRoom(.dashboard)),
        ]
        for shot in shots { try await render(shot, into: directory) }
    }
}
