// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// System-owned Liquid Glass sidebar and toolbar; content owns no fake glass chrome.
struct ExplorerRootView: View {
    @Bindable var lifetime: AppLifetime

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Workspace?>(
                get: { lifetime.destination },
                set: { if let value = $0 { lifetime.destination = value } }
            )) {
                Section {
                    ForEach(Workspace.allCases) { workspace in
                        Label(workspace.rawValue, systemImage: workspace.symbol)
                            .tag(workspace)
                    }
                } header: {
                    Text("Workspaces")
                        .font(ExplorerDesign.Typography.eyebrow)
                        .tracking(1.1)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Research Explorer")
            .navigationSplitViewColumnWidth(
                min: 200,
                ideal: ExplorerDesign.Layout.sidebarIdealWidth,
                max: 290
            )
            .safeAreaInset(edge: .bottom, alignment: .leading) {
                sidebarStatus
            }
        } detail: {
            Group {
                switch lifetime.destination {
                case .research:
                    if let research = lifetime.research {
                        ResearchView(model: research, focusID: lifetime.searchFocus)
                            .disabled(lifetime.isQuitting || lifetime.termination.unsettled)
                    } else {
                        ContentUnavailableView(
                            lifetime.startupProblem == nil ? "Preparing source" : "Source unavailable",
                            systemImage: lifetime.startupProblem == nil ? "book.closed" : "exclamationmark.triangle",
                            description: Text(lifetime.startupProblem ?? "Preparing the selected bounded provider. No listener or network request is started.")
                        )
                    }
                case .server:
                    ServerView(lifetime: lifetime)
                        .disabled(lifetime.isQuitting || lifetime.termination.unsettled)
                case .activity:
                    ActivityView(lifetime: lifetime, focusID: lifetime.searchFocus)
                }
            }
            .navigationTitle(lifetime.destination.rawValue)
        }
        .tint(ExplorerDesign.Palette.accent)
        .task { lifetime.prepare() }
        .background(WindowReference { lifetime.mainWindow = $0 }.frame(width: 0, height: 0))
    }

    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
            Divider()
            HStack(spacing: ExplorerDesign.Space.xs) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(ExplorerDesign.Palette.accent)
                    .accessibilityHidden(true)
                Text("MCP 2026-07-28")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
            }
            if let server = lifetime.server {
                ExplorerPill(
                    title: "Server " + server.phase.rawValue.lowercased(),
                    symbol: server.phase == .running ? "checkmark.circle.fill" : "circle",
                    tone: server.phase == .running ? .accent : .neutral
                )
            } else {
                ExplorerPill(title: "Server unavailable", symbol: "circle")
            }
        }
        .padding(.horizontal, ExplorerDesign.Space.md)
        .padding(.bottom, ExplorerDesign.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
