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
    @Published var message: String?
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "correction.automatic") } }
    @Published private(set) var executable: URL
    private var queue: [(LibraryScriptFile, ConversionNotes)] = []
    private var task: Task<Void, Never>?
    private var accessed: [URL] = []
    var busy: Bool { activeID != nil || !queue.isEmpty }
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
            if !directory && !FileManager.default.isExecutableFile(atPath: url.path) { throw CodexCorrectionFailure.unavailable }
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
    func preparedInput(_ input: ConversionNotes, enabled: Bool) async throws -> ConversionNotes {
        var result = input; result.aiCorrection = enabled; result.referenceExcerpts = nil
        if enabled || (input.provider == .soniox && input.sonioxContext == true), let referenceURL {
            let excerpts = try await ReferenceFolder().excerpts(in: referenceURL, query: [input.participants ?? "", input.context, input.reference].joined(separator: "\n"))
            result.referenceExcerpts = excerpts; preview = excerpts
        }
        return result
    }
    static func addPreview(to alert: NSAlert, input: ConversionNotes) {
        guard input.aiCorrection == true || (input.provider == .soniox && input.sonioxContext == true) else { return }
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 170))
        view.isEditable = false; view.isSelectable = true; view.font = .systemFont(ofSize: 11)
        view.string = "참석자\n\(input.participants ?? "미입력")\n\n맥락\n\(input.context)\n\n참고 정보\n\(input.reference)\n\n" +
            (input.referenceExcerpts ?? []).map { "[\($0.name)]\n\($0.text)" }.joined(separator: "\n\n")
        if let bytes = try? SonioxRequest.context(input) {
            let context = String(decoding: bytes, as: UTF8.self)
            view.string = "Soniox 전사 문맥 (전체 전송값)\n\(context)\n\n" + (input.aiCorrection == true ? "OpenAI 교정 입력\n" + view.string : "")
        }
        let scroll = NSScrollView(frame: view.frame); scroll.hasVerticalScroller = true; scroll.documentView = view
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        alert.accessoryView = scroll
    }
    func review(_ file: LibraryScriptFile) {
        guard !busy, LibraryWorkspace.shared.canLeave else { return }
        Task {
            do {
                let library = LibraryWorkspace.shared
                let input = try await preparedInput(library.speeches.first { $0.id == file.script.transcript.sessionId }?.notes ?? file.script.input, enabled: true)
                let alert = NSAlert(); alert.messageText = "문맥을 반영해 AI 교정할까요?"
                alert.informativeText = "이 스크립트의 전사·참석자·맥락·아래 참고 발췌를 Codex CLI를 통해 OpenAI로 전송합니다. Codex 계정 사용량이 소모될 수 있습니다. 원음은 보내지 않으며 원문과 사용자 수정은 보존합니다."
                Self.addPreview(to: alert, input: input)
                alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "AI 교정")
                guard alert.runModal() == .alertSecondButtonReturn else { return }
                enqueue(file, input: input)
            } catch { message = "참고 폴더를 읽지 못했습니다. 다시 선택하거나 연결을 해제해 주세요. 전송하지 않았습니다." }
        }
    }
    func enqueue(_ file: LibraryScriptFile, input: ConversionNotes) {
        guard input.aiCorrection == true, activeID != file.id, !queue.contains(where: { $0.0.id == file.id }) else { return }
        queue.append((file, input)); runNext()
    }
    func cancel() { queue = []; task?.cancel() }
    private func runNext() {
        guard task == nil, !queue.isEmpty else { return }
        let (file, input) = queue.removeFirst()
        activeID = file.id; completed = 0; total = 0; message = nil
        let executable = self.executable
        task = Task {
            var correction = ScriptCorrection(input: input, engine: "Codex CLI (기본 모델) · " + ContextCorrection.version)
            let hasPreviousResult = file.script.correction?.state == .completed
            defer { activeID = nil; task = nil; runNext() }
            do {
                let chunks = try await Task.detached(priority: .utility) {
                    var source = file.script; source.correction = nil; source.showsOriginal = nil
                    return try ContextCorrection.chunks(source)
                }.value
                total = chunks.count; correction.totalChunks = total
                if !hasPreviousResult { try await LibraryWorkspace.shared.storeCorrection(correction, file: file) }
                var conflicts = Set<String>()
                let client = CodexCorrectionClient()
                for chunk in chunks {
                    try Task.checkCancellation()
                    let response = try await client.correct(chunk: chunk, input: input, executable: executable)
                    let validated = try ContextCorrection.validated(response, chunk: chunk, input: input)
                    correction.edits += validated.edits
                    for (id, name) in validated.names {
                        if let previous = correction.speakerNames[id], previous != name { conflicts.insert(id) }
                        correction.speakerNames[id] = name
                        correction.nameEvidence[id] = validated.evidence[id]
                    }
                    completed += 1; correction.completedChunks = completed
                }
                try Task.checkCancellation()
                for id in conflicts { correction.speakerNames.removeValue(forKey: id); correction.nameEvidence.removeValue(forKey: id) }
                correction.state = .completed; correction.completedAt = Date()
                try await LibraryWorkspace.shared.storeCorrection(correction, file: file)
                message = "문맥 교정을 저장했습니다. 불확실한 부분은 원문과 노란 표시로 남겼습니다."
            } catch {
                correction.state = .failed; correction.edits = []; correction.speakerNames = [:]; correction.nameEvidence = [:]
                if !hasPreviousResult { try? await LibraryWorkspace.shared.storeCorrection(correction, file: file) }
                message = Task.isCancelled ? "교정을 중단했습니다. 원문과 사용자 수정은 유지됩니다." :
                    "AI 교정을 완료하지 못했습니다. 원문은 사용할 수 있습니다. Codex 설치·로그인·앱 접근 권한 또는 연결을 확인한 뒤 AI 교정을 다시 실행하세요. 자동 재호출하지 않습니다."
            }
        }
    }
}
