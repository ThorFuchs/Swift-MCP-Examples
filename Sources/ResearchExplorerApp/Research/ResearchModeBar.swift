// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ExplorerPresentation

/// Source and execution route are independent choices. This control never
/// starts a listener or automatically changes the selected source.
struct ResearchModeBar: View {
    @Bindable var lifetime: AppLifetime

    var body: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
            HStack {
                SourceBadge(source: lifetime.profile)
                Spacer(minLength: 4)
                Menu {
                    Button("Direct", systemImage: "arrow.right") { lifetime.selectResearchMode(.direct) }
                        .disabled(lifetime.researchMode == .direct)
                    Button(lifetime.researchMode == .mcp && !lifetime.researchRouteReady ? "Reconnect MCP" : "Via MCP", systemImage: "arrow.left.arrow.right") {
                        lifetime.selectResearchMode(.mcp)
                    }
                    .disabled(!lifetime.canUseMCPResearch || (lifetime.researchMode == .mcp && lifetime.researchRouteReady))
                } label: {
                    Label(lifetime.researchMode.rawValue, systemImage: lifetime.researchMode == .mcp ? "arrow.left.arrow.right" : "arrow.right")
                }
                .disabled(!lifetime.canChangeResearchMode)
                .help("Changing routes clears the open article and retains the query. Search explicitly afterwards.")
            }
            if !lifetime.researchRouteReady {
                Label("MCP route unavailable. Start the local server and reconnect explicitly, or choose Direct.", systemImage: "exclamationmark.triangle")
                    .font(ExplorerDesign.Typography.detail)
                    .fixedSize(horizontal: false, vertical: true)
            } else if lifetime.researchMode == .mcp {
                Text("Research requests use the real local MCP client and appear in Server metrics.")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
            }
            if let problem = lifetime.researchModeProblem {
                Text(problem).font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, ExplorerDesign.Space.md)
        .padding(.vertical, ExplorerDesign.Space.xs)
    }
}
