// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ExplorerPresentation

/// A small local research dossier, not a new workspace or persistent notebook.
struct EvidenceCollectionView: View {
    @Bindable var lifetime: AppLifetime
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?

    private var selected: ResearchEvidence? {
        lifetime.collection.entries.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
            ExplorerScreenHeading(eyebrow: "EVIDENCE COLLECTION", title: "Your research dossier",
                summary: "Collected sections stay in memory until you quit. Export explicitly to keep them; source excerpts, reference metadata and personal notes stay separate.")
            HStack(alignment: .top, spacing: ExplorerDesign.Space.md) {
                List(selection: $selectedID) {
                    ForEach(lifetime.collection.entries) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.passage.provenance.title).font(.headline)
                            Text(item.heading).foregroundStyle(.secondary)
                            Text(item.passage.provenance.synthetic ? "Fictional · Offline" : "Wikipedia · \(item.passage.snapshot.revisionID)")
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(item.id)
                    }
                }
                .frame(width: 230)
                .accessibilityLabel("Collected sections")
                if let selected {
                    detail(selected)
                } else {
                    ContentUnavailableView("Collect a section", systemImage: "bookmark",
                        description: Text("Choose a settled article section in Research, then Collect section."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let message = lifetime.collectionMessage {
                Text(message).font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(lifetime.collection.entries.count) / \(ResearchCollection.maximumEntries) sections")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(ResearchCollection.Format.allCases, id: \.self) { format in
                        Button(format.rawValue) { lifetime.exportCollection(format) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(lifetime.collection.entries.isEmpty || lifetime.exporting || lifetime.isQuitting)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExplorerDesign.Space.lg)
        .frame(minWidth: 680, idealWidth: 840, minHeight: 520, idealHeight: 680)
        .onAppear { selectedID = lifetime.collection.entries.first?.id }
        .onChange(of: lifetime.collection.entries.map(\.id)) {
            if selected == nil { selectedID = lifetime.collection.entries.first?.id }
        }
    }

    private func detail(_ item: ResearchEvidence) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
                Text(item.passage.provenance.title).font(ExplorerDesign.Typography.section)
                Text(item.heading).font(.headline)
                Text("Revision \(item.passage.snapshot.revisionID) · \(item.route.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(item.passage.provenance.license)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text(item.passage.provenance.sourceURL)
                    .font(.caption).textSelection(.enabled)
                if item.passage.truncated { Label("Captured source text was truncated.", systemImage: "text.badge.minus") }
                Text(item.passage.text)
                    .font(ExplorerDesign.Typography.article(size: 15))
                    .textSelection(.enabled)
                Divider()
                Text("References · unverified metadata").font(.headline)
                if let refs = item.references {
                    if refs.references.isEmpty && refs.unresolvedIDs.isEmpty {
                        Text("No cited references in this projection.").foregroundStyle(.secondary)
                    }
                    ForEach(refs.references, id: \.id) { ref in
                        Text(ref.title).font(.callout).textSelection(.enabled)
                    }
                    if !refs.unresolvedIDs.isEmpty { Text("Unresolved: \(refs.unresolvedIDs.joined(separator: ", "))").font(.caption) }
                    if refs.truncated { Text("Reference projection truncated.").font(.caption) }
                } else {
                    Text("Reference metadata unavailable: \(item.referenceProblem?.rawValue ?? "unknown").").foregroundStyle(.secondary)
                }
                Divider()
                Text("Personal note").font(.headline)
                TextEditor(text: Binding(
                    get: { lifetime.collection.entries.first { $0.id == item.id }?.note ?? "" },
                    set: { lifetime.updateEvidenceNote($0, id: item.id) }
                ))
                .font(.body)
                .frame(height: 110)
                .accessibilityLabel("Personal note for selected evidence")
                Text("Maximum 4 KiB UTF-8. Notes are not attributed to Wikipedia.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    lifetime.removeEvidence(item.id)
                } label: { Label("Remove from collection", systemImage: "trash") }
                .disabled(lifetime.isQuitting)
            }
            .padding(ExplorerDesign.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
