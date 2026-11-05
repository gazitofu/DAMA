import DamaAudio
import DamaCore
import SwiftUI

/// usage-bundle1 제목 저장 상태 문구 (tone 문구 11).
enum TitleStatus {
    static let typing = "Enter를 누르면 저장합니다."
    static let saving = "제목 저장 중…"
    static let saved = "제목 저장됨"
    static let failed = "제목을 저장하지 못했습니다. 입력한 내용은 유지됩니다."
}

/// Draft lifetime follows the selected Run/view. File mutations remain serialized in FolderLibraryStore.
/// 제목은 Enter·입력칸 이탈 때만 저장한다(0.5초 자동 저장 없음, usage-bundle1 T2a-5).
/// 연결 녹음이 있으면 인덱스 displayTitle에만 쓰고 스크립트 파일은 쓰지 않는다. 연결이 없으면 파일 title.
@MainActor final class ScriptEditingSession: ObservableObject {
    @Published var title: String
    @Published private(set) var titleMessage: String?
    @Published private(set) var bodySource: LibraryScriptFile?
    @Published private(set) var block: ScriptBlock?
    @Published var text = ""
    @Published private(set) var bodyMessage: String?
    @Published private(set) var savingBody = false
    private(set) var file: LibraryScriptFile
    private let workspace: LibraryWorkspace
    private var draft: TitleDraft
    private var composingBody = false
    private var savingTitle = false
    var bodyDirty: Bool { block.map { $0.text != text } ?? false }
    var readOnly: Bool { file.script.snapshotTitle != nil }
    init(file: LibraryScriptFile, workspace: LibraryWorkspace) {
        let resolved = workspace.scriptTitle(file.script)
        self.file = file; title = resolved; draft = TitleDraft(saved: resolved); self.workspace = workspace
    }
    func receive(_ updated: LibraryScriptFile) {
        file = updated
        refreshTitle()
    }
    /// 바깥에서 제목이 바뀌었을 때(파일 갱신·녹음 제목 저장). 고치는 중이거나 저장 중이면 입력을 유지한다.
    func refreshTitle() {
        guard !savingTitle else { return }
        draft.receive(saved: workspace.scriptTitle(file.script))
        if !draft.isDirty { title = draft.text }
    }
    func titleChanged(composing: Bool) {
        _ = draft.handle(.edit(title, composing: composing))
        titleMessage = draft.isDirty ? TitleStatus.typing : nil
        updatePending()
    }
    /// Enter와 입력칸 이탈이 같은 경로로 온다(InlineScriptText commit).
    func commitTitle() {
        guard !readOnly, !savingTitle else { return }
        switch draft.handle(.enter) {
        case .save(let value): save(value)
        case .reject(let message): titleMessage = message
        case .none, .revert: break
        }
    }
    func cancelTitle() {
        guard !savingTitle else { return }
        if case .revert(let value) = draft.handle(.escape) { title = value; titleMessage = nil }
        updatePending()
    }
    private func save(_ value: String) {
        savingTitle = true; titleMessage = TitleStatus.saving; updatePending()
        let source = file, linked = workspace.isLinked(source.script)
        Task {
            do {
                if linked { try await workspace.saveDisplayTitle(value, speechID: source.script.transcript.sessionId) }
                else { file = try await workspace.saveTitle(value, original: source) }
                savingTitle = false; draft.didSave(value)
                titleMessage = draft.isDirty ? TitleStatus.typing : TitleStatus.saved
            } catch {
                savingTitle = false; titleMessage = TitleStatus.failed
            }
            updatePending()
        }
    }
    private func updatePending() { workspace.titlePending = draft.isDirty || savingTitle }
    func begin(_ block: ScriptBlock) {
        guard workspace.canLeave, !readOnly else { return }
        workspace.playback.stop(); bodySource = file; self.block = block
        text = block.text; bodyMessage = nil; composingBody = false; workspace.editing = true
    }
    func bodyChanged(composing: Bool) { composingBody = composing }
    func saveBody() {
        guard let source = bodySource, let block, bodyDirty, !composingBody, !savingBody else { return }
        savingBody = true; bodyMessage = nil
        let submitted = text
        Task {
            do {
                let saved = try await workspace.saveParagraph(block, text: submitted, original: source)
                file = saved; savingBody = false; endBody()
            } catch {
                savingBody = false; bodyMessage = "저장하지 못했습니다. 입력한 내용은 유지됩니다."
            }
        }
    }
    func cancelBody() { guard !savingBody else { return }; endBody() }
    private func endBody() { block = nil; bodySource = nil; text = ""; bodyMessage = nil; workspace.editing = false }
}

/// usage-bundle1 Speech 상세 제목칸. 저장 규칙과 상태 문구는 스크립트 제목칸과 같고, 인덱스 displayTitle에만 쓴다.
@MainActor final class SpeechTitleSession: ObservableObject {
    @Published var title: String
    @Published private(set) var message: String?
    private let speechID: String
    private let workspace: LibraryWorkspace
    private var draft: TitleDraft
    private var saving = false
    init(speech: LibrarySpeech, workspace: LibraryWorkspace) {
        let resolved = workspace.speechTitle(speech)
        speechID = speech.id; title = resolved; draft = TitleDraft(saved: resolved); self.workspace = workspace
    }
    func receive(_ resolved: String) {
        guard !saving else { return }
        draft.receive(saved: resolved)
        if !draft.isDirty { title = draft.text }
    }
    func changed(composing: Bool) {
        _ = draft.handle(.edit(title, composing: composing))
        message = draft.isDirty ? TitleStatus.typing : nil
        updatePending()
    }
    func commit() {
        guard !saving else { return }
        switch draft.handle(.enter) {
        case .save(let value): save(value)
        case .reject(let text): message = text
        case .none, .revert: break
        }
    }
    func cancel() {
        guard !saving else { return }
        if case .revert(let value) = draft.handle(.escape) { title = value; message = nil }
        updatePending()
    }
    private func save(_ value: String) {
        saving = true; message = TitleStatus.saving; updatePending()
        Task {
            do {
                try await workspace.saveDisplayTitle(value, speechID: speechID)
                saving = false; draft.didSave(value)
                message = draft.isDirty ? TitleStatus.typing : TitleStatus.saved
            } catch {
                saving = false; message = TitleStatus.failed
            }
            updatePending()
        }
    }
    private func updatePending() { workspace.titlePending = draft.isDirty || saving }
}
