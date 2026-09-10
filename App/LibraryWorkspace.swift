import AppKit
import DamaAudio
import DamaCore
import DamaManaged
import SwiftUI
import UniformTypeIdentifiers

enum LibraryFolder: String, CaseIterable, Identifiable { case speeches = "Speeches", scripts = "Scripts"; var id: String { rawValue } }

@MainActor final class LibraryWorkspace: ObservableObject {
    static let shared = LibraryWorkspace()
    @Published var folder: LibraryFolder = .speeches
    @Published private(set) var folders: [LibraryFolder: URL] = [:]
    @Published private(set) var speeches: [LibrarySpeech] = []
    @Published private(set) var scripts: [LibraryScriptFile] = []
    @Published private(set) var selectedSpeechID: String?
    @Published private(set) var selectedScriptID: String?
    @Published var speakerCount = ""
    @Published var context = ""
    @Published var reference = ""
    @Published var message: String?
    @Published private(set) var busy = false
    @Published var editing = false
    @Published private(set) var preparingSpeechID: String?
    private var store: FolderLibraryStore?
    private var root: URL?
    private var started = false
    private var scoped: [URL] = []
    var canLeave: Bool { !busy && !editing }
    var speech: LibrarySpeech? { speeches.first { $0.id == selectedSpeechID } }
    var scriptFile: LibraryScriptFile? { scripts.first { $0.id == selectedScriptID } }
    var notesValid: Bool { speakerCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Int(speakerCount).map { $0 > 0 } == true) }
    var notes: ConversionNotes { ConversionNotes(speakerCount: Int(speakerCount), context: context, reference: reference) }
    var notesDirty: Bool { speech.map { $0.notes != notes } ?? false }
    var foldersLocked: Bool { !canLeave || notesDirty || ProcessingWorkspace.shared.busy || RecordingWorkspace.shared.capture.phase.busy }

    func start() {
        guard !started else { return }; started = true
        do {
            let root = try AudioFiles.root(); self.root = root; store = FolderLibraryStore(root: root)
            for folder in LibraryFolder.allCases {
                guard let data = UserDefaults.standard.data(forKey: "library.folder.\(folder.rawValue)") else { continue }
                do {
                    var stale = false
                    let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                    if url.startAccessingSecurityScopedResource() { scoped.append(url) }
                    try FolderLibraryStore.validateFolder(url, other: folders.values.first, internalRoot: root)
                    folders[folder] = url
                    if stale { try persistFolder(folder, url: url) }
                } catch { message = "\(folder.rawValue) 폴더에 접근할 수 없습니다. 다시 선택해 주세요." }
            }
            refresh()
        } catch { message = "DAMA 저장소를 열지 못했습니다." }
    }
    private func persistFolder(_ folder: LibraryFolder, url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: "library.folder.\(folder.rawValue)")
    }
    func chooseFolder(_ kind: LibraryFolder) {
        guard !foldersLocked, let root else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "선택"
        panel.message = "\(kind.rawValue) 폴더를 선택해 주세요. 기존 파일은 이동하지 않습니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            try FolderLibraryStore.validateFolder(url, other: folders[kind == .speeches ? .scripts : .speeches], internalRoot: root)
            try persistFolder(kind, url: url)
            if let old = folders[kind], let i = scoped.firstIndex(of: old) { scoped.remove(at: i).stopAccessingSecurityScopedResource() }
            if accessed { scoped.append(url) }
            folders[kind] = url; folder = kind
            if kind == .speeches { speeches = []; selectedSpeechID = nil }
            else { scripts = []; selectedScriptID = nil }
            refresh()
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            message = "폴더를 선택하지 못했습니다. 다른 보관 폴더와 겹치지 않는 쓰기 가능한 폴더를 선택해 주세요."
        }
    }
    func revealFolder(_ kind: LibraryFolder) {
        if let url = folders[kind] { NSWorkspace.shared.open(url) }
    }
    func refresh() {
        guard canLeave, let store else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await persistNotes()
                if let url = folders[.speeches] {
                    speeches = try await store.speeches(in: url)
                    if !speeches.contains(where: { $0.id == selectedSpeechID }) { setSpeech(speeches.first?.id) }
                }
                if let url = folders[.scripts] {
                    scripts = try await store.scripts(in: url)
                    if !scripts.contains(where: { $0.id == selectedScriptID }) { selectedScriptID = scripts.first?.id }
                }
            } catch { message = "파일 목록을 읽지 못했습니다. 폴더 접근 권한·파일 형식·변경 여부를 확인해 주세요. 이전 목록은 유지됩니다." }
        }
    }
    private func setSpeech(_ id: String?) {
        selectedSpeechID = id
        let notes = speech?.notes ?? ConversionNotes()
        speakerCount = notes.speakerCount.map(String.init) ?? ""; context = notes.context; reference = notes.reference
    }
    private func persistNotes() async throws {
        guard let speech, let store, notesDirty else { return }
        guard notesValid else { throw LibraryFailure.invalidInput }
        let value = notes
        try await store.saveNotes(value, speechID: speech.id)
        if let i = speeches.firstIndex(where: { $0.id == speech.id }) { speeches[i].notes = value }
    }
    func saveNotes() { navigate {} }
    private func navigate(_ action: @escaping @MainActor () -> Void) {
        guard canLeave else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await persistNotes(); action() }
            catch { message = "입력 정보를 저장하지 못했습니다. 화자 수와 저장 공간을 확인해 주세요." }
        }
    }
    func selectFolder(_ kind: LibraryFolder) {
        if folders[kind] == nil { chooseFolder(kind); return }
        navigate { self.folder = kind }
    }
    func selectSpeech(_ id: String) { navigate { self.setSpeech(id); self.folder = .speeches } }
    func selectScript(_ id: String) { navigate { self.selectedScriptID = id; self.folder = .scripts } }
    func completedScript(for speech: LibrarySpeech) -> LibraryScriptFile? { scripts.first { $0.script.transcript.sessionId == speech.id } }

    func convert() {
        guard canLeave, notesValid, let speech, let root, folders[.scripts] != nil else { return }
        if let existing = completedScript(for: speech) { selectScript(existing.id); return }
        let processing = ProcessingWorkspace.shared
        if let run = processing.run(for: speech.id) {
            if run.stage == "readyForReview" { processingFinished(run); return }
            if processing.canResume(run) { processing.resume(run) }
            else { message = processing.label(run) }
            return
        }
        let input = notes
        busy = true
        preparingSpeechID = speech.id
        Task {
            defer { busy = false; preparingSpeechID = nil }
            do {
                try await persistNotes()
                let manifest = try await AudioLibrary(root: root).prepareAnalysis(speech.id)
                processing.reviewTransmission(manifest, input: input)
            } catch { message = "원본 확인 또는 분석 파일 준비에 실패했습니다. 음성을 전송하지 않았습니다." }
        }
    }
    func processingFinished(_ run: ManagedRun) {
        guard let store, let root, let destination = folders[.scripts],
              let speech = speeches.first(where: { $0.id == run.sessionID }) else {
            message = "결과는 내부에 보존했습니다. 해당 Speeches와 Scripts 폴더를 선택한 뒤 스크립트를 저장해 주세요."
            return
        }
        // A remote completion may arrive while a different script is being edited.
        Task {
            do {
                let document = try await FileSessionRepository(rootURL: root).load(sessionId: run.sessionID, revisionId: nil)
                let result = try await store.createScript(document, speech: speech, input: run.input ?? speech.notes, in: destination)
                scripts = try await store.scripts(in: destination)
                if canLeave && !notesDirty { selectedScriptID = result.id; folder = .scripts }
                message = "스크립트를 저장했습니다. 화자와 내용을 확인해 주세요."
            } catch { message = "스크립트 저장이 필요합니다. 변환 버튼으로 로컬 저장을 다시 시도할 수 있습니다. 음성을 다시 제출하지 않습니다." }
        }
    }
    func saveScript(_ candidate: LibraryScript, original: LibraryScriptFile) async throws {
        guard !busy, let store else { throw LibraryFailure.invalidInput }
        busy = true; defer { busy = false }
        let result = try await store.saveScript(candidate, to: original.url, expectedHash: original.hash)
        if let i = scripts.firstIndex(where: { $0.url == original.url }) { scripts[i] = result }
    }
    func exportMarkdown() {
        guard canLeave, let file = scriptFile, let store else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = file.script.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".md"
        panel.title = "Markdown 내보내기"
        panel.message = "녹음 정보·변환 전 입력·화자·대화·타임스탬프를 저장합니다."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true
        Task {
            defer { busy = false }
            let accessed = destination.startAccessingSecurityScopedResource()
            defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
            do { try await store.exportMarkdown(file, to: destination); message = "Markdown 파일을 저장했습니다." }
            catch { message = "내보내지 못했습니다. 원본 스크립트의 변경 여부와 저장 권한을 확인해 주세요." }
        }
    }
    func recordingSaved(_ record: AudioManifest) {
        guard let store, let destination = folders[.speeches] else {
            message = "녹음 원본은 내부에 보존했습니다. Speeches 폴더를 선택한 뒤 보존된 녹음을 저장할 수 있습니다."; return
        }
        Task {
            do { try await store.publishRecording(record, to: destination); refresh() }
            catch { message = "Speeches에 저장하지 못했습니다. 내부 원본은 보존되어 있습니다." }
        }
    }
    func recoverRecordings() {
        guard !foldersLocked, let root, let store, let destination = folders[.speeches] else { return }
        busy = true
        Task {
            do {
                for record in try await AudioLibrary(root: root).list(recover: true) where record.origin == "microphone" {
                    try await store.publishRecording(record, to: destination)
                }
                busy = false; refresh()
            } catch { busy = false; message = "보존된 녹음을 저장하지 못했습니다. 내부 원본은 유지됩니다." }
        }
    }
    func preventLeaving() { message = "열려 있는 편집을 저장하거나 취소하고, 저장 중인 작업이 끝난 뒤 종료해 주세요." }
}
