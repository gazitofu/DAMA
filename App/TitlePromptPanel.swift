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
    private var model: TitlePromptModel?
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
        guard id != model?.id else { return }
        close()
        guard let id, let info = TitlePromptInfo(id: id, workspace: .shared) else { return }
        let model = TitlePromptModel(info: info)
        model.onSaved = { [weak self] in self?.dismiss(id) }
        self.model = model
        let panel = TitlePromptPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "녹음 제목"
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.later() }
        panel.contentView = NSHostingView(rootView: TitlePromptView(model: model, later: { [weak self] in self?.later() }))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 440, height: 220))
        // 화면 가운데 위쪽. 메뉴바 녹음 토글(오른쪽 위 메뉴)을 가리지 않는다.
        if let screen = NSScreen.main?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - screen.height * 0.12))
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    /// «나중에»·Esc: 쓰기 없이 닫고 다음 것을 보인다. 저장 중에는 받지 않는다 (QA B D-2).
    private func later() {
        guard let model, !model.saving else { return }
        dismiss(model.id)
    }
    /// 이 입력창(id)만 닫는다. 다른 입력창이 이미 보이면 아무것도 하지 않는다.
    private func dismiss(_ id: String) { LibraryWorkspace.shared.dismissTitlePrompt(id) }

    private func close() {
        model = nil
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil); panel.close()
    }

    /// 제목 표시줄의 닫기 단추. 저장 중이면 닫지 않는다.
    func windowShouldClose(_ sender: NSWindow) -> Bool { !(model?.saving ?? false) }
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? TitlePromptPanel) === panel, let id = model?.id else { return }
        panel = nil; model = nil
        dismiss(id)
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

/// 입력창 하나의 상태. 저장 중이면 입력·버튼·닫기·Esc를 막는다.
@MainActor final class TitlePromptModel: ObservableObject {
    let info: TitlePromptInfo
    var id: String { info.id }
    @Published var text = ""
    @Published private(set) var saving = false
    @Published private(set) var failed = false
    var composing = false
    var onSaved: () -> Void = {}
    var canSave: Bool { !saving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    init(info: TitlePromptInfo) { self.info = info }

    /// Enter(조합 중 아님)·«저장». 입력은 다듬지 않고 그대로 인덱스 displayTitle에 쓴다.
    func save() {
        guard canSave, !composing else { return }
        saving = true; failed = false
        let value = text, id = info.id
        Task {
            do { try await LibraryWorkspace.shared.saveDisplayTitle(value, speechID: id); saving = false; onSaved() }
            catch { saving = false; failed = true }
        }
    }
}

private struct TitlePromptView: View {
    @ObservedObject var model: TitlePromptModel
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("녹음 제목").font(.headline)
            Text(model.info.subtitle).font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text(model.info.autoTitle).font(.system(size: 15)).foregroundStyle(.tertiary).accessibilityHidden(true).allowsHitTesting(false)
                }
                InlineScriptText(text: $model.text, editable: !model.saving, title: true, focus: true, label: "녹음 제목",
                    changed: { model.composing = $0 }, commit: model.save, cancel: later,
                    commitOnEndEditing: false, fontSize: 15)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
            Text("녹음은 이미 저장했습니다. 제목은 나중에 Speeches에서도 바꿀 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            if model.failed { Text(TitleStatus.failed).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("나중에", action: later).disabled(model.saving)
                Button("저장", action: model.save).disabled(!model.canSave)
            }
        }.padding(18).frame(width: 440)
    }
}
