// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// User-controlled appearance and reader typography preferences.
struct ExplorerSettings: View {
    @AppStorage("readerSize") private var readerSize = ExplorerDesign.Reader.defaultSize
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: ExplorerDesign.Space.md) {
            ExplorerScreenHeading(
                eyebrow: "PERSONALIZE",
                title: "Reading preferences",
                summary: "Make the reader comfortable without changing source identity or network behavior."
            )
            Form {
                Section("Appearance") {
                    Picker("Window appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
                Section("Typography") {
                    Slider(value: $readerSize, in: ExplorerDesign.Reader.minimumSize...ExplorerDesign.Reader.maximumSize, step: 1) {
                        Text("Article text size")
                    }
                    LabeledContent("Preview size", value: "\(Int(readerSize)) pt")
                    Text("The shape of a good question is the beginning of a discovery.")
                        .font(ExplorerDesign.Typography.article(size: readerSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, ExplorerDesign.Space.sm)
                        .textSelection(.enabled)
                }
                Section("Sources & privacy") {
                    LabeledContent("Source", value: "Choose in Server while stopped")
                    Text("Live Wikipedia is an explicit choice. No server or network request starts automatically.")
                        .font(ExplorerDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(ExplorerDesign.Space.lg)
        .frame(width: 500)
    }
}
