// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ExplorerDomain
import ExplorerPresentation

/// Earlier revision metadata, not a replacement for the current article.
struct RevisionHistoryPanel: View {
    @Bindable var model: ResearchController

    var body: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
            Label("Wikipedia Time Machine", systemImage: "clock.arrow.circlepath")
                .font(ExplorerDesign.Typography.panel)
                .accessibilityAddTraits(.isHeader)
            if !model.supportsRevisionHistory {
                Text("History browsing is available in Direct mode. This MCP reader does not bypass its selected route.")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
            } else {
                Text("Explore earlier revisions without changing the pinned article. Each request returns up to 20 history entries.")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                Button(model.revisionHistory == nil ? "Load earlier revisions" : "Return to pinned revision history",
                       systemImage: "clock") { model.loadRevisionHistory() }
                    .buttonStyle(.glass)
                    .disabled(model.isBusy)
                if model.phase == .history {
                    ProgressView("Loading history…").controlSize(.small)
                }
                if let problem = model.historyProblem {
                    Label(problem.message, systemImage: "exclamationmark.triangle")
                        .font(ExplorerDesign.Typography.detail)
                    Text(problem.recovery).font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                }
                if let history = model.revisionHistory {
                    Text("Earlier than revision \(history.anchor) · \(history.entries.count) returned")
                        .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                        .monospacedDigit()
                    if history.entries.isEmpty {
                        Text("No earlier revisions returned.").foregroundStyle(.secondary)
                    }
                    ForEach(history.entries) { entry in
                        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(ExplorerDesign.Typography.panel)
                            Text("Revision \(entry.id) · \(entry.size) bytes\(entry.minor ? " · Minor" : "")")
                                .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                                .monospacedDigit().textSelection(.enabled)
                            if let delta = entry.delta {
                                Label("\(delta > 0 ? "+" : "")\(delta) bytes vs preceding edit",
                                      systemImage: delta > 0 ? "plus.circle" : delta < 0 ? "minus.circle" : "equal.circle")
                                    .font(ExplorerDesign.Typography.detail).monospacedDigit()
                            } else {
                                Text("Change size unavailable").font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack { revisionLinks(entry, history: history) }.fixedSize(horizontal: true, vertical: false)
                                VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) { revisionLinks(entry, history: history) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ExplorerDesign.Space.sm)
                        .background(ExplorerDesign.Palette.control, in: RoundedRectangle(cornerRadius: ExplorerDesign.Radius.small))
                    }
                    if history.nextAnchor != nil {
                        Button("Load next older page", systemImage: "chevron.down") {
                            model.loadRevisionHistory(older: true)
                        }
                        .buttonStyle(.glass).disabled(model.isBusy)
                    }
                    Text("Title-scoped MediaWiki history. Revision and comparison links open Wikipedia in your browser; the native reader remains pinned. Page identity and historical content are not independently admitted by this history view.")
                        .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func revisionLinks(_ entry: RevisionHistoryEntry, history: RevisionHistory) -> some View {
        if let link = entry.permalink { Link("Open revision", destination: link) }
        if let link = entry.comparisonURL(to: history.pinned.revisionID) { Link("Compare with pin", destination: link) }
    }
}
