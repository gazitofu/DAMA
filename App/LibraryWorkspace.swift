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
    /// Listed from validated summaries; the selected Script's body is read on demand (library-script.md).
    @Published private(set) var scripts: [LibraryScriptSummary] = []
    @Published private(set) var openedScript: LibraryScriptFile?
    /// The Script listing is incomplete while true: actions that create or submit work stay blocked.
    @Published private(set) var scriptsLoading = false
    @Published private(set) var loadingScriptID: String?
    @Published private(set) var scanIssues: [LibraryFolder: [FileScanIssue]] = [:]
    @Published private(set) var selectedSpeechID: String?
    @Published private(set) var selectedScriptID: String? { didSet { openSelectedScript() } }
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
    /// usage-bundle2 저장 공간 정리 확인·실행 중(AI 교정 시작을 막는다).
    @Published private(set) var storageCleanupActive = false
    /// usage-bundle2 설정 «저장 공간» 상태(문구 11–23).
    enum StorageCleanupPhase: Equatable { case idle, checking, running(done: Int, total: Int), finished(String), nothing, failed }
    @Published fileprivate(set) var storageCleanup: StorageCleanupPhase = .idle
    /// 설정을 열 때 잰 «내부 수정 이력 {크기}» 바이트(nil = 아직 안 잼).
    @Published private(set) var revisionBytes: Int64?
    /// usage-bundle1 녹음 표시 제목: 인덱스 전체(휴지통 항목 포함)의 id → displayTitle, 연결 판정용 id 집합.
    @Published private(set) var displayTitles: [String: String] = [:]
    @Published private(set) var indexedSpeechIDs: Set<String> = []
    /// usage-bundle1 녹음 직후 제목 입력창 줄. 끝난 마이크 녹음만 들어오고 인덱스에서 확인된 것만 보인다.
    @Published private(set) var titlePrompts = TitlePromptQueue()
    private(set) var promptRecords: [String: AudioManifest] = [:]
    /// Speeches 저장을 마친 녹음 → 그때의 새로고침 세대. 그 뒤에 시작한 새로고침에서도 인덱스에 없으면 건너뛴다.
    private var publishedPrompts: [String: Int] = [:]
    private var refreshGeneration = 0
    private var promptRefresh: Task<Void, Never>?
    private var store: FolderLibraryStore?
    private var root: URL?
    private var started = false
    private var scoped: [URL] = []
    private var failedOpen: String?
    var canLeave: Bool { !busy && !editing && !titlePending && savingRunIDs.isEmpty }
    var speech: LibrarySpeech? { speeches.first { $0.id == selectedSpeechID } }
    var scriptFile: LibraryScriptFile? { openedScript.flatMap { $0.id == selectedScriptID ? $0 : nil } }
    var displayedScript: LibraryScriptFile? { historicalFile ?? scriptFile }
    /// 녹음 제목 = displayTitle, 없으면 기존 title (계약 library-script.md «녹음 표시 제목»).
    func speechTitle(_ speech: LibrarySpeech) -> String { displayTitles[speech.id] ?? LibraryTitles.speech(speech) }
    func speechTitle(id: String, fallback: String) -> String { displayTitles[id] ?? fallback }
    /// 스크립트 제목 = 연결 녹음의 displayTitle, 없으면 파일 title. AI 버전 보기는 당시 제목.
    func scriptTitle(_ summary: LibraryScriptSummary) -> String {
        LibraryTitles.script(fileTitle: summary.title, sessionID: summary.sessionId, displayTitles: displayTitles)
    }
    func scriptTitle(_ script: LibraryScript) -> String { LibraryTitles.script(script, displayTitles: displayTitles) }
    /// 연결 = 인덱스 항목 id가 스크립트 sessionId와 같음(Speech 파일이 휴지통에 있어도). AI 버전 보기는 제외.
    func isLinked(_ script: LibraryScript) -> Bool { script.snapshotTitle == nil && indexedSpeechIDs.contains(script.transcript.sessionId) }
    var primaryScripts: [LibraryScriptSummary] { ScriptResultPresentation.primaryFiles(in: scripts) }
    var notesValid: Bool { speakerCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Int(speakerCount).map { $0 > 0 } == true) }
    var notes: ConversionNotes {
        var value = speech?.notes ?? ConversionNotes()
        value.speakerCount = Int(speakerCount); value.context = context; value.reference = reference
        value.participants = participants.isEmpty ? nil : participants; value.meetingTerms = meetingTerms.isEmpty ? nil : meetingTerms
        return value
    }
    var notesDirty: Bool { speech.map { $0.notes != notes } ?? false }
    var foldersLocked: Bool { !canLeave || scriptsLoading || notesDirty || ProcessingWorkspace.shared.busy || CorrectionWorkspace.shared.busy || RecordingWorkspace.shared.capture.phase.busy }

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
        guard canLeave, !scriptsLoading, let store else { return }
        ProcessingWorkspace.shared.refresh()
        busy = true
        refreshGeneration += 1
        let generation = refreshGeneration
        Task {
            // 녹음 제목 입력창의 «인덱스 누락» 판정은 Speeches 스캔과 인덱스 읽기가 둘 다 성공한 새로고침에서만 한다 (QA B N-1).
            var speechesScanned = false
            do {
                try await persistNotes()
                if let url = folders[.speeches] {
                    do {
                        let scan = try await store.scanSpeeches(in: url)
                        speeches = scan.items; scanIssues[.speeches] = scan.issues; speechesScanned = true
                        if !speeches.contains(where: { $0.id == selectedSpeechID }) { setSpeech(speeches.first?.id) }
                    } catch { scanIssues[.speeches] = [FileScanIssue(url: url)] }
                }
            } catch { message = "입력 정보를 저장하지 못해 Speeches 갱신을 보류했습니다. 입력값과 기존 목록은 유지됩니다." }
            // Speeches are usable from here; Script-dependent actions wait for the listing below.
            busy = false
            // 녹음 표시 제목: Speeches 스캔이 새 항목을 인덱스에 더한 뒤 읽는다 (usage-bundle1).
            let titlesLoaded = await loadTitles()
            confirmTitlePrompts(refreshedAt: generation, verified: speechesScanned && titlesLoaded)
            guard let url = folders[.scripts] else { return }
            scriptsLoading = true
            do {
                let scan = try await store.scanScriptSummaries(in: url)
                scripts = scan.items; scanIssues[.scripts] = scan.issues
                if !scripts.contains(where: { $0.id == selectedScriptID }) { historicalFile = nil; selectedScriptID = primaryScripts.first?.id }
            } catch { scanIssues[.scripts] = [FileScanIssue(url: url)] }
            scriptsLoading = false
            openSelectedScript()
        }
    }
    /// Reads the selected Script unless the opened copy already matches its listing.
    private func openSelectedScript() {
        guard let id = selectedScriptID, let summary = scripts.first(where: { $0.id == id }), let store else {
            if selectedScriptID == nil { openedScript = nil }
            return
        }
        if let opened = openedScript, opened.id == id, opened.url == summary.url, opened.hash == summary.hash { return }
        loadingScriptID = id
        Task {
            defer { if loadingScriptID == id { loadingScriptID = nil } }
            do {
                let file = try await store.loadScript(summary)
                if selectedScriptID == id { openedScript = file }
            } catch {
                // The file changed after listing: a rescan lists current bytes or reports damage. Retry once per version.
                if selectedScriptID == id { openedScript = nil }
                let attempt = id + ":" + summary.hash
                guard failedOpen != attempt else { return }
                failedOpen = attempt
                loadingScriptID = nil
                refresh()
            }
        }
    }
    /// 인덱스에서 표시 제목·연결 id를 다시 읽는다. 실패하면 이전 값을 유지하고 false.
    @discardableResult private func loadTitles() async -> Bool {
        guard let store else { return false }
        guard let titles = try? await store.displayTitles(), let ids = try? await store.indexedSpeechIDs() else { return false }
        displayTitles = titles; indexedSpeechIDs = ids
        return true
    }
    /// 녹음 표시 제목을 인덱스에만 쓴다. 스크립트 파일·사본은 쓰지 않는다.
    func saveDisplayTitle(_ title: String, speechID: String) async throws {
        guard let store else { throw LibraryFailure.invalidInput }
        let saved = try await store.saveDisplayTitle(title, speechID: speechID)
        displayTitles[speechID] = saved.displayTitle
        indexedSpeechIDs.insert(speechID)
        for i in speeches.indices where speeches[i].id == speechID { speeches[i].displayTitle = saved.displayTitle }
    }
    private func updated(_ file: LibraryScriptFile) {
        if let i = scripts.firstIndex(where: { $0.id == file.id }) { scripts[i] = LibraryScriptSummary(file) }
        if openedScript?.id == file.id { openedScript = file }
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
    func completedScript(for speech: LibrarySpeech) -> LibraryScriptSummary? {
        ScriptResultPresentation.primaryFile(in: scripts.filter { $0.sessionId == speech.id })
    }
    func scriptGroupSelected(_ file: LibraryScriptSummary) -> Bool {
        guard let selected = scripts.first(where: { $0.id == selectedScriptID }) else { return false }
        return selected.sessionId == file.sessionId
    }

    func canRetranscribe(_ sessionID: String) -> Bool {
        canLeave && !scriptsLoading && notesValid && folders[.scripts] != nil && !RecordingWorkspace.shared.capture.phase.busy &&
        !CorrectionWorkspace.shared.busy && ProcessingWorkspace.shared.canRetranscribe(sessionID)
    }
    func retranscribeSpeech() {
        guard let speech else { return }
        retranscribe(sessionID: speech.id, input: notes)
    }
    func retranscribeScript(_ file: LibraryScriptSummary) {
        let sessionID = file.sessionId
        if selectedSpeechID == sessionID { retranscribe(sessionID: sessionID, input: notes); return }
        if let input = speeches.first(where: { $0.id == sessionID })?.notes { retranscribe(sessionID: sessionID, input: input); return }
        // Only the Script still holds this recording's input; read it before preparing the request.
        guard canRetranscribe(sessionID), let store else { return }
        Task {
            do { retranscribe(sessionID: sessionID, input: try await store.loadScript(file).script.input) }
            catch { refresh() }
        }
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
        guard confirmDeletion(title: speechTitle(speech), kind: "Speech", detail: "선택한 녹음 파일 또는 녹음 묶음을 휴지통으로 이동합니다. 연결된 Scripts와 내부 원음 사본은 남아 재생·재전사에 사용할 수 있습니다.") else { busy = false; return }
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
    func deleteScript(_ file: LibraryScriptSummary) {
        guard !foldersLocked, let store, let folder = folders[.scripts] else { return }
        busy = true; playback.stop()
        // usage-bundle2 문구 6 (ssot/tone/usage-bundle2.md).
        guard confirmDeletion(title: scriptTitle(file), kind: "Script", detail: "선택한 스크립트 파일을 휴지통으로 이동하고, 이 스크립트의 내부 수정 이력과 AI 버전 기록을 지웁니다. 파일을 휴지통에서 되돌려도 지운 AI 버전은 열 수 없습니다. 연결된 Speech·다른 Scripts·내보낸 Markdown과 원음·전사 원응답은 남습니다.") else { busy = false; return }
        let isChild = ProcessingWorkspace.shared.runs.contains { $0.id == file.id && $0.parentRunID != nil }
        Task {
            defer { busy = false }
            // 순서: 휴지통 → (자식이면) savedSourceRuns → 내부 수정 이력 → 교정 시도 기록 (library-script.md «결과 보관»).
            let removal = await store.removeScript(file, in: folder, isChildResult: isChild, registerSavedSource: Self.registerSavedSource)
            guard removal != .trashFailed else {
                message = "Script를 삭제하지 못했습니다. 파일 변경 여부와 폴더 권한을 확인한 뒤 새로고침해 주세요. 영구 삭제로 재시도하지 않습니다."
                return
            }
            scripts.removeAll { $0.url == file.url }
            if openedScript?.url == file.url { openedScript = nil }
            if selectedScriptID == file.id { selectedScriptID = primaryScripts.first?.id }
            message = removal == .removed ? "Script를 휴지통으로 이동했습니다. 원음과 다른 스크립트는 유지됩니다."
                : "Script를 휴지통으로 이동했습니다. 내부 수정 이력은 지우지 못했습니다. 설정의 저장 공간 정리에서 다시 지울 수 있습니다."
        }
    }
    /// usage-bundle2 저장 공간 정리 시작 조건: 변환·AI 교정·녹음 마무리·편집 중이 아니고 Scripts 목록을 다 읽었다. 녹음 중 자체는 막지 않는다.
    var storageCleanupAllowed: Bool {
        let capture = RecordingWorkspace.shared.capture
        return canLeave && !scriptsLoading && store != nil && folders[.scripts] != nil && !storageCleanupActive
            && !ProcessingWorkspace.shared.busy && !CorrectionWorkspace.shared.busy
            && capture.phase != .finalizing && !capture.needsFinalization
    }
    func refreshRevisionBytes() {
        guard let store else { return }
        Task { revisionBytes = await store.revisionStorageBytes() }
    }
    /// 설정 «저장 공간 정리…»: 확인(쓰기 없음) → 확인창(기본 «취소») → 보관 정리 → 이력 정리. 진행 중에는 편집·저장·변환·AI 교정 시작을 막는다.
    func cleanStorage() {
        guard storageCleanupAllowed, let store, let folder = folders[.scripts] else { return }
        busy = true; storageCleanupActive = true; storageCleanup = .checking; playback.stop()
        Task {
            let outcome = await runStorageCleanup(store: store, folder: folder)
            storageCleanup = outcome
            busy = false; storageCleanupActive = false
            revisionBytes = await store.revisionStorageBytes()
        }
    }
    private func runStorageCleanup(store: FolderLibraryStore, folder: URL) async -> StorageCleanupPhase {
        let plan: RevisionCleanupPlan, removals: [LibraryScriptSummary], counts: StorageCleanupNotice.Counts
        do {
            // 확인 단계(쓰기 없음, 요약 캐시 포함). Scripts 목록을 다시 읽는다.
            let checked = try await store.planStorageCleanup(scriptsFolder: folder)
            let scan = checked.scan
            scripts = scan.items; scanIssues[.scripts] = scan.issues
            let issues = !scan.issues.isEmpty
            let inputs = ProcessingWorkspace.shared.retentionInputs()
            let plans = inputs.available && !issues
                ? ScriptRetention.plan(scripts, links: inputs.links, skipIDs: retentionSkipIDs, skippedSessions: inputs.skippedSessions) : [:]
            let ids = ScriptRetention.removals(plans)
            removals = scripts.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
            plan = checked.plan
            let scriptBytes = removals.reduce(Int64(0)) { $0 + Int64((try? $1.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            counts = StorageCleanupNotice.Counts(scripts: removals.count, scriptBytes: scriptBytes,
                deletions: plan.deletions.count, deletionBytes: plan.deletionBytes, skippedOrphans: plan.skippedOrphans,
                migrations: plan.migrations.count, migrationBytes: plan.migrationBytes, attempts: plan.attempts.count)
        } catch { return .failed }
        guard counts.total > 0 else { return .nothing }
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = StorageCleanupNotice.confirmTitle
        alert.informativeText = StorageCleanupNotice.confirmLines(counts).joined(separator: "\n\n")
        alert.addButton(withTitle: StorageCleanupNotice.cancel); alert.addButton(withTitle: StorageCleanupNotice.confirm)
        guard alert.runModal() == .alertSecondButtonReturn else { return .idle }
        let before = await store.revisionStorageBytes(), total = counts.total
        storageCleanup = .running(done: 0, total: total)
        // 1. 보관 정리(결과 하나를 지우는 순서 그대로, 건별 기록).
        let links = ProcessingWorkspace.shared.retentionInputs().links
        var removed: Set<String> = [], failed = 0, done = 0
        for summary in removals {
            let removal = await store.removeScript(summary, in: folder, isChildResult: links[summary.id]?.parentRunID != nil, log: true,
                                                   registerSavedSource: Self.registerSavedSource)
            // 휴지통 이동은 됐지만 내부 이력·시도 기록을 못 지운 경우도 «처리하지 못한 파일»로 센다(문구 21).
            if removal == .trashFailed || removal == .historyNotRemoved { failed += 1 }
            if removal != .trashFailed { removed.insert(summary.id); scripts.removeAll { $0.id == summary.id } }
            done += 1; storageCleanup = .running(done: done, total: total)
        }
        if let opened = openedScript, removed.contains(opened.id) { openedScript = nil }
        if let selected = selectedScriptID, removed.contains(selected) { selectedScriptID = primaryScripts.first?.id }
        // 2–4. 지울 이력 → 압축 이전 → 지울 시도 기록.
        let offset = done
        let result = await store.runRevisionCleanup(plan, removedScriptIDs: removed) { n in
            Task { @MainActor in
                let workspace = LibraryWorkspace.shared
                if case .running = workspace.storageCleanup { workspace.storageCleanup = .running(done: offset + n, total: total) }
            }
        }
        let after = await store.revisionStorageBytes()
        return .finished(StorageCleanupNotice.finished(before: before, after: after, scripts: removed.count, failed: failed + result.failed))
    }
    /// usage-bundle2 결과 보관 정리. `sessions` = nil이면 모든 녹음. Scripts 목록을 읽는 중이거나 조회 문제가 있거나
    /// 처리 이력을 읽지 못했으면 아무것도 하지 않는다. 반환 = 옮긴 수 · 옮기지 못한 수 · 옮긴 id.
    func applyRetention(sessions: Set<String>?, in folder: URL,
                        progress: (() -> Void)? = nil) async -> (moved: Int, failed: Int, removed: Set<String>) {
        guard let store, !scriptsLoading, (scanIssues[.scripts] ?? []).isEmpty else { return (0, 0, []) }
        let inputs = ProcessingWorkspace.shared.retentionInputs()
        guard inputs.available else { return (0, 0, []) }
        let candidates = sessions.map { wanted in scripts.filter { wanted.contains($0.sessionId) } } ?? scripts
        let plans = ScriptRetention.plan(candidates, links: inputs.links, skipIDs: retentionSkipIDs, skippedSessions: inputs.skippedSessions)
        var moved = 0, failed = 0, removed: Set<String> = []
        for id in ScriptRetention.removals(plans).sorted() {
            guard let summary = scripts.first(where: { $0.id == id }) else { continue }
            let removal = await store.removeScript(summary, in: folder, isChildResult: inputs.links[id]?.parentRunID != nil,
                                                   registerSavedSource: Self.registerSavedSource)
            if removal == .trashFailed { failed += 1 } else { moved += 1; removed.insert(id); scripts.removeAll { $0.id == id } }
            progress?()
        }
        return (moved, failed, removed)
    }
    /// 결과 보관에서 건너뛸 결과: 열려 있는 본문·과거 버전, 저장 중, AI 교정 실행·대기.
    private var retentionSkipIDs: Set<String> {
        var ids = savingRunIDs.union(CorrectionWorkspace.shared.pendingScriptIDs)
        if let id = openedScript?.id { ids.insert(id) }
        if let id = historicalFile?.id { ids.insert(id) }
        return ids
    }
    /// 재전사 확인창의 정리 수 N(상한): 이 실행과 재사용할 Soniox 결과를 새 세대로 놓은 정리 수. 건너뜀 조건은 넣지 않는다.
    func pendingRetentionCount(sessionID: String, reusing sonioxRunID: String?) -> Int {
        let pendingID = "pending-run"
        let pending = ScriptRetention.PendingGeneration(sessionId: sessionID, representativeID: pendingID, createdAt: Date(),
                                                        memberIDs: Set([pendingID] + [sonioxRunID].compactMap { $0 }))
        let plans = ScriptRetention.plan(scripts.filter { $0.sessionId == sessionID }, links: ProcessingWorkspace.shared.retentionInputs().links,
                                         pending: pending)
        return plans[sessionID]?.remove.count ?? 0
    }
    /// 지운 Soniox 자식 결과가 다음 처리 때 다시 저장되지 않게 한다(operating-baseline.md:36, saveCompletedSources).
    nonisolated static func registerSavedSource(_ runID: String) {
        var saved = Set(UserDefaults.standard.stringArray(forKey: "library.savedSourceRuns") ?? [])
        saved.insert(runID); UserDefaults.standard.set(Array(saved), forKey: "library.savedSourceRuns")
    }
    private func confirmDeletion(title: String, kind: String, detail: String) -> Bool {
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "\(kind)를 삭제할까요?"
        alert.informativeText = "\(title)\n\n\(detail)\n\n휴지통에서 되돌릴 수 있습니다. 서버에 전송된 데이터는 삭제하지 않습니다."
        alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "휴지통으로 이동")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func convert() {
        // An incomplete Script listing could make an existing result look missing.
        guard canLeave, !scriptsLoading, notesValid, let speech, let root, folders[.scripts] != nil else { return }
        let processing = ProcessingWorkspace.shared
        if let run = processing.run(for: speech.id) {
            if run.stage == "readyForReview" {
                if let existing = scripts.first(where: { $0.id == run.id }) { selectScript(existing.id) }
                else { processingFinished(run) }
                return
            }
            // pyannote is retired: a stalled P2 run is replaced by a new local run, never resumed.
            if processing.isRetired(run), canRetranscribe(speech.id) { retranscribeSpeech(); return }
            if processing.canResume(run) { processing.resume(run) }
            else if run.canRetranscribe {
                // Terminal failures are never resumed; a new run reuses completed provider results when eligible.
                if canRetranscribe(speech.id) { retranscribeSpeech() }
                else { message = processing.label(run) + " 다른 작업이 끝난 뒤 다시 전사할 수 있습니다." }
            }
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
    /// `retain` = launch 경로의 완료(usage-bundle2 결과 보관 정리 시점). 재저장(convert)·자식 저장은 false.
    func processingFinished(_ run: ManagedRun, select: Bool = true, retain: Bool = false) {
        guard ![.precision, .nemotron].contains(run.provider) else { return }
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
                let (result, created) = try await store.createScriptReportingNew(document, speech: speech, input: run.input ?? speech.notes, in: destination)
                let scan = try await store.scanScriptSummaries(in: destination)
                scripts = scan.items; scanIssues[.scripts] = scan.issues
                if !select { Self.registerSavedSource(run.id) }
                savingRunIDs.remove(run.id)
                if select && canLeave && !notesDirty { historicalFile = nil; openedScript = result; selectedScriptID = result.id; folder = .scripts }
                // usage-bundle2 결과 보관: 자식이 아닌 실행이 새 스크립트를 만든 직후, 그 녹음 하나만.
                var retentionNotice = ""
                if retain && created && run.parentRunID == nil {
                    let outcome = await applyRetention(sessions: [run.sessionID], in: destination)
                    retentionNotice = RetentionNotice.completionSuffix(moved: outcome.moved, failed: outcome.failed)
                }
                message = "스크립트를 저장했습니다. 화자와 내용을 확인해 주세요." + retentionNotice
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
        updated(result)
    }
    func saveTitle(_ title: String, original: LibraryScriptFile) async throws -> LibraryScriptFile {
        guard !busy, historicalFile == nil, let store else { throw LibraryFailure.invalidInput }
        busy = true; defer { busy = false }
        let result = try await store.saveTitle(title, for: original)
        updated(result)
        return result
    }
    func saveParagraph(_ block: ScriptBlock, text: String, original: LibraryScriptFile) async throws -> LibraryScriptFile {
        guard !busy, historicalFile == nil, let store else { throw LibraryFailure.invalidInput }
        busy = true; defer { busy = false }
        let result = try await store.saveParagraph(block, text: text, for: original)
        updated(result)
        return result
    }
    func storeCorrection(_ correction: ScriptCorrection, file: LibraryScriptFile) async throws {
        guard let store else { throw LibraryFailure.invalidInput }
        // Re-read and merge only the AI layer. Concurrent manual edits remain authoritative.
        let result = try await store.saveCorrection(correction, for: file)
        updated(result)
    }
    func applyPendingCorrection(_ file: LibraryScriptFile) async throws {
        guard historicalFile == nil, canLeave, !CorrectionWorkspace.shared.busy, let store else { throw LibraryFailure.invalidInput }
        busy = true; defer { busy = false }
        let result = try await store.applyPendingCorrection(for: file)
        updated(result)
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
        // 현재 결과는 해석한 녹음 제목, AI 버전 보기는 당시 제목 (usage-bundle1).
        let title = scriptTitle(file.script)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".md"
        panel.title = "Markdown 내보내기"
        panel.message = "녹음 정보·변환 전 입력·화자·대화·타임스탬프를 저장합니다."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true
        Task {
            defer { busy = false }
            let accessed = destination.startAccessingSecurityScopedResource()
            defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
            do { try await store.exportMarkdown(file, title: title, to: destination); message = "Markdown 파일을 저장했습니다." }
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
        // 제목 입력창은 원본 저장이 끝난 뒤 줄 선다. 끝난 순서를 지키려고 Speeches 저장 전에 순번을 받는다.
        titlePrompts.finished(record.id); promptRecords[record.id] = record
        Task {
            do {
                try await store.publishRecording(record, to: destination)
                publishedPrompts[record.id] = refreshGeneration
                requestPromptRefresh()
            } catch {
                titlePrompts.drop(record.id); promptRecords[record.id] = nil
                message = "Speeches에 저장하지 못했습니다. 내부 원본은 보존되어 있습니다."
            }
        }
    }
    /// 새로고침은 편집·저장·목록 읽기 중에는 미뤄진다(`refresh` 가드). 입력창의 인덱스 확인이 빠지지 않게
    /// 가능해질 때 한 번 새로고침한다 (QA B D-3).
    private func requestPromptRefresh() {
        guard promptRefresh == nil else { return }
        promptRefresh = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.canLeave && !self.scriptsLoading { self.refresh(); break }
                try? await Task.sleep(for: .seconds(1))
            }
            self?.promptRefresh = nil
        }
    }
    /// 인덱스에서 확인된 녹음을 표시 가능으로 바꾼다. Speeches 저장 뒤 시작한 새로고침이 스캔·인덱스 읽기에
    /// 성공(`verified`)했는데도 인덱스에 없으면 건너뛴다. 실패한 새로고침은 줄을 그대로 둔다(다음 새로고침에서 확인).
    private func confirmTitlePrompts(refreshedAt generation: Int, verified: Bool) {
        titlePrompts.confirmed(indexedSpeechIDs)
        for id in titlePrompts.awaiting {
            guard let published = publishedPrompts[id] else { continue }
            if indexedSpeechIDs.contains(id) { publishedPrompts[id] = nil }
            else if verified && published < generation { titlePrompts.drop(id); publishedPrompts[id] = nil; promptRecords[id] = nil }
        }
        for id in publishedPrompts.keys where indexedSpeechIDs.contains(id) { publishedPrompts[id] = nil }
    }
    /// 보이는 제목 입력창을 닫는다(저장 성공·나중에·Esc·창 닫기). 쓰기는 하지 않는다. 지금 보이는 `id`일 때만.
    func dismissTitlePrompt(_ id: String) {
        guard titlePrompts.current == id else { return }
        promptRecords[id] = nil
        titlePrompts.dismiss(id)
    }
    /// 앱 종료: 열린 입력창과 줄 선 것을 저장 없이 버린다.
    func discardTitlePrompts() {
        promptRefresh?.cancel(); promptRefresh = nil
        titlePrompts.terminate(); promptRecords = [:]; publishedPrompts = [:]
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
