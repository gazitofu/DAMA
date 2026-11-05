import AppKit
import SwiftUI

@MainActor
final class DamaAppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.applySaved()
        statusBar = StatusBarController()
        DockPresence.start()
    }
    /// A Dock click with no visible window (only minimized ones keep the icon) reuses the menu-bar open path.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }
        statusBar?.showWindow()
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let lifecycle = RecordingWorkspace.shared.lifecycle
        if lifecycle.shuttingDown { return .terminateLater }
        if CorrectionWorkspace.shared.busy {
            CorrectionWorkspace.shared.message = "AI 교정 중입니다. 완료를 기다리거나 ‘교정 중단’을 누른 뒤 종료해 주세요."
            return .terminateCancel
        }
        let library = LibraryWorkspace.shared
        if library.notesDirty { library.saveNotes(); library.message = "입력 정보를 저장한 뒤 다시 종료해 주세요."; return .terminateCancel }
        guard library.canLeave else { library.preventLeaving(); return .terminateCancel }
        let workspace = ReviewWorkspace.shared
        guard workspace.canLeave else {
            workspace.preventLeaving()
            NSApp.activate(ignoringOtherApps: true)
            return .terminateCancel
        }
        let capture = RecordingWorkspace.shared.capture
        var saveRecording = false
        if capture.phase.busy || capture.needsFinalization {
            guard capture.phase == .recording || capture.phase == .starting else { return .terminateCancel }
            let alert = NSAlert()
            alert.messageText = "녹음 중입니다."
            alert.informativeText = "녹음을 저장한 뒤 종료할 수 있습니다."
            alert.addButton(withTitle: "계속 녹음")
            alert.addButton(withTitle: "녹음을 저장하고 종료")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            saveRecording = true
        }
        let processing = ProcessingWorkspace.shared
        if saveRecording || processing.localInferenceActive {
            guard lifecycle.beginShutdown() else { return .terminateLater }
            let shouldSave = saveRecording
            Task {
                let saved = await lifecycle.finishShutdown(saveRecording: {
                    if shouldSave { return await capture.stop() }
                    return true
                }, pauseLocalInference: {
                    await processing.pauseAndWait()
                })
                sender.reply(toApplicationShouldTerminate: saved)
            }
            return .terminateLater
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// LSUIElement keeps DAMA a menu-bar agent. While a DAMA window is open or minimized the app joins
/// the Dock and Cmd+Tab; once every such window is closed it returns to the menu bar only.
@MainActor enum DockPresence {
    static func start() {
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification,
                                          NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                                          NSWindow.willCloseNotification]
        for name in names {
            // willClose arrives while the window is still on screen, so re-evaluate on a later main-actor turn.
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in DockPresence.refresh() }
            }
        }
        refresh()
    }
    static func refresh() {
        // Cmd+H orders windows out without closing them; keep the Dock entry so Cmd+Tab can bring them back.
        guard !NSApp.isHidden else { return }
        let policy: NSApplication.ActivationPolicy = NSApp.windows.contains { isUserWindow($0) } ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
    private static func isUserWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.sheetParent == nil
            && (window.isVisible || window.isMiniaturized)
    }
}

struct LibraryWindowGuard: NSViewRepresentable {
    let workspace: LibraryWorkspace
    func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }
    func makeNSView(context: Context) -> ReviewWindowGuard.WindowAttachmentView {
        let view = ReviewWindowGuard.WindowAttachmentView()
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }
    func updateNSView(_ view: ReviewWindowGuard.WindowAttachmentView, context: Context) {}
    final class Coordinator: NSObject, NSWindowDelegate {
        let workspace: LibraryWorkspace
        weak var prior: (any NSWindowDelegate)?
        init(workspace: LibraryWorkspace) { self.workspace = workspace }
        @MainActor func attach(to window: NSWindow) { guard window.delegate !== self else { return }; prior = window.delegate; window.delegate = self }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if workspace.notesDirty { workspace.saveNotes(); workspace.message = "입력 정보를 저장한 뒤 창을 닫아 주세요."; return false }
            guard workspace.canLeave else { workspace.preventLeaving(); return false }
            return prior?.windowShouldClose?(sender) ?? true
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || prior?.responds(to: selector) == true }
        override func forwardingTarget(for selector: Selector!) -> Any? { prior }
    }
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
