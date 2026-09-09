import AppKit
import DamaCore
import SwiftUI
import UniformTypeIdentifiers

/// One editor per app, shared by the review window and menu bar.
@MainActor
final class ReviewWorkspace: ObservableObject {
    static let shared = ReviewWorkspace()
    @Published private(set) var sessions: [SessionListing] = []
    @Published private(set) var state: TranscriptEditingState?
    @Published private(set) var model: TranscriptDocument?
    @Published private(set) var isWorking = false
    @Published private(set) var didLoad = false
    @Published var message: String?
    @Published private(set) var recoveryMessage: String?
    @Published var version: TranscriptExportVersion = .current {
        didSet { clearSelection() }
    }
    @Published var search = "" {
        didSet { if search != oldValue { clearSelection() } }
    }
    @Published var selectedWordIDs: Set<String> = []
    @Published var selectedTurnID: String?
    @Published var selectedIssueID: String?
    @Published var isPresentingEditor = false
    private var anchorWordID: String?
    private var repository: FileSessionRepository?
    private var editor: TranscriptEditingSession?
    private var activity = "불러오는 중"

    var document: TranscriptDocument? { version == .automatic ? model : state?.draft }
    var canEdit: Bool {
        version == .current && state != nil && !isWorking && state?.isDirty == false
            && !isPresentingEditor
    }
    var canLeave: Bool { !isWorking && state?.isDirty != true && !isPresentingEditor }
    var canExport: Bool { !isWorking && !isPresentingEditor && state?.canExport == true }
    var saveLabel: String {
        if isWorking { return activity }
        if isPresentingEditor { return "수정 중" }
        if state?.failure != nil || state?.isDirty == true { return "저장하지 못했습니다" }
        return state == nil ? "" : "저장됨"
    }
    var selectedWords: [TranscriptWord] {
        document?.words.filter { selectedWordIDs.contains($0.id) }.sorted { $0.ordinal < $1.ordinal } ?? []
    }
    var selectedIssue: ReviewIssue? { document?.reviewIssues.first { $0.id == selectedIssueID } }
    var selectedTurn: TranscriptTurn? { document?.turns.first { $0.id == selectedTurnID } }
    var openIssues: [ReviewIssue] {
        document.map { TranscriptIssueOrdering.openIssues(in: $0) } ?? []
    }
    var isLastIssue: Bool { selectedIssueID != nil && openIssues.last?.id == selectedIssueID }

    func start() {
        guard !didLoad, !isWorking else { return }
        activity = "불러오는 중"
        isWorking = true
        Task {
            defer { isWorking = false; didLoad = true }
            do {
                let repository = try FileSessionRepository.applicationSupport()
                self.repository = repository
                sessions = try await repository.listSessions()
                if let first = sessions.first { try await load(first.sessionId, repository: repository) }
            } catch { message = "저장된 세션을 열지 못했습니다. 저장 공간과 접근 권한을 확인해 주세요." }
        }
    }

    func refresh() {
        guard canLeave else { return }
        didLoad = false
        start()
    }

    func open(_ sessionID: String) {
        guard canLeave, let repository else { return }
        activity = "불러오는 중"
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await load(sessionID, repository: repository) }
            catch { message = "선택한 세션을 열지 못했습니다. 현재 세션은 유지됩니다." }
        }
    }

    private func load(_ sessionID: String, repository: FileSessionRepository) async throws {
        let next = try await TranscriptEditingSession.open(repository: repository, sessionId: sessionID)
        let nextState = await next.state()
        let nextModel = try await repository.loadModel(
            sessionId: sessionID, runId: nextState.committed.runId
        )
        editor = next
        state = nextState
        model = nextModel
        version = .current
        search = ""
        message = nil
        let notices = await repository.recoveryNotices()
        recoveryMessage = notices.contains { $0.sessionId == sessionID }
            ? "저장 위치 정보가 손상되어 마지막 유효한 수정본을 복구했습니다." : nil
    }

    #if DEBUG
    func importFixture() {
        guard canLeave, let repository else { return }
        activity = "불러오는 중"
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                guard let url = Bundle.main.url(forResource: "normalized-transcript", withExtension: "json") else {
                    message = "합성 테스트 데이터를 찾을 수 없습니다."
                    return
                }
                let result = try await repository.importSyntheticTranscript(Data(contentsOf: url))
                sessions = try await repository.listSessions()
                try await load(result.sessionId, repository: repository)
            } catch { message = "합성 테스트 데이터를 열지 못했습니다. 원본과 저장 공간을 확인해 주세요." }
        }
    }
    #endif

    func clearSelection() {
        selectedWordIDs = []
        selectedTurnID = nil
        selectedIssueID = nil
        anchorWordID = nil
    }

    func selectWord(_ word: TranscriptWord, turnID: String, extending: Bool) {
        if extending, let anchor = document?.words.first(where: { $0.id == anchorWordID }) {
            let bounds = min(anchor.ordinal, word.ordinal)...max(anchor.ordinal, word.ordinal)
            selectedWordIDs = Set(document?.words.filter { bounds.contains($0.ordinal) }.map(\.id) ?? [])
        } else {
            selectedWordIDs = [word.id]
            anchorWordID = word.id
        }
        selectedTurnID = turnID
        selectedIssueID = word.reviewIssueIds.first
    }

    func selectIssue(_ issue: ReviewIssue) {
        search = ""
        selectedIssueID = issue.id
        selectedWordIDs = Set(issue.wordIds)
        anchorWordID = issue.wordIds.first
        selectedTurnID = document?.turns.first {
            $0.reviewIssueIds.contains(issue.id) || !$0.wordIds.filter { selectedWordIDs.contains($0) }.isEmpty
        }?.id
    }

    func nextIssue() {
        guard !openIssues.isEmpty else { return }
        if let index = openIssues.firstIndex(where: { $0.id == selectedIssueID }), index + 1 < openIssues.count {
            selectIssue(openIssues[index + 1])
        } else if let first = openIssues.first { selectIssue(first) }
    }

    func selectMarker(_ turn: TranscriptTurn) {
        clearSelection()
        selectedTurnID = turn.id
        selectedIssueID = turn.reviewIssueIds.first
    }

    func apply(_ operation: TranscriptEditOperation) {
        guard canEdit else { return }
        transition { try await $0.apply(operation) }
    }
    func undo() {
        guard canEdit, state?.canUndo == true else { return }
        transition { try await $0.undo() }
    }
    func redo() {
        guard canEdit, state?.canRedo == true else { return }
        transition { try await $0.redo() }
    }
    func retry() {
        guard !isWorking, state?.isDirty == true else { return }
        transition { try await $0.retry() }
    }
    func cancelFailedSave() {
        guard !isWorking, state?.isDirty == true else { return }
        transition { try await $0.cancelFailedSave() }
    }

    private func transition(_ action: @escaping @Sendable (TranscriptEditingSession) async throws -> Void) {
        guard let editor else { return }
        activity = "저장 중"
        isWorking = true
        message = nil
        Task {
            do { try await action(editor) }
            catch { message = "변경을 완료하지 못했습니다. 저장 실패가 표시되면 다시 저장하거나 변경을 취소해 주세요." }
            state = await editor.state()
            if let word = selectedWords.first {
                selectedTurnID = document?.turns.first { $0.wordIds.contains(word.id) }?.id
            }
            isWorking = false
        }
    }

    func export(_ format: TranscriptExportFormat) {
        guard canExport, let document, let editor else { return }
        let selection = TranscriptExportSelection(
            version: version, sessionId: document.sessionId, runId: document.runId,
            revisionId: document.revision.id
        )
        let label = version == .automatic ? "자동본" : "현재 수정본"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .json ? .json : .plainText]
        panel.nameFieldStringValue = "다마-\(label).\(format == .json ? "json" : "txt")"
        panel.title = "\(label) 내보내기"
        panel.message = "현재 표시한 \(label)을 저장합니다."
        activity = "내보내는 중"
        isWorking = true
        Task {
            defer { isWorking = false }
            let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
                if let window = NSApp.keyWindow {
                    panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                } else { panel.begin { continuation.resume(returning: $0) } }
            }
            guard response == .OK, let url = panel.url else { return }
            do {
                _ = try await editor.export(selection: selection, format: format, to: url)
                message = "\(label) \(format == .json ? "JSON" : "TXT") 파일을 저장했습니다."
            } catch { message = "내보내지 못했습니다. 앱 내부 저장소가 아닌 위치와 쓰기 권한을 확인해 주세요." }
            state = await editor.state()
        }
    }

    func preventLeaving() {
        message = isPresentingEditor ? "열려 있는 수정 창에서 적용하거나 취소해 주세요."
            : isWorking ? "작업이 끝난 뒤 창을 닫거나 종료해 주세요."
            : "저장하지 못한 변경이 있습니다. 다시 저장하거나 변경을 취소한 뒤 종료해 주세요."
    }

    func speakerName(_ id: String?) -> String {
        id.flatMap { id in document?.speakers.first { $0.id == id }?.displayName } ?? "화자 미확정"
    }
}
