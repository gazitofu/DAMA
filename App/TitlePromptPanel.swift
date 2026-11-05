import AppKit
import Combine
import DamaAudio
import DamaCore
import SwiftUI

/// usage-bundle1 녹음 직후 제목 입력창 (스펙 §02-2 «녹음 직후 입력창»·§03 S3, tone 문구 10·11).
/// 마이크 녹음 원본이 저장되고 Speeches 새로고침이 인덱스 항목을 확인한 뒤에만, 한 번에 하나씩 띄운다.
/// 녹음과 원본 저장을 막지 않는 작은 패널(NSPanel)이라 Dock·Cmd+Tab 계산에 들어가지 않는다(AppLifecycle).
@MainActor final class TitlePromptPanelController: NSObject, NSWindowDelegate {
    static let shared = TitlePromptPanelController()
    private var panel: TitlePromptPanel?
    private var shownID: String?
    private var subscription: AnyCancellable?

    func start() {
        guard subscription == nil else { return }
        subscription = LibraryWorkspace.shared.$titlePrompts.map(\.current).removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self] id in self?.show(id) }
    }

    func discardAll() {
        LibraryWorkspace.shared.discardTitlePrompts()
        close()
    }

    private func show(_ id: String?) {
        guard id != shownID else { return }
        close()
        guard let id, let info = TitlePromptInfo(id: id, workspace: .shared) else { return }
        shownID = id
        let panel = TitlePromptPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "녹음 제목"
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.later() }
        panel.contentView = NSHostingView(rootView: TitlePromptView(info: info, later: { [weak self] in self?.later() },
            saved: { [weak self] in self?.finished() }))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 440, height: 220))
        // 화면 가운데 위쪽. 메뉴바 녹음 토글(오른쪽 위 메뉴)을 가리지 않는다.
        if let screen = NSScreen.main?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - screen.height * 0.12))
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    /// «나중에»·Esc·창 닫기: 쓰기 없이 닫고 다음 것을 보인다.
    private func later() { LibraryWorkspace.shared.dismissTitlePrompt() }
    /// 저장 성공: 닫고 다음 것을 보인다.
    private func finished() { LibraryWorkspace.shared.dismissTitlePrompt() }

    private func close() {
        shownID = nil
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil); panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        // 제목 표시줄의 닫기 단추. 저장 중이 아니면 «나중에»와 같다.
        guard (notification.object as? TitlePromptPanel) === panel else { return }
        panel = nil; shownID = nil
        LibraryWorkspace.shared.dismissTitlePrompt()
    }
}

/// Esc를 «나중에»로 받는 패널. 입력칸이 조합 중이면 Esc는 입력기 몫이라 여기까지 오지 않는다.
final class TitlePromptPanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

struct TitlePromptInfo {
    let id: String
    let autoTitle: String
    let subtitle: String

    @MainActor init?(id: String, workspace: LibraryWorkspace) {
        let speech = workspace.speeches.first { $0.id == id }
        let record = workspace.promptRecords[id]
        guard speech != nil || record != nil else { return nil }
        self.id = id
        autoTitle = speech?.title ?? record?.title ?? ""
        let recordedAt = speech?.recordedAt ?? record?.createdAt
        let duration = speech?.durationUs ?? record?.durationUs
        subtitle = "\(recordedAt?.formatted(date: .numeric, time: .shortened) ?? "녹음 날짜 미확인") · \(LibraryScript.timestamp(duration))"
    }
}

private struct TitlePromptView: View {
    let info: TitlePromptInfo
    let later: () -> Void
    let saved: () -> Void
    @State private var text = ""
    @State private var composing = false
    @State private var saving = false
    @State private var failed = false
    private var canSave: Bool { !saving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("녹음 제목").font(.headline)
            Text(info.subtitle).font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(info.autoTitle).font(.system(size: 15)).foregroundStyle(.tertiary).accessibilityHidden(true).allowsHitTesting(false)
                }
                InlineScriptText(text: $text, editable: !saving, title: true, focus: true, label: "녹음 제목",
                    changed: { composing = $0 }, commit: save, cancel: { if !saving { later() } },
                    commitOnEndEditing: false, fontSize: 15)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
            Text("녹음은 이미 저장했습니다. 제목은 나중에 Speeches에서도 바꿀 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            if failed { Text(TitleStatus.failed).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("나중에", action: later).disabled(saving)
                Button("저장", action: save).disabled(!canSave)
            }
        }.padding(18).frame(width: 440)
    }

    /// Enter(조합 중 아님)·«저장». 입력은 다듬지 않고 그대로 인덱스 displayTitle에 쓴다.
    private func save() {
        guard canSave, !composing else { return }
        saving = true; failed = false
        let value = text
        Task { @MainActor in
            do { try await LibraryWorkspace.shared.saveDisplayTitle(value, speechID: info.id); saved() }
            catch { saving = false; failed = true }
        }
    }
}
