import AppKit
import DamaCore
import DamaAudio
import DamaManaged
import SwiftUI

@MainActor final class CorrectionWorkspace: ObservableObject {
    static let shared = CorrectionWorkspace()
    @Published private(set) var activeID: String?
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var referenceURL: URL?
    @Published private(set) var preview: [ReferenceExcerpt] = []
    /// 안내 띠. 새 교정 안내가 생기면 남아 있던 작업 공간 안내를 지워 가려지지 않게 한다(띠는 `workspace.message`를 먼저 보인다, usage-bundle1 게이트 ② AC-14).
    @Published var message: String? { didSet { if message != nil { LibraryWorkspace.shared.message = nil } } }
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "correction.automatic") } }
    @Published private(set) var executable: URL
    /// 시도 기록이 바뀔 때 올린다. 화면은 이 값이 바뀌면 «이어서 교정» 상태를 다시 읽는다.
    @Published private(set) var attemptVersion = 0
    /// 새 교정(확인한 입력) 또는 이어서 교정(기록된 입력).
    private enum Job: Sendable { case fresh(ConversionNotes), resume }
    private var queue: [(LibraryScriptFile, Job)] = []
    private var task: Task<Void, Never>?
    private var accessed: [URL] = []
    var busy: Bool { activeID != nil || !queue.isEmpty }
    /// usage-bundle2 결과 보관에서 건너뛸 결과: 실행 중이거나 대기열에 있는 교정의 스크립트.
    var pendingScriptIDs: Set<String> { Set([activeID].compactMap { $0 } + queue.map { $0.0.id }) }
    private init() {
        automatic = UserDefaults.standard.object(forKey: "correction.automatic") as? Bool ?? true
        let home = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
        let candidates = [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        executable = URL(fileURLWithPath: candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0])
        for key in ["correction.executable", "correction.references"] {
            guard let data = UserDefaults.standard.data(forKey: key) else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if url.startAccessingSecurityScopedResource() { accessed.append(url) }
                if key == "correction.executable" { executable = url } else { referenceURL = url }
            } else { message = "교정용 파일 접근을 다시 선택해 주세요." }
        }
    }
    func chooseReferences() { choose(directory: true) }
    func chooseExecutable() { choose(directory: false) }
    private func choose(directory: Bool) {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        panel.message = directory ? "이 폴더의 Markdown·텍스트에서 관련 내용을 찾아 교정에 참고합니다. 전송 전에 발췌를 보여줍니다." : "설치된 codex 실행 파일을 선택해 주세요."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            if !directory && !FileManager.default.isExecutableFile(atPath: url.path) { throw LibraryFailure.invalidInput }
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: directory ? "correction.references" : "correction.executable")
            if scoped { accessed.append(url) }
            if directory { referenceURL = url; preview = [] } else { executable = url }
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            message = "파일 접근 정보를 저장하지 못했습니다."
        }
    }
    func disconnectReferences() {
        guard !busy else { return }; referenceURL = nil; preview = []
        UserDefaults.standard.removeObject(forKey: "correction.references")
    }
    func preparedInput(_ input: ConversionNotes, enabled: Bool, includeSonioxFolder: Bool = false, includeQwenFolder: Bool = false) async throws -> ConversionNotes {
        var result = input; result.aiCorrection = enabled; result.referenceExcerpts = nil
        if enabled || (input.provider.usesSoniox && input.sonioxContext == true && includeSonioxFolder) || (input.provider == .qwen && includeQwenFolder), let referenceURL {
            let excerpts = try await ReferenceFolder().excerpts(in: referenceURL, query: [input.participants ?? "", input.context, input.reference, input.meetingTerms ?? ""].joined(separator: "\n"))
            result.referenceExcerpts = excerpts; preview = excerpts
        }
        return result
    }
    static func addPreview(to alert: NSAlert, input: ConversionNotes) {
        guard input.aiCorrection == true || input.provider == .qwen || (input.provider.usesSoniox && input.sonioxContext == true) else { return }
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 170))
        view.isEditable = false; view.isSelectable = true; view.font = .systemFont(ofSize: 11)
        view.string = "참석자\n\(input.participants ?? "미입력")\n\n맥락\n\(input.context)\n\n참고 정보\n\(input.reference)\n\n" +
            (input.referenceExcerpts ?? []).map { "[\($0.name)]\n\($0.text)" }.joined(separator: "\n\n")
        if let bytes = try? SonioxRequest.context(input) {
            let context = String(decoding: bytes, as: UTF8.self)
            let included = (input.sonioxReferenceExcerpts ?? input.referenceExcerpts ?? []).map(\.name).joined(separator: ", ")
            let omitted = (input.sonioxOmittedReferences ?? []).joined(separator: ", ")
            view.string = "Soniox 전사 문맥 (전체 전송값 · \(bytes.count)/7,500바이트)\n\(context)\n\n" +
                "포함한 폴더 발췌: \(included.isEmpty ? "없음" : included)\n제외한 발췌 (선택/용량): \(omitted.isEmpty ? "없음" : omitted)\n\n" +
                (input.aiCorrection == true ? "OpenAI 교정 입력\n" + view.string : "")
        }
        if input.provider == .qwen { view.string="Qwen 로컬 입력 (외부 전송 없음)\n"+input.qwenLocalContext }
        let scroll = NSScrollView(frame: view.frame); scroll.hasVerticalScroller = true; scroll.documentView = view
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        alert.accessoryView = scroll
    }
    func enqueue(_ file: LibraryScriptFile, input: ConversionNotes) {
        guard AudioFiles.uiFixtureFolder == nil else {
            message = "합성 UI 검증에서는 AI 실행과 외부 전송을 차단합니다."; return
        }
        guard !LibraryWorkspace.shared.storageCleanupActive else { return }   // usage-bundle2: 저장 공간 정리 중 시작 막음
        guard input.aiCorrection == true, activeID != file.id, !queue.contains(where: { $0.0.id == file.id }) else { return }
        queue.append((file, .fresh(input))); runNext()
    }
    /// usage-bundle1 이어서 교정: 확인창을 거친 뒤에만 부른다. 기록된 입력으로 남은 청크만 보낸다. 자동 재시도는 없다.
    func resume(_ file: LibraryScriptFile) {
        guard AudioFiles.uiFixtureFolder == nil else {
            message = "합성 UI 검증에서는 AI 실행과 외부 전송을 차단합니다."; return
        }
        guard !busy, !LibraryWorkspace.shared.storageCleanupActive else { return }
        queue.append((file, .resume)); runNext()
    }
    private func makeRunner() throws -> CorrectionRunner {
        CorrectionRunner(store: CorrectionAttemptStore(root: try AudioFiles.root()), executable: executable)
    }
    /// «이어서 교정» 상태(청크 계획 해시를 다시 만들므로 메인 밖에서 계산한다).
    func attemptStatus(for script: LibraryScript) async -> CorrectionRunner.Resume {
        guard let runner = try? makeRunner() else { return .none }
        return await Task.detached(priority: .utility) { runner.resumeState(for: script) }.value
    }
    private func setCompleted(_ value: Int) { completed = value }
    func cancel() { queue = []; task?.cancel() }
    private func runNext() {
        guard task == nil, !queue.isEmpty else { return }
        let (file, job) = queue.removeFirst()
        activeID = file.id; completed = 0; total = 0; message = nil
        task = Task {
            var correction = ScriptCorrection(input: file.script.input, engine: CorrectionRunner.engine)
            let hasPreviousResult = file.script.correction?.state == .completed
            defer { activeID = nil; task = nil; attemptVersion += 1; runNext() }
            do {
                let runner = try makeRunner(), script = file.script
                // 새 교정은 기존 시도 기록을 버리고 새로 만든다. 이어서 교정은 계획·엔진이 같을 때만 기록을 그대로 쓴다.
                let (attempt, chunks) = try await Task.detached(priority: .utility) {
                    switch job {
                    case .fresh(let input): return try runner.begin(script: script, input: input)
                    case .resume: return try runner.prepareResume(script: script)
                    }
                }.value
                attemptVersion += 1
                correction = ScriptCorrection(input: attempt.input, engine: attempt.engine)
                total = attempt.totalChunks; completed = attempt.completedChunks
                correction.totalChunks = total; correction.completedChunks = completed
                if !hasPreviousResult { try await LibraryWorkspace.shared.storeCorrection(correction, file: file) }
                let outcome = await runner.run(attempt, chunks: chunks) { [weak self] done in await self?.setCompleted(done) }
                switch outcome {
                case .completed(let finished):
                    let merged = finished.merged()
                    correction.edits = merged.edits; correction.speakerNames = merged.names; correction.nameEvidence = merged.evidence
                    correction.rejectedTurns = merged.rejected.isEmpty ? nil : merged.rejected
                    correction.completedChunks = finished.totalChunks
                    correction.state = .completed; correction.completedAt = Date()
                    try await LibraryWorkspace.shared.storeCorrection(correction, file: file)
                    // 성공 저장 직후 시도 기록을 지운다.
                    try? runner.discard(scriptID: file.id)
                    message = CorrectionRejectionText.completionMessage(rejectedCount: merged.rejected.count)
                case .failed(let failed, let error):
                    correction.state = .failed; correction.edits = []; correction.speakerNames = [:]; correction.nameEvidence = [:]
                    correction.rejectedTurns = nil
                    correction.completedChunks = failed.completedChunks
                    if !hasPreviousResult { try? await LibraryWorkspace.shared.storeCorrection(correction, file: file) }
                    // 분류별 안내 띠 (tone 문구 18). 원문·stderr 내용은 쓰지 않는다.
                    message = error.kind.bannerMessage(exitCode: error.exitCode, hasCompletedChunks: failed.completedChunks > 0)
                }
            } catch {
                // 청크 계획·시도 기록·저장 단계 실패(프로세스 실행 전). 원문을 쓰지 않는다.
                correction.state = .failed; correction.edits = []; correction.speakerNames = [:]; correction.nameEvidence = [:]
                correction.rejectedTurns = nil
                if !hasPreviousResult { try? await LibraryWorkspace.shared.storeCorrection(correction, file: file) }
                message = "AI 보정을 완료하지 못했습니다. 기존 결과는 유지됩니다."
            }
        }
    }
}
