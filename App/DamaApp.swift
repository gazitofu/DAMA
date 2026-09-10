import SwiftUI

@main struct DamaApp: App {
    @NSApplicationDelegateAdaptor(DamaAppDelegate.self) private var delegate
    @StateObject private var workspace = LibraryWorkspace.shared
    var body: some Scene {
        Window("DAMA", id: "review") {
            LibraryShell(workspace: workspace)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .importExport) {
                Button("Markdown 내보내기", action: workspace.exportMarkdown)
                    .disabled(!workspace.canLeave || workspace.scriptFile == nil || workspace.folder != .scripts)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        Settings { LibrarySettings(workspace: workspace) }
    }
}
