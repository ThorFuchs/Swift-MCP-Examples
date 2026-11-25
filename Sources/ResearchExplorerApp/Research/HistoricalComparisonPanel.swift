// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ExplorerDomain
import ExplorerPresentation

/// Compare two independently selected plain-text projections, never an inferred
/// semantic alignment or a diff of the full historical article.
struct HistoricalComparisonPanel: View {
    @Bindable var model: ResearchController
    let preview: HistoricalResearchPreview

    var body: some View {
        ExplorerPanel {
            VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
                Text("Revision comparison").font(ExplorerDesign.Typography.section)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose a section from the selected historical revision. Compare it with your independently selected pinned section; ordinal IDs do not establish correspondence.")
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Revision \(preview.outline.snapshot.revisionID) · \(preview.outline.provenance.title)")
                    .font(ExplorerDesign.Typography.panel)
                Text(preview.outline.provenance.license)
                    .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !HistoricalRevisionLicense.permitsCollection(preview.outline.provenance) {
                    Label("Local reading only until the historical license is verified. Collection/export is disabled for this excerpt.", systemImage: "exclamationmark.shield")
                        .font(ExplorerDesign.Typography.detail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Menu {
                    ForEach(preview.outline.sections, id: \.location.partID) { section in
                        Button(section.heading ?? "Introduction") { model.readHistoricalSection(section.location) }
                    }
                } label: { Label("Choose historical section", systemImage: "list.bullet.indent") }
                .disabled(model.isBusy)
                if let old = preview.passage {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: ExplorerDesign.Space.md) { compared(old) }
                        VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) { compared(old) }
                    }
                } else {
                    Text("Choose a section to read its bounded excerpt.").foregroundStyle(.secondary)
                }
                Button("Read this revision", systemImage: "arrow.right.circle") { model.adoptHistoricalRevision() }
                    .buttonStyle(.glassProminent).disabled(model.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func compared(_ historical: SectionPassage) -> some View {
        if let pinned = model.passage {
            excerpt("Pinned · \(pinned.snapshot.revisionID)", pinned)
        } else {
            Text("Select a section in the pinned reader first.").foregroundStyle(.secondary)
        }
        excerpt("Selected · \(historical.snapshot.revisionID)", historical)
    }

    private func excerpt(_ title: String, _ passage: SectionPassage) -> some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.xs) {
            Text(title).font(ExplorerDesign.Typography.panel)
            Text("Part \(passage.selectedPartID) · \(passage.text.utf8.count) B")
                .font(ExplorerDesign.Typography.detail).foregroundStyle(.secondary)
            Text(passage.textAvailable ? passage.text : "No supplied text")
                .font(ExplorerDesign.Typography.article(size: 15)).textSelection(.enabled)
            if passage.truncated { Text("Excerpt shortened").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
