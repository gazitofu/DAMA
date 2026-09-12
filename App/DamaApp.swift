import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    static let preferenceKey = "appearance.mode"
    var title: String {
        switch self {
        case .system: "시스템 설정"
        case .light: "라이트"
        case .dark: "다크"
        }
    }
    @MainActor static func applySaved() {
        let mode = Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

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
