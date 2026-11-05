import AppKit
import DamaAudio
import SwiftUI

@MainActor
final class DamaAppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.applySaved()
        statusBar = StatusBarController()
        DockPresence.start()
        TitlePromptPanelController.shared.start()
        QASnapshot.start()
    }
    func applicationWillTerminate(_ notification: Notification) {
        // usage-bundle1: 열린 녹음 제목 입력창과 줄 선 입력창은 저장 없이 버린다.
        TitlePromptPanelController.shared.discardAll()
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

/// 합성 QA 앱(Debug · `com.gazitofu.Dama.ReadingQA` · `--reading-fixture-root`)만 자기 창을 PNG로 남긴다.
/// 화면 기록 권한 없이 앱 자신의 뷰를 그린다. 운영 Bundle·Release에서는 켜지지 않는다 (usage-bundle1 게이트 ② 화면 검증).
/// 요청: 분산 알림 `com.gazitofu.Dama.ReadingQA.snapshot`, object = 파일 이름(영숫자·`-`·`_` 64자 이하).
/// 결과: `<fixture>/qa-snapshots/<이름>-<창 번호>.png`. 모달 경고창은 기본 런루프가 멈춰 담기지 않는다.
@MainActor enum QASnapshot {
    static func start() {
        #if DEBUG
        guard let fixture = AudioFiles.uiFixtureFolder else { return }
        let folder = fixture.appendingPathComponent("qa-snapshots", isDirectory: true)
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.gazitofu.Dama.ReadingQA.snapshot"),
                                                            object: nil, queue: .main) { note in
            let requested = note.object as? String ?? ""
            let name = requested.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil ? requested : "snapshot"
            MainActor.assumeIsolated { capture(name: name, folder: folder) }
        }
        #endif
    }
    #if DEBUG
    private static func capture(name: String, folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
                  let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                      bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            // 뷰만 그리면 창 배경이 빠져 투명해지고 글자 혼합이 사라진다. 창의 외관으로 배경색을 먼저 칠한 비트맵에 뷰를 직접 그린다.
            out.size = rep.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                window.backgroundColor.setFill(); NSRect(origin: .zero, size: rep.size).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            view.cacheDisplay(in: view.bounds, to: out)
            try? out.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name)-\(index).png"))
        }
    }
    #endif
}
