import DamaAudio
import DamaCore
import SwiftUI

/// Draft lifetime follows the selected Run/view. File mutations remain serialized in FolderLibraryStore.
@MainActor final class ScriptEditingSession: ObservableObject {
    @Published var title: String
    @Published private(set) var titleMessage: String?
    @Published private(set) var bodySource: LibraryScriptFile?
    @Published private(set) var block: ScriptBlock?
    @Published var text = ""
    @Published private(set) var bodyMessage: String?
    @Published private(set) var savingBody = false
    private(set) var file: LibraryScriptFile
    private var titleSource: LibraryScriptFile
    private let workspace: LibraryWorkspace
    private var debounce: Task<Void, Never>?
    private var composingTitle = false
    private var composingBody = false
    private var savingTitle: String?
    var bodyDirty: Bool { block.map { $0.text != text } ?? false }
    var readOnly: Bool { file.script.snapshotTitle != nil }
    init(file: LibraryScriptFile, workspace: LibraryWorkspace) {
        self.file = file; titleSource = file; title = file.script.title; self.workspace = workspace
    }
    func receive(_ updated: LibraryScriptFile) {
        file = updated
        if !workspace.titlePending && savingTitle == nil { titleSource = updated; title = updated.script.title }
    }
    func titleChanged(composing: Bool) {
        composingTitle = composing; debounce?.cancel(); debounce = nil
        workspace.titlePending = title != titleSource.script.title || savingTitle != nil
        titleMessage = workspace.titlePending ? "제목 저장 중…" : nil
        guard workspace.titlePending, !composing, savingTitle == nil else { return }
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self else { return }; self.debounce = nil; self.commitTitle()
        }
    }
    func commitTitle() {
        debounce?.cancel(); debounce = nil
        guard !readOnly, !composingTitle, savingTitle == nil, title != titleSource.script.title else { return }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            titleMessage = "제목을 입력해 주세요."; return
        }
        let submitted = title, source = titleSource
        savingTitle = submitted; workspace.titlePending = true
        Task {
            do {
                let saved = try await workspace.saveTitle(submitted, original: source)
                file = saved; titleSource = saved; savingTitle = nil
                workspace.titlePending = title != submitted
                if workspace.titlePending { titleChanged(composing: composingTitle) }
                else { titleMessage = "자동 저장됨" }
            } catch {
                savingTitle = nil; workspace.titlePending = true
                titleMessage = "제목을 저장하지 못했습니다. 입력한 내용은 유지됩니다."
            }
        }
    }
    func cancelTitle() {
        debounce?.cancel(); debounce = nil
        title = savingTitle ?? titleSource.script.title
        workspace.titlePending = savingTitle != nil; titleMessage = nil
    }
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
