import AppKit
import DamaCore
import SwiftUI

struct ReviewShell: View {
    @ObservedObject var workspace: ReviewWorkspace
    @State private var showEvidence = false
    @State private var dialog: EditDialog?
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebar.frame(width: 220)
                Divider()
                VStack(spacing: 0) {
                    header(compact: geometry.size.width < 1_100)
                    Divider()
                    notices
                    transcript
                    Divider()
                    editBar
                }
                if geometry.size.width >= 1_100 {
                    Divider()
                    EvidencePanel(workspace: workspace).frame(width: 260)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ReviewWindowGuard(workspace: workspace))
        .task { workspace.start() }
        .sheet(item: $dialog, onDismiss: { workspace.isPresentingEditor = false }) { item in
            EditDialogView(dialog: item) { value in
                workspace.isPresentingEditor = false
                switch item.kind {
                case .word(let id): workspace.apply(.replaceWordText(wordId: id, editedText: value))
                case .speaker(let id): workspace.apply(.renameSpeaker(speakerId: id, displayName: value))
                }
            }
        }
        .onExitCommand {
            if showEvidence { showEvidence = false }
            else if !workspace.search.isEmpty { workspace.search = "" }
            else { workspace.clearSelection() }
        }
        .toolbar {
            ToolbarItem {
                Button { searchFocused = true } label: { Label("검색", systemImage: "magnifyingglass") }
                    .keyboardShortcut("f")
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("다마").font(.system(size: 21, weight: .semibold))
            Text("이 Mac의 기록").font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(workspace.sessions, id: \.sessionId) { session in
                        Button { workspace.open(session.sessionId) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label("검수 세션", systemImage: "text.bubble")
                                Text(session.sessionId).font(.caption).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(workspace.document?.sessionId == session.sessionId
                                ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(!workspace.canLeave)
                            .accessibilityLabel("검수 세션 \(session.sessionId)")
                    }
                }
            }
            if workspace.sessions.isEmpty { Text("저장된 세션이 없습니다.").foregroundStyle(.secondary) }
            Button("목록 다시 읽기", action: workspace.refresh).disabled(!workspace.canLeave)
            Spacer(minLength: 0)
            #if DEBUG
            Button("합성 테스트 데이터 열기", action: workspace.importFixture)
                .disabled(!workspace.didLoad || !workspace.canLeave)
            #endif
            Text("메뉴바 좌클릭으로 녹음을 시작하고,\n우클릭 패널에서 파일 가져오기와 전송 검토를 할 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).background(Color(nsColor: .controlBackgroundColor))
    }

    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("원문 검수").font(.system(size: 21, weight: .semibold))
                if workspace.document?.provenance.isSynthetic == true {
                    Text("합성 테스트 데이터").font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(workspace.saveLabel).font(.caption).foregroundStyle(.secondary)
                if compact {
                    Button("근거 보기") { showEvidence.toggle() }
                        .popover(isPresented: $showEvidence, arrowEdge: .trailing) {
                            VStack(alignment: .trailing, spacing: 0) {
                                Button("닫기") { showEvidence = false }.keyboardShortcut(.cancelAction).padding(8)
                                EvidencePanel(workspace: workspace)
                            }.frame(width: 300, height: 500)
                        }
                }
            }
            HStack {
                Picker("표시 버전", selection: $workspace.version) {
                    Text("현재 수정본").tag(TranscriptExportVersion.current)
                    Text("자동본").tag(TranscriptExportVersion.automatic)
                }.pickerStyle(.segmented).frame(maxWidth: 220)
                    .disabled(!workspace.canLeave || workspace.document == nil)
                Spacer(minLength: 8)
                Menu("내보내기") {
                    Button("표시한 버전 · JSON") { workspace.export(.json) }
                    Button("표시한 버전 · TXT") { workspace.export(.text) }
                }.fixedSize().disabled(!workspace.canExport)
            }
            HStack {
                TextField("원문 검색", text: $workspace.search).textFieldStyle(.roundedBorder)
                    .focused($searchFocused).accessibilityLabel("원문 검색")
                if !workspace.search.isEmpty {
                    Button("지우기") { workspace.search = "" }.accessibilityLabel("검색어 지우기")
                }
                Button(workspace.isLastIssue ? "첫 확인 구간으로" : "다음 확인 구간", action: workspace.nextIssue)
                    .disabled(workspace.openIssues.isEmpty).keyboardShortcut("j", modifiers: [.command, .option])
            }
        }.padding(16)
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let recovery = workspace.recoveryMessage {
                Label(recovery, systemImage: "arrow.counterclockwise.circle")
            }
            if let message = workspace.message {
                HStack(alignment: .top) {
                    Text(message).frame(maxWidth: .infinity, alignment: .leading)
                    Button { workspace.message = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("알림 닫기")
                }
            }
            if workspace.state?.isDirty == true {
                HStack {
                    Label("저장하지 못했습니다", systemImage: "exclamationmark.triangle")
                    Button("다시 저장", action: workspace.retry)
                    Button("변경 취소", action: workspace.cancelFailedSave)
                }.disabled(workspace.isWorking)
            }
            if workspace.version == .automatic { Text("자동본은 읽기 전용입니다. 수정하려면 현재 수정본을 선택하세요.") }
        }.font(.callout).padding(.horizontal, 16).padding(.vertical, 6)
    }

    private var visibleTurns: [TranscriptTurn] {
        guard let document = workspace.document else { return [] }
        guard !workspace.search.isEmpty else { return document.turns }
        let words = Dictionary(uniqueKeysWithValues: document.words.map { ($0.id, $0) })
        return document.turns.filter { turn in
            let text = turn.markerText ?? turn.wordIds.compactMap { words[$0] }
                .map { $0.prefix + ($0.editedText ?? $0.text) }.joined()
            return text.localizedCaseInsensitiveContains(workspace.search)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if workspace.document == nil {
                        ContentUnavailableView("검수할 세션이 없습니다.", systemImage: "text.bubble",
                            description: Text("저장된 세션을 선택하거나 Debug 합성 테스트 데이터를 열어 주세요."))
                    } else if visibleTurns.isEmpty {
                        ContentUnavailableView("검색 결과가 없습니다.", systemImage: "magnifyingglass")
                        Button("검색어 지우기") { workspace.search = "" }
                    } else {
                        ForEach(visibleTurns, id: \.id) { turn in turnRow(turn).id(turn.id) }
                    }
                    if workspace.document != nil && workspace.openIssues.isEmpty {
                        Text("미확인 이슈가 없습니다. 정확도를 보장하지는 않습니다.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if workspace.isLastIssue {
                        Text("마지막 확인 구간입니다").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }.onChange(of: workspace.selectedTurnID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func turnRow(_ turn: TranscriptTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(workspace.speakerName(turn.speakerId)).fontWeight(.semibold)
                Text(timeRange(turn.startUs, turn.endUs)).font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if turn.kind == .missingSpeech {
                Button { workspace.selectMarker(turn) } label: {
                    Label(turn.markerText ?? "[음성 감지 / 전사 누락 의심]", systemImage: "waveform")
                        .font(.system(size: 17)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                            Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }.buttonStyle(.plain)
                Text("감지 길이 \(TranscriptTimePresentation.duration(startUs: turn.startUs, endUs: turn.endUs))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                WordFlowLayout(spacing: 0) {
                    ForEach(words(in: turn), id: \.id) { word in
                        Button {
                            workspace.selectWord(word, turnID: turn.id, extending: NSEvent.modifierFlags.contains(.shift))
                        } label: {
                            Text(word.prefix + (word.editedText ?? word.text))
                                .font(.system(size: 17)).padding(.vertical, 5).padding(.horizontal, 2)
                                .background(workspace.selectedWordIDs.contains(word.id)
                                    ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                                .underline(word.editedText != nil)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(word.editedText ?? word.text), \(workspace.speakerName(word.speakerId)), \(timeRange(word.startUs, word.endUs)), 이슈 \(word.reviewIssueIds.count)개")
                            .accessibilityValue(workspace.selectedWordIDs.contains(word.id) ? "선택됨" : "선택 안 됨")
                            .accessibilityHint("Shift와 함께 선택하면 단어 범위를 선택합니다.")
                    }
                }
                if words(in: turn).contains(where: { $0.editedText != nil && $0.timingOrigin == .inheritedUnaligned }) {
                    Text("시간 재정렬 안 됨").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(issues(in: turn), id: \.id) { issue in
                Button { workspace.selectIssue(issue) } label: {
                    Label("\(issueLabel(issue.kind)) · \(issue.status == .open ? "미확인" : issue.status == .acknowledged ? "확인함" : "해결됨")",
                        systemImage: issue.status == .open ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.caption).multilineTextAlignment(.leading)
                }.buttonStyle(.plain)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                workspace.selectedTurnID == turn.id ? Color.accentColor : Color.clear, lineWidth: 1))
            .accessibilityElement(children: .contain)
    }

    private func words(in turn: TranscriptTurn) -> [TranscriptWord] {
        let map = Dictionary(uniqueKeysWithValues: (workspace.document?.words ?? []).map { ($0.id, $0) })
        return turn.wordIds.compactMap { map[$0] }
    }
    private func issues(in turn: TranscriptTurn) -> [ReviewIssue] {
        let ids = Set(turn.reviewIssueIds + words(in: turn).flatMap(\.reviewIssueIds))
        return workspace.document?.reviewIssues.filter { ids.contains($0.id) } ?? []
    }

    private var editBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(workspace.selectedWords.isEmpty ? "단어 또는 확인 구간을 선택하세요." : "단어 \(workspace.selectedWords.count)개 선택")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("실행 취소", action: workspace.undo).disabled(!workspace.canEdit || workspace.state?.canUndo != true)
                Button("다시 실행", action: workspace.redo).disabled(!workspace.canEdit || workspace.state?.canRedo != true)
            }
            HStack {
                Menu("화자 변경") {
                    ForEach(workspace.document?.speakers ?? [], id: \.id) { speaker in
                        Button(speaker.displayName) {
                            workspace.apply(.assignWords(wordIds: workspace.selectedWords.map(\.id), speakerId: speaker.id))
                        }
                    }
                    Divider()
                    Button("화자 미확정") { workspace.apply(.assignWords(wordIds: workspace.selectedWords.map(\.id), speakerId: nil)) }
                }.disabled(!workspace.canEdit || workspace.selectedWords.isEmpty)
                    .accessibilityLabel("선택 단어의 화자 변경")
                Menu("수정") {
                    Button("선택 단어 수정") {
                        if let word = workspace.selectedWords.first {
                            present(EditDialog(kind: .word(word.id), title: "선택 단어 수정", value: word.editedText ?? word.text, original: word.text))
                        }
                    }.disabled(workspace.selectedWords.count != 1)
                    Button("모델 원문으로 되돌리기") {
                        if let word = workspace.selectedWords.first { workspace.apply(.revertWordText(wordId: word.id)) }
                    }.disabled(workspace.selectedWords.count != 1 || workspace.selectedWords.first?.editedText == nil)
                    Menu("화자 이름 변경") {
                        ForEach(workspace.document?.speakers ?? [], id: \.id) { speaker in
                            Button(speaker.displayName) {
                                present(EditDialog(kind: .speaker(speaker.id), title: "화자 이름 변경", value: speaker.displayName, original: nil))
                            }
                        }
                    }
                    Button("여기서 발화 나누기") {
                        if let word = workspace.selectedWords.first, let turn = workspace.selectedTurn {
                            workspace.apply(.splitTurn(turnId: turn.id, beforeWordId: word.id))
                        }
                    }.disabled(!canSplit)
                }.disabled(!workspace.canEdit)
                Spacer(minLength: 4)
                if let issue = workspace.selectedIssue {
                    Button(issue.status == .open ? "확인함" : "미확인으로 되돌리기") {
                        workspace.apply(issue.status == .open ? .acknowledgeIssue(issueId: issue.id) : .reopenIssue(issueId: issue.id))
                    }.disabled(!workspace.canEdit)
                }
            }
        }.padding(12)
    }
    private var canSplit: Bool {
        guard workspace.selectedWords.count == 1, let word = workspace.selectedWords.first,
              let turn = workspace.selectedTurn, let index = turn.wordIds.firstIndex(of: word.id) else { return false }
        return turn.kind == .speech && index > 0
    }
    private func present(_ item: EditDialog) {
        workspace.isPresentingEditor = true
        dialog = item
    }
}

func timeRange(_ start: Int64?, _ end: Int64?) -> String {
    guard start != nil, end != nil else { return TranscriptTimePresentation.unavailable }
    return "\(TranscriptTimePresentation.timestamp(start))–\(TranscriptTimePresentation.timestamp(end))"
}
func issueLabel(_ kind: IssueKind) -> String {
    switch kind {
    case .ambiguous_speaker: "화자 미확정 · 후보가 비슷합니다."
    case .overlapping_speech: "동시에 여러 화자가 감지되었습니다. 두 사람의 발화가 모두 전사되었다는 뜻은 아닙니다."
    case .missing_speech: "음성 감지 / 전사 누락 의심"
    case .boundary_conflict: "단어 시간이 화자 전환 경계를 걸칩니다."
    case .unrepresented_speaker: "음성에서 감지된 화자가 스크립트에 나타나지 않습니다."
    case .invalid_timestamp: "시간을 확인할 수 없습니다. 원문은 보존되어 있습니다."
    case .low_confidence: "공급자 화자 점수가 낮아 확인이 필요합니다."
    case .capture_interrupted: "녹음이 중단되었습니다. 이후 구간은 녹음되지 않았을 수 있습니다."
    case .partial_result: "일부 전사 결과를 받지 못했습니다."
    }
}

/// Individually focusable words wrap in their stored order, including original prefixes.
struct WordFlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 500, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
