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
    @Published private(set) var scanIssues: [LibraryFolder: [FileScanIssue]] = [:]
    @Published private(set) var selectedSpeechID: String?
    @Published private(set) var selectedScriptID: String?
    @Published var speakerCount = ""
    @Published var context = ""
    @Published var reference = ""
    @Published var participants = ""
    @Published var meetingTerms = ""
    let playback = SegmentPlayback()
    @Published var message: String?
    @Published private(set) var busy = false
    @Published var editing = false
    @Published var titlePending = false
    @Published private(set) var historicalFile: LibraryScriptFile?
    @Published private(set) var preparingSpeechID: String?
    @Published private(set) var needsDefaultFolderAccess = false
    @Published private(set) var savingRunIDs: Set<String> = []
    private var store: FolderLibraryStore?
    private var root: URL?
    private var started = false
    private var scoped: [URL] = []
    var canLeave: Bool { !busy && !editing && !titlePending && savingRunIDs.isEmpty }
    var speech: LibrarySpeech? { speeches.first { $0.id == selectedSpeechID } }
    var scriptFile: LibraryScriptFile? { scripts.first { $0.id == selectedScriptID } }
    var displayedScript: LibraryScriptFile? { historicalFile ?? scriptFile }
    var primaryScripts: [LibraryScriptFile] { ScriptResultPresentation.primaryFiles(in: scripts) }
    var notesValid: Bool { speakerCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Int(speakerCount).map { $0 > 0 } == true) }
    var notes: ConversionNotes {
        var value = speech?.notes ?? ConversionNotes()
        value.speakerCount = Int(speakerCount); value.context = context; value.reference = reference
        value.participants = participants.isEmpty ? nil : participants; value.meetingTerms = meetingTerms.isEmpty ? nil : meetingTerms
        return value
    }
    var notesDirty: Bool { speech.map { $0.notes != notes } ?? false }
    var foldersLocked: Bool { !canLeave || notesDirty || ProcessingWorkspace.shared.busy || CorrectionWorkspace.shared.busy || RecordingWorkspace.shared.capture.phase.busy }

    func start() {
        guard !started else { return }; started = true
        do {
            let root = try AudioFiles.root(); self.root = root; store = FolderLibraryStore(root: root)
            if let fixture = AudioFiles.uiFixtureFolder {
                for kind in LibraryFolder.allCases { folders[kind] = fixture.appendingPathComponent(kind.rawValue) }
                folder = .scripts; refresh(); return
            }
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
            setUpDefaultFolders()
            refresh()
        } catch { message = "DAMA 저장소를 열지 못했습니다." }
    }
    private var userHome: URL? {
        // NSHomeDirectory() may return an app container in a sandboxed build.
        NSHomeDirectoryForUser(NSUserName()).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    var defaultFolderDescription: String { "~/DAMA/Speeches · ~/DAMA/Scripts" }
    private func setUpDefaultFolders() {
        guard let home = userHome, let root else { return }
        needsDefaultFolderAccess = false
        for kind in LibraryFolder.allCases where UserDefaults.standard.data(forKey: "library.folder.\(kind.rawValue)") == nil {
            do {
                let url = try FolderLibraryStore.prepareDefaultFolder(kind.rawValue, home: home,
                    other: folders[kind == .speeches ? .scripts : .speeches], internalRoot: root)
                try persistFolder(kind, url: url)
                if url.startAccessingSecurityScopedResource() { scoped.append(url) }
                folders[kind] = url
            } catch {
                needsDefaultFolderAccess = true
                message = "기본 폴더를 준비하려면 DAMA 폴더 접근을 허용해 주세요. 기존 파일은 유지됩니다."
            }
        }
    }
    func authorizeDefaultFolders() {
        guard !foldersLocked, let home = userHome else { return }
        let expected = home.appendingPathComponent("DAMA", isDirectory: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "DAMA 폴더 사용"
        panel.directoryURL = FileManager.default.fileExists(atPath: expected.path) ? expected : home
        panel.message = "홈의 DAMA 폴더를 선택해 주세요. 없으면 ‘새로운 폴더’로 DAMA를 만드세요. 안에 Speeches와 Scripts를 준비합니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL.resolvingSymlinksInPath() == expected.standardizedFileURL.resolvingSymlinksInPath() else {
            message = "기본 위치는 ~/DAMA입니다. 다른 위치는 각 폴더의 메뉴에서 선택할 수 있습니다."; return
        }
        if url.startAccessingSecurityScopedResource() { scoped.append(url) }
        message = nil
        setUpDefaultFolders(); refresh()
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
            scanIssues[kind] = []
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
        ProcessingWorkspace.shared.refresh()
        busy = true
        Task {
            defer { busy = false }
            do {
                try await persistNotes()
                if let url = folders[.speeches] {
                    do {
                        let scan = try await store.scanSpeeches(in: url)
                        speeches = scan.items; scanIssues[.speeches] = scan.issues
                        if !speeches.contains(where: { $0.id == selectedSpeechID }) { setSpeech(speeches.first?.id) }
                    } catch { scanIssues[.speeches] = [FileScanIssue(url: url)] }
                }
            } catch { message = "입력 정보를 저장하지 못해 Speeches 갱신을 보류했습니다. 입력값과 기존 목록은 유지됩니다." }
            if let url = folders[.scripts] {
                do {
                    let scan = try await store.scanScripts(in: url)
                    scripts = scan.items; scanIssues[.scripts] = scan.issues
                    if !scripts.contains(where: { $0.id == selectedScriptID }) { historicalFile = nil; selectedScriptID = primaryScripts.first?.id }
                } catch { scanIssues[.scripts] = [FileScanIssue(url: url)] }
            }
        }
    }
    private func setSpeech(_ id: String?) {
        playback.stop()
        selectedSpeechID = id
        let notes = speech?.notes ?? ConversionNotes()
        speakerCount = notes.speakerCount.map(String.init) ?? ""; context = notes.context; reference = notes.reference
        participants = notes.participants ?? ""; meetingTerms = notes.meetingTerms ?? ""
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
        playback.stop()
        Task {
            defer { busy = false }
            do { try await persistNotes(); action() }
            catch { message = "입력 정보를 저장하지 못했습니다. 화자 수와 저장 공간을 확인해 주세요." }
        }
    }
    func selectFolder(_ kind: LibraryFolder) {
        if folders[kind] == nil { chooseFolder(kind); return }
        navigate { self.historicalFile = nil; self.folder = kind }
    }
    func selectSpeech(_ id: String) { navigate { self.historicalFile = nil; self.setSpeech(id); self.folder = .speeches } }
    func selectScript(_ id: String) { navigate { self.historicalFile = nil; self.selectedScriptID = id; self.folder = .scripts } }
    func selectVersion(_ version: ScriptVersion) {
        guard canLeave, let current = scriptFile, let store else { return }
        busy = true; playback.stop()
        Task {
            defer { busy = false }
            do { historicalFile = try await store.readVersion(version, for: current) }
            catch { message = "이 버전을 읽지 못했습니다. 현재 결과는 보존되어 있습니다." }
        }
    }
    func returnToCurrent() { guard canLeave else { return }; playback.stop(); historicalFile = nil }
    func completedScript(for speech: LibrarySpeech) -> LibraryScriptFile? {
        ScriptResultPresentation.primaryFile(in: scripts.filter { $0.script.transcript.sessionId == speech.id })
    }
    func scriptGroupSelected(_ file: LibraryScriptFile) -> Bool {
        guard let selected = scriptFile else { return false }
        return selected.script.transcript.sessionId == file.script.transcript.sessionId
    }

    func canRetranscribe(_ sessionID: String) -> Bool {
        canLeave && notesValid && folders[.scripts] != nil && !RecordingWorkspace.shared.capture.phase.busy &&
        !CorrectionWorkspace.shared.busy && ProcessingWorkspace.shared.canRetranscribe(sessionID)
    }
    func retranscribeSpeech() {
        guard let speech else { return }
        retranscribe(sessionID: speech.id, input: notes)
    }
    func retranscribeScript(_ file: LibraryScriptFile) {
        let sessionID = file.script.transcript.sessionId
        let input = selectedSpeechID == sessionID ? notes : speeches.first { $0.id == sessionID }?.notes ?? file.script.input
        retranscribe(sessionID: file.script.transcript.sessionId, input: input)
    }
    private func retranscribe(sessionID: String, input: ConversionNotes) {
        guard canRetranscribe(sessionID), let root else { return }
        busy = true; preparingSpeechID = sessionID; playback.stop()
        Task {
            defer { busy = false; preparingSpeechID = nil }
            do {
                try await persistNotes()
                let manifest = try await AudioLibrary(root: root).prepareAnalysis(sessionID)
                let prepared = try await ProcessingWorkspace.shared.preparedInput(input)
                await ProcessingWorkspace.shared.reviewTransmission(manifest, input: prepared, retranscribing: true)
            } catch LibraryFailure.invalidInput {
                message = "전사 입력을 확인해 주세요. Soniox 화자 수 힌트는 1~15명입니다. 기본 맥락·참석자·직접 입력 참고·용어는 합계 7,500바이트 이하여야 합니다. 폴더 발췌는 남은 용량 안에서 선택됩니다. 전송하지 않았습니다."
            } catch { message = "재전사할 원음을 준비하지 못했습니다. 이 Mac의 내부 녹음과 참고 폴더 접근을 확인해 주세요. 전송하지 않았습니다." }
        }
    }

    func deleteSpeech(_ speech: LibrarySpeech) {
        guard !foldersLocked, let store, let folder = folders[.speeches] else { return }
        busy = true; playback.stop()
        guard confirmDeletion(title: speech.title, kind: "Speech", detail: "선택한 녹음 파일 또는 녹음 묶음을 휴지통으로 이동합니다. 연결된 Scripts와 내부 원음 사본은 남아 재생·재전사에 사용할 수 있습니다.") else { busy = false; return }
        Task {
            defer { busy = false }
            do {
                try await store.trashSpeech(speech, in: folder)
                speeches.removeAll { $0.fileURL == speech.fileURL }
                if selectedSpeechID == speech.id { setSpeech(speeches.first?.id) }
                message = "Speech를 휴지통으로 이동했습니다. 연결된 Scripts와 내부 복구 사본은 유지됩니다."
            } catch { message = "Speech를 삭제하지 못했습니다. 파일 변경 여부와 폴더 권한을 확인한 뒤 새로고침해 주세요. 영구 삭제로 재시도하지 않습니다." }
        }
    }
    func deleteScript(_ file: LibraryScriptFile) {
        guard !foldersLocked, let store, let folder = folders[.scripts] else { return }
        busy = true; playback.stop()
        guard confirmDeletion(title: file.script.title, kind: "Script", detail: "선택한 스크립트 파일을 휴지통으로 이동합니다. 연결된 Speech·다른 Scripts·내보낸 Markdown과 내부 복구 이력은 남습니다.") else { busy = false; return }
        Task {
            defer { busy = false }
            do {
                try await store.trashScript(file, in: folder)
                scripts.removeAll { $0.url == file.url }
                if selectedScriptID == file.id { selectedScriptID = primaryScripts.first?.id }
                message = "Script를 휴지통으로 이동했습니다. 원음과 다른 스크립트는 유지됩니다."
            } catch { message = "Script를 삭제하지 못했습니다. 파일 변경 여부와 폴더 권한을 확인한 뒤 새로고침해 주세요. 영구 삭제로 재시도하지 않습니다." }
        }
    }
    private func confirmDeletion(title: String, kind: String, detail: String) -> Bool {
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "\(kind)를 삭제할까요?"
        alert.informativeText = "\(title)\n\n\(detail)\n\n휴지통에서 되돌릴 수 있습니다. 서버에 전송된 데이터는 삭제하지 않습니다."
        alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "휴지통으로 이동")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func convert() {
        guard canLeave, notesValid, let speech, let root, folders[.scripts] != nil else { return }
        let processing = ProcessingWorkspace.shared
        if let run = processing.run(for: speech.id) {
            if run.stage == "readyForReview" {
                if let existing = scripts.first(where: { $0.id == run.id }) { selectScript(existing.id) }
                else { processingFinished(run) }
                return
            }
            if processing.canResume(run) { processing.resume(run) }
            else { message = processing.label(run) }
            return
        }
        if let existing = completedScript(for: speech) { selectScript(existing.id); return }
        let input = notes
        busy = true
        preparingSpeechID = speech.id
        Task {
            defer { busy = false; preparingSpeechID = nil }
            do {
                try await persistNotes()
                let manifest = try await AudioLibrary(root: root).prepareAnalysis(speech.id)
                let prepared = try await processing.preparedInput(input)
                await processing.reviewTransmission(manifest, input: prepared)
            } catch LibraryFailure.invalidInput {
                message = "전사 입력을 확인해 주세요. Soniox 화자 수 힌트는 1~15명입니다. 기본 맥락·참석자·직접 입력 참고·용어는 합계 7,500바이트 이하여야 합니다. 폴더 발췌는 남은 용량 안에서 선택됩니다. 전송하지 않았습니다."
            } catch { message = "원본 확인 또는 분석 파일 준비에 실패했습니다. 음성을 전송하지 않았습니다." }
        }
    }
    func processingFinished(_ run: ManagedRun, select: Bool = true) {
        guard run.provider != .precision else { return }
        guard let store, let root, let destination = folders[.scripts] else {
            message = "결과는 내부에 보존했습니다. 해당 Speeches와 Scripts 폴더를 선택한 뒤 스크립트를 저장해 주세요."
            return
        }
        guard savingRunIDs.insert(run.id).inserted else { return }
        // A remote completion may arrive while a different script is being edited.
        Task {
            defer { savingRunIDs.remove(run.id) }
            do {
                guard let speech = try await store.storedSpeech(run.sessionID) else { throw LibraryFailure.missingFile }
                let document = try await FileSessionRepository(rootURL: root).loadModel(sessionId: run.sessionID, runId: run.id)
                let result = try await store.createScript(document, speech: speech, input: run.input ?? speech.notes, in: destination)
                let scan = try await store.scanScripts(in: destination)
                scripts = scan.items; scanIssues[.scripts] = scan.issues
                if !select {
                    var saved = Set(UserDefaults.standard.stringArray(forKey: "library.savedSourceRuns") ?? [])
                    saved.insert(run.id); UserDefaults.standard.set(Array(saved), forKey: "library.savedSourceRuns")
                }
                savingRunIDs.remove(run.id)
                if select && canLeave && !notesDirty { historicalFile = nil; selectedScriptID = result.id; folder = .scripts }
                message = "스크립트를 저장했습니다. 화자와 내용을 확인해 주세요."
                if result.script.correction == nil, run.input?.aiCorrection == true {
                    CorrectionWorkspace.shared.enqueue(result, input: run.input!)
                }
            } catch { message = "스크립트 저장이 필요합니다. 변환 버튼으로 로컬 저장을 다시 시도할 수 있습니다. 음성을 다시 제출하지 않습니다." }
        }
    }
    func saveScript(_ candidate: LibraryScript, original: LibraryScriptFile) async throws {
        guard !busy, let store else { throw LibraryFailure.invalidInput }
        busy = true; defer { busy = false }
        let result = try await store.saveScript(candidate, to: original.url, expectedHash: original.hash)
        if let i = scripts.firstIndex(where: { $0.url == original.url }) { scripts[i] = result }
    }
    func saveTitle(_ title: String, original: LibraryScriptFile) async throws -> LibraryScriptFile {
        guard !busy, historicalFile == nil, let store else { throw LibraryFailure.invalidInput }
        busy = true; defer { busy = false }
        let result = try await store.saveTitle(title, for: original)
        if let i = scripts.firstIndex(where: { $0.url == original.url }) { scripts[i] = result }
        return result
    }
    func saveParagraph(_ block: ScriptBlock, text: String, original: LibraryScriptFile) async throws -> LibraryScriptFile {
        guard !busy, historicalFile == nil, let store else { throw LibraryFailure.invalidInput }
        busy = true; defer { busy = false }
        let result = try await store.saveParagraph(block, text: text, for: original)
        if let i = scripts.firstIndex(where: { $0.url == original.url }) { scripts[i] = result }
        return result
    }
    func storeCorrection(_ correction: ScriptCorrection, file: LibraryScriptFile) async throws {
        guard let store else { throw LibraryFailure.invalidInput }
        // Re-read and merge only the AI layer. Concurrent manual edits remain authoritative.
        let result = try await store.saveCorrection(correction, for: file)
        if let i = scripts.firstIndex(where: { $0.id == result.id }) { scripts[i] = result }
    }
    func applyPendingCorrection(_ file: LibraryScriptFile) async throws {
        guard historicalFile == nil, canLeave, !CorrectionWorkspace.shared.busy, let store else { throw LibraryFailure.invalidInput }
        busy = true; defer { busy = false }
        let result = try await store.applyPendingCorrection(for: file)
        if let i = scripts.firstIndex(where: { $0.id == result.id }) { scripts[i] = result }
    }
    func validateCorrectionSource(_ file: LibraryScriptFile) async throws {
        guard historicalFile == nil, let store else { throw LibraryFailure.invalidInput }
        try await store.validateCurrent(file)
    }
    func toggleOriginal(_ file: LibraryScriptFile) {
        guard canLeave else { return }
        Task {
            do {
                var script = file.script; script.showsOriginal = !(script.showsOriginal ?? false); script.revisionID = UUID().uuidString
                try await saveScript(script, original: file)
            } catch { message = "표시 선택을 저장하지 못했습니다. 파일을 새로 고친 뒤 다시 시도해 주세요." }
        }
    }
    func resolveCorrection(_ edit: CorrectionEdit, apply: Bool, file: LibraryScriptFile) {
        guard canLeave else { return }
        Task {
            do {
                var candidate = file.script
                try candidate.editText(edit.turnID, text: apply ? edit.text : edit.original)
                try await saveScript(candidate, original: file)
            } catch { message = "교정 선택을 저장하지 못했습니다. 파일의 변경 여부를 확인한 뒤 다시 시도해 주세요." }
        }
    }
    func play(_ block: ScriptBlock, file: LibraryScriptFile) {
        play(id: block.id, startUs: block.startUs, endUs: block.endUs, file: file)
    }
    func play(_ event: ScriptReviewEvent, file: LibraryScriptFile) {
        play(id: "event:" + event.id, startUs: event.startUs, endUs: event.endUs, file: file, context: true)
    }
    private func play(id: String, startUs: Int64?, endUs: Int64?, file: LibraryScriptFile, context: Bool = false) {
        guard !RecordingWorkspace.shared.capture.phase.busy, let root else { return }
        do {
            let session = try AudioFiles.session(file.script.transcript.sessionId, root: root)
            playback.play(url: session.appendingPathComponent("audio/analysis.wav"), id: file.id + ":" + id,
                          startUs: startUs, endUs: endUs, context: context)
        } catch { playback.message = "원음 위치를 찾을 수 없습니다. 이 Mac에 해당 녹음이 보존되어 있는지 확인해 주세요." }
    }
    func exportMarkdown() {
        guard canLeave, let file = displayedScript, let store else { return }
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
    var monthlyCost: MonthlyOperatingCost {
        UserDefaults.standard.data(forKey: "evaluation.monthlyCost").flatMap { try? JSONDecoder().decode(MonthlyOperatingCost.self, from: $0) } ?? MonthlyOperatingCost()
    }
    func saveMonthlyCost(_ cost: MonthlyOperatingCost) throws {
        try cost.validate()
        UserDefaults.standard.set(try JSONEncoder().encode(cost), forKey: "evaluation.monthlyCost")
    }
    func exportEvaluation() {
        guard canLeave, let file = scriptFile, let store else { return }
        let cost = monthlyCost, protectedSpeechURLs = speeches.map(\.fileURL)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DAMA-evaluation-" + file.id + ".json"
        panel.message = "원문·수정 이력·문맥·검수 표본과 수동 입력한 월 비용을 저장합니다. 자동 외부 전송은 없습니다."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true
        Task {
            defer { busy = false }
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            do {
                try await store.exportEvaluation(file, cost: cost, protectedSpeechURLs: protectedSpeechURLs, to: destination)
                message = "평가 JSON을 저장했습니다. 정확도와 미측정 비용을 자동 추정하지 않습니다."
            } catch { message = "평가 파일을 저장하지 못했습니다. 원본 파일과 저장 위치를 확인해 주세요." }
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
