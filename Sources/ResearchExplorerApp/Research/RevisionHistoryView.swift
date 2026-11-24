// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ExplorerDomain
import ExplorerPresentation

/// A bounded native revision timeline. Opening Wikipedia is explicit and
/// never changes the reader's pinned revision or its collected evidence.
struct RevisionHistoryView: View {
    @Bindable var model: ResearchController
    let outline: Outline

    var body: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
            Text("Revision history")
                .font(ExplorerDesign.Typography.section)
                .accessibilityAddTraits(.isHeader)
            Text("Explore the recent edit history of this article title. Your current revision stays pinned.")
                .font(ExplorerDesign.Typography.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.supportsRevisionHistory {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ExplorerDesign.Space.sm) { controls }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) { controls }
                }
                if model.loadingRevisionHistory {
                    ProgressView("Loading history…").controlSize(.small)
                }
                if let problem = model.revisionHistoryProblem {
                    Label(problem.message, systemImage: "exclamationmark.triangle")
                        .font(ExplorerDesign.Typography.detail)
                    Text(problem.recovery)
                        .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                }
                if let history = model.revisionHistory, history.requestedSnapshot == outline.snapshot {
                    Text("\(history.entries.count) revisions · newest first · Direct REST")
                        .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                    if history.entries.isEmpty {
                        Text("No revisions returned for this segment.").foregroundStyle(.secondary)
                    }
                    ForEach(history.entries) { entry in
                        revisionRow(entry)
                        Divider()
                    }
                    Text("History is title-addressed. An individual historical revision has not been admitted to this reader. Open it explicitly on Wikipedia; no historical text has been downloaded here.")
                        .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("History is currently a Direct-only operation. Switch to Direct and reopen the article to browse it; Via MCP never bypasses its selected route.", systemImage: "info.circle")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var controls: some View {
        Button("Recent revisions", systemImage: "clock.arrow.circlepath") { model.loadRevisionHistory() }
            .buttonStyle(.glass)
            .disabled(model.isBusy)
        if model.revisionHistory?.olderCursor != nil {
            Button("Older revisions", systemImage: "arrow.down") { model.loadRevisionHistory(older: true) }
                .buttonStyle(.glass)
                .disabled(model.isBusy)
        }
    }

    private func revisionRow(_ entry: RevisionHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
            HStack {
                if let date = entry.date {
                    Text(date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .font(ExplorerDesign.Typography.panel)
                }
                Spacer(minLength: 0)
                if entry.revisionID == outline.snapshot.revisionID {
                    ExplorerPill(title: "Pinned", symbol: "pin", tone: .accent)
                }
            }
            Text("Revision \(entry.revisionID)")
                .font(ExplorerDesign.Typography.mono)
                .textSelection(.enabled)
            HStack {
                Text("\(entry.size) B revision size").monospacedDigit()
                if let delta = entry.delta {
                    Text("\(delta > 0 ? "+" : "")\(delta) B change")
                        .monospacedDigit()
                } else {
                    Text("Change unavailable")
                }
            }
            .font(ExplorerDesign.Typography.detail)
            .foregroundStyle(.secondary)
            if entry.minor {
                Label("Marked minor by editor", systemImage: "pencil")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
            }
            if let url = entry.permalink {
                Link("Open revision on Wikipedia", destination: url)
                    .font(ExplorerDesign.Typography.detail)
            }
        }
    }
}
