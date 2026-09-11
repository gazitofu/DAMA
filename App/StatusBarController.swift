import AppKit
import Combine
import DamaAudio
import SwiftUI

@MainActor final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let toggle = NSSwitch()
    private let label = NSTextField(labelWithString: "녹음 시작")
    private let workspace = RecordingWorkspace.shared
    private var subscriptions = Set<AnyCancellable>()
    private var mainWindow: NSWindow?
    private let idleImage = StatusBarController.icon(named: "DamaMenuIdle", template: true)
    private let recordingImage = StatusBarController.icon(named: "DamaMenuRecording", template: false)
    private static func icon(named name: String, template: Bool) -> NSImage? {
        guard let image = NSImage(named: name)?.copy() as? NSImage else { return nil }
        // Display both states at 90% of the original 22pt canvas.
        image.size = NSSize(width: 19.8, height: 19.8)
        image.isTemplate = template
        image.accessibilityDescription = template ? "DAMA, 녹음 대기" : "DAMA, 녹음 중"
        return image
    }
    private static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "미확인"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "미확인"
        return "DAMA \(version) · 빌드 \(build)"
    }

    override init() {
        super.init()
        LibraryWorkspace.shared.start()
        workspace.start()
        ProcessingWorkspace.shared.start()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 42))
        label.frame = NSRect(x: 14, y: 12, width: 175, height: 18)
        toggle.frame = NSRect(x: 199, y: 9, width: 38, height: 24)
        toggle.target = self; toggle.action = #selector(toggleRecording)
        toggle.setAccessibilityLabel("녹음 시작 또는 종료")
        row.addSubview(label); row.addSubview(toggle)
        let recordingItem = NSMenuItem(); recordingItem.view = row
        menu.addItem(recordingItem); menu.addItem(.separator())
        for (title, action) in [("Open DAMA", #selector(showWindow)), (Self.versionLabel, #selector(showVersion)), ("Quit DAMA", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        menu.delegate = self; item.menu = menu
        workspace.capture.$phase.sink { [weak self] phase in self?.update(phase: phase) }.store(in: &subscriptions)
        workspace.$ready.sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        update()
    }
    func menuWillOpen(_ menu: NSMenu) { update() }
    private func update(phase suppliedPhase: CapturePhase? = nil) {
        let phase = suppliedPhase ?? workspace.capture.phase, recording = phase == .recording
        item.button?.image = recording ? recordingImage : idleImage
        item.button?.contentTintColor = nil
        item.button?.setAccessibilityLabel(recording ? "DAMA, 녹음 중" : "DAMA, 녹음 대기")
        item.button?.toolTip = Self.versionLabel + (recording ? " · 녹음 중" : "")
        toggle.state = recording ? .on : .off
        toggle.isEnabled = workspace.ready && (recording || !phase.busy) && !workspace.capture.needsFinalization
        switch phase {
        case .authorizing, .starting: label.stringValue = "녹음 시작 중"
        case .finalizing: label.stringValue = "녹음 저장 중"
        case .recording: label.stringValue = "녹음 중"
        default: label.stringValue = "녹음 시작"
        }
    }
    @objc private func toggleRecording() { menu.cancelTracking(); workspace.toggleRecord(); update() }
    @objc private func showVersion() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "DAMA"])
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "DAMA" && !($0 is NSPanel) }) { window.makeKeyAndOrderFront(nil) }
        else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "DAMA"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LibraryShell(workspace: .shared))
            window.center(); window.makeKeyAndOrderFront(nil); mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
