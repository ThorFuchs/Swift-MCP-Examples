// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ExplorerPresentation

/// Native macOS application entry point, window configuration and Settings scene.
@main struct ResearchExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var lifetime = AppLifetime()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup("Research Explorer", id: "explorer") {
            ExplorerRootView(lifetime: lifetime)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .frame(minWidth: 820, minHeight: 620)
                .onAppear { delegate.lifetime = lifetime }
        }
        .defaultSize(width: 1440, height: 900)
        .commands { ExplorerCommands(lifetime: lifetime) }
        Settings { ExplorerSettings() }
    }
}
