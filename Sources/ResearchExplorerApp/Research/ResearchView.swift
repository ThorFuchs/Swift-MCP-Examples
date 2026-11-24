// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ExplorerDomain
import ExplorerPresentation

struct ResearchView: View {
    @Bindable var model: ResearchController
    let focusID: UUID
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let problem = model.problem {
                ExplorerPanel {
                    VStack(alignment: .leading, spacing: ExplorerDesign.Space.sm) {
                        Label(problem.message, systemImage: "exclamationmark.triangle")
                            .font(ExplorerDesign.Typography.panel)
                        Text(problem.recovery)
                            .foregroundStyle(.secondary)
                        if model.outline != nil {
                            Button("Obtain a new outline") { model.refreshOutline() }
                        } else if !model.query.isEmpty {
                            Button("Try again") { model.search() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(ExplorerDesign.Space.md)
            }
            if let outline = model.outline {
                ArticleReaderView(model: model, outline: outline)
            } else if model.candidate != nil && model.isBusy {
                ProgressView("Opening exact revision…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let page = model.page, model.phase != .empty {
                results(page)
            } else if model.phase == .empty || model.phase == .cancelled {
                ContentUnavailableView {
                    Label(model.phase == .empty ? "No matching articles" : "Search cancelled", systemImage: "book.closed")
                } description: {
                    Text(model.phase == .empty
                        ? "Nothing in this source matched. No other source was searched instead."
                        : "The search was stopped. No partial result is shown.")
                } actions: {
                    if model.source == .offlineDemo {
                        Button("Show all Riverglass articles") {
                            model.query = OfflineTour.query
                            model.search()
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            } else if model.source == .offlineDemo {
                welcome
            } else {
                ContentUnavailableView(
                    "A place to follow your curiosity",
                    systemImage: "book.closed",
                    description: Text("Search English Wikipedia explicitly. Opening an article selects one fetched revision; sections and references use that snapshot. For a no-network tour, choose Offline demo in Server.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.back()
                } label: {
                    Label("Back to results", systemImage: "chevron.left")
                }
                .disabled(model.candidate == nil)
                .keyboardShortcut("[", modifiers: .command)
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: ExplorerDesign.Space.xs) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(
                        model.source == .offlineDemo ? "Search offline articles" : "Search English Wikipedia",
                        text: $model.query
                    )
                    .textFieldStyle(.plain)
                    .frame(minWidth: 200, idealWidth: 330)
                    .focused($searchFocused)
                    .onSubmit { model.search() }
                    .accessibilityLabel("Search articles")
                    if model.isBusy { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, ExplorerDesign.Space.xs)
            }
            ToolbarItem {
                if model.isBusy {
                    Button("Cancel", systemImage: "xmark") { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Search", systemImage: "arrow.right") { model.search() }
                        .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onChange(of: focusID) { searchFocused = true }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.lg) {
                Spacer(minLength: ExplorerDesign.Space.xl)
                ExplorerPill(title: "Fictional · Offline demo", symbol: "externaldrive", tone: .accent)
                Text("A place to follow\nyour curiosity.")
                    .font(ExplorerDesign.Typography.display)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Explore five fictional articles about an observatory that never existed. Read the story, follow its references, and see exactly which revision each passage came from.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 660, alignment: .leading)
                Button("Explore the offline collection", systemImage: "sparkle.magnifyingglass") {
                    model.exploreOfflineCollection()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                ExplorerPanel {
                    HStack(alignment: .top, spacing: ExplorerDesign.Space.lg) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(ExplorerDesign.Palette.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
                            Text("Read first. Inspect when curious.")
                                .font(ExplorerDesign.Typography.section)
                            Text("The collection works entirely on this Mac. Starting the app makes no network request and opens no server. If you want to inspect real MCP traffic, start the local host explicitly in Server.")
                                .font(ExplorerDesign.Typography.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: ExplorerDesign.Space.lg)
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(ExplorerDesign.Space.xl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(ExplorerDesign.Palette.canvas)
    }

    private func results(_ page: SearchPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: ExplorerDesign.Space.md) {
                Text(model.source == .offlineDemo ? "Explore the collection" : "Wikipedia results")
                    .font(ExplorerDesign.Typography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: ExplorerDesign.Space.sm)
                SourceBadge(source: model.source)
            }
            .padding(.horizontal, ExplorerDesign.Space.xl)
            .padding(.top, ExplorerDesign.Space.lg)
            .padding(.bottom, ExplorerDesign.Space.md)
            List(page.candidates, id: \.id) { candidate in
                Button { model.open(candidate) } label: {
                    HStack(alignment: .center, spacing: ExplorerDesign.Space.md) {
                        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
                            Text(candidate.title)
                                .font(ExplorerDesign.Typography.section)
                            if let description = candidate.description {
                                Text(description)
                                    .font(ExplorerDesign.Typography.body)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, ExplorerDesign.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(candidate.title)")
            }
            .listStyle(.inset)
            if page.truncated {
                Text(model.source == .offlineDemo
                     ? "More candidates exist. Refine the query."
                     : "Showing up to 10 results. Refine your query; total matches are unknown.")
                    .font(ExplorerDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .padding(ExplorerDesign.Space.md)
            }
        }
    }
}

/// Source status is always visible so fictional material cannot masquerade as Wikipedia.
struct SourceBadge: View {
    let source: ResearchSource
    var body: some View {
        ExplorerPill(
            title: source == .offlineDemo ? "Fictional · Offline demo" : "Wikipedia English",
            symbol: source == .offlineDemo ? "externaldrive" : "globe",
            tone: .neutral
        )
        .accessibilityLabel(source == .offlineDemo
                            ? "Source: fictional offline demo"
                            : "Source: Wikipedia English")
    }
}
