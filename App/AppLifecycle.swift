import AppKit
import SwiftUI

@MainActor
final class DamaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let workspace = ReviewWorkspace.shared
        guard workspace.canLeave else {
            workspace.preventLeaving()
            NSApp.activate(ignoringOtherApps: true)
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Preserve SwiftUI's delegate behavior while guarding unsaved or in-flight work.
struct ReviewWindowGuard: NSViewRepresentable {
    let workspace: ReviewWorkspace
    func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }
    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }
    func updateNSView(_ view: WindowAttachmentView, context: Context) {}
    final class WindowAttachmentView: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { attach?(window) }
        }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        let workspace: ReviewWorkspace
        weak var prior: (any NSWindowDelegate)?
        init(workspace: ReviewWorkspace) { self.workspace = workspace }
        @MainActor func attach(to window: NSWindow) {
            guard window.delegate !== self else { return }
            prior = window.delegate
            window.delegate = self
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard workspace.canLeave else { workspace.preventLeaving(); return false }
            return prior?.windowShouldClose?(sender) ?? true
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || prior?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? { prior }
    }
}
