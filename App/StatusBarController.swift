import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = NSPopover()
    private let workspace = RecordingWorkspace.shared
    private var subscriptions = Set<AnyCancellable>()
    private var reviewWindow: NSWindow?

    override init() {
        super.init()
        workspace.start()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "다마")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("다마 녹음 시작·종료")
            button.setAccessibilityHelp("좌클릭은 녹음 시작 또는 종료. Control 클릭이나 우클릭은 녹음 패널 열기.")
        }
        panel.behavior = .transient
        panel.contentViewController = NSHostingController(rootView: RecordingPanel(
            workspace: workspace, capture: workspace.capture, openReview: { [weak self] in self?.showReview() }
        ))
        workspace.capture.$phase.sink { [weak self] phase in
            self?.item.button?.image = NSImage(systemSymbolName: phase == .recording ? "record.circle.fill" : "mic",
                                              accessibilityDescription: phase == .recording ? "녹음 중" : "다마")
            self?.item.button?.toolTip = phase == .recording ? "좌클릭: 녹음 종료 · 우클릭: 패널" : "좌클릭: 녹음 시작 · 우클릭: 패널"
        }.store(in: &subscriptions)
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            if panel.isShown { panel.performClose(nil) }
            else if let button = item.button { panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        } else { workspace.toggleRecord() }
    }

    private func showReview() {
        panel.performClose(nil)
        if let window = NSApp.windows.first(where: { $0.title == "다마" && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "다마"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ReviewShell(workspace: .shared))
            window.center()
            window.makeKeyAndOrderFront(nil)
            reviewWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
