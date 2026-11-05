import AppKit
import DamaAudio
import DamaCore
import DamaManaged
import SwiftUI

struct ScriptReadingView: View {
    let file: LibraryScriptFile
    @ObservedObject var workspace: LibraryWorkspace
    var rename: (LibraryScriptFile, ScriptBlock) -> Void
    var correct: (LibraryScriptFile) -> Void
    @StateObject private var editor: ScriptEditingSession
    @ObservedObject private var correction = CorrectionWorkspace.shared
    @ObservedObject private var capture = RecordingWorkspace.shared.capture
    @State private var selected: String?
    @State private var information = false
    @State private var playingID: String?
    @State private var deletionError: String?
    @State private var hasSavedCorrections = false
    @State private var correctionError: String?
    /// usage-bundle1 교정 시도 기록 상태(이어서 교정).
    @State private var attempt: CorrectionRunner.Resume = .none
    init(file: LibraryScriptFile, workspace: LibraryWorkspace,
         rename: @escaping (LibraryScriptFile, ScriptBlock) -> Void, correct: @escaping (LibraryScriptFile) -> Void) {
        self.file = file; self.workspace = workspace; self.rename = rename; self.correct = correct
        _editor = StateObject(wrappedValue: ScriptEditingSession(file: file, workspace: workspace))
    }
    private var shown: LibraryScriptFile { editor.bodySource ?? file }
    private var blocks: [ScriptBlock] { shown.reading.blocks }
    private var selectedBlock: ScriptBlock? { blocks.first { $0.id == (editor.block?.id ?? selected) } ?? blocks.first }
    private var readOnly: Bool { file.script.snapshotTitle != nil }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    InlineScriptText(text: $editor.title, editable: !readOnly && editor.block == nil && !workspace.editing,
                        title: true, label: "스크립트 제목", changed: editor.titleChanged,
                        commit: editor.commitTitle, cancel: editor.cancelTitle)
                    // usage-bundle1: 연결 녹음이 있는 현재 결과에만 캡션 (문구 12).
                    if !readOnly && workspace.isLinked(file.script) {
                        Text("녹음 제목과 같이 바뀝니다.").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(file.script.recordedAt?.formatted(date: .numeric, time: .shortened) ?? "녹음 날짜 미확인")
                        Text("· \(LibraryScript.timestamp(file.script.transcript.durationUs))")
                        if let message = editor.titleMessage { Text(message) }
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("내보내기", systemImage: "square.and.arrow.up", action: workspace.exportMarkdown).disabled(!workspace.canLeave)
            }.padding(.horizontal, 28).padding(.vertical, 20)
            Divider()
            HStack(spacing: 12) {
                Text(file.script.snapshotTitle.map { "\($0) · 읽기 전용" } ?? currentLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if readOnly { Button("현재 결과로 돌아가기", action: workspace.returnToCurrent).disabled(!workspace.canLeave) }
                resultMenu
                Button(information ? "정보 닫기" : "정보", systemImage: "info.circle") { information.toggle() }
            }.padding(.horizontal, 28).padding(.vertical, 10)
            Divider()
            ScrollViewReader { scroll in
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(blocks) { block in
                                ReadingParagraphRow(block: block, editor: editor,
                                    selected: selectedBlock?.id == block.id, playing: playingID == file.id + ":" + block.id,
                                    canAct: workspace.canLeave && !readOnly,
                                    canPlay: !capture.phase.busy && !workspace.editing && !workspace.titlePending && block.startUs != nil && block.endUs != nil,
                                    select: { if editor.block == nil { selected = block.id } },
                                    rename: { rename(shown, block) }, play: { workspace.play(block, file: shown) },
                                    delete: { changeDeletion(block) })
                                    .id(block.id)
                            }
                            if blocks.isEmpty {
                                Text("표시할 발화가 없습니다.").foregroundStyle(.secondary).padding(24)
                            }
                        }.frame(maxWidth: 800).padding(.horizontal, 26).padding(.vertical, 14).frame(maxWidth: .infinity)
                    }
                    if information { inspector.frame(width: 285) }
                }
                Divider()
                if let deletionError { Text(deletionError).font(.caption).foregroundStyle(.red).padding(.horizontal, 24) }
                if let correctionError { Text(correctionError).font(.caption).foregroundStyle(.red).padding(.horizontal, 24) }
                HStack(spacing: 12) {
                    Button("이전 문단", systemImage: "chevron.up") { move(-1, scroll: scroll) }.labelStyle(.iconOnly).disabled(editor.block != nil || index <= 0)
                    Button("다음 문단", systemImage: "chevron.down") { move(1, scroll: scroll) }.labelStyle(.iconOnly).disabled(editor.block != nil || index + 1 >= blocks.count)
                    if let block = selectedBlock {
                        Button(playingID == file.id + ":" + block.id ? "재생 정지" : "원음 듣기", systemImage: playingID == file.id + ":" + block.id ? "stop.fill" : "play.fill") {
                            workspace.play(block, file: shown)
                        }.disabled(capture.phase.busy || workspace.editing || workspace.titlePending)
                        PlaybackPositionLabel(playback: workspace.playback)
                        if playingID != nil { Button("현재 문단") { scroll.scrollTo(selectedBlock?.id, anchor: .center) } }
                    }
                    Spacer()
                    if !readOnly, let changes = file.script.nameHistory, let last = changes.last {
                        Button("이름 변경 취소 (\(changes.count))") { undoNameChange() }
                            .disabled(!workspace.canLeave)
                            .help("마지막 화자 이름 변경을 되돌립니다. ‘\(last.name)’ · 원구간 \(last.turnIDs.count)개")
                    }
                    if !readOnly, let deleted = file.script.deletedParagraphs, !deleted.isEmpty {
                        Button("삭제 취소 (\(deleted.count))") { changeDeletion(nil) }.disabled(!workspace.canLeave)
                    }
                    if capture.phase.busy { Text("녹음 중에는 재생할 수 없습니다.").font(.caption).foregroundStyle(.secondary) }
                    if correction.activeID == file.id {
                        ProgressView().controlSize(.small)
                        Text("AI 보정 중… \(correction.completed)/\(correction.total)").font(.caption)
                        Button("보정 취소", action: correction.cancel)
                    } else {
                        if !readOnly { attemptControls }
                        if !readOnly && hasSavedCorrections {
                            Button("저장된 AI 교정 반영") {
                                correctionError = nil
                                Task {
                                    do { try await workspace.applyPendingCorrection(file) }
                                    catch { correctionError = "교정을 반영하지 못했습니다. 새로고침 후 다시 시도해 주세요." }
                                }
                            }.help("AI를 다시 호출하지 않고 저장된 확실한 후보를 새 결과로 반영합니다.")
                                .disabled(!workspace.canLeave || correction.busy)
                        }
                        Button("AI 검수/보정", systemImage: "sparkles") { correct(file) }.disabled(readOnly || !workspace.canLeave || correction.busy)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 14)
            }
        }
        .onChange(of: file.hash) { _, _ in editor.receive(file) }
        .onChange(of: workspace.displayTitles) { _, _ in editor.refreshTitle() }
        .task(id: file.hash) {
            let script = file.script
            hasSavedCorrections = await Task.detached(priority: .utility) {
                (try? ContextCorrection.reapplyingPending(in: script)) != nil
            }.value
        }
        .task(id: "\(file.hash):\(correction.attemptVersion):\(correction.activeID ?? "")") {
            attempt = readOnly ? .none : await correction.attemptStatus(for: file.script)
        }
        .onReceive(workspace.playback.$playingID.removeDuplicates()) { playingID = $0 }
        .onReceive(workspace.playback.$positionUs) { position in
            guard playingID != nil, editor.block == nil,
                  let active = blocks.first(where: { ($0.startUs ?? .max) <= position && ($0.endUs ?? 0) > position }),
                  selected != active.id else { return }
            selected = active.id
        }
        .onDisappear { workspace.playback.stop() }
    }
    /// 하단 미완료 줄·이어서 교정 버튼·이어하기 불가 줄 (tone 문구 13–16).
    @ViewBuilder private var attemptControls: some View {
        switch attempt {
        case .none: EmptyView()
        case .available(let done, let total, let last):
            Text(Self.unfinished(done, total, last)).font(.caption).foregroundStyle(.secondary)
            // 다른 교정이 돌고 있으면 버튼을 보이지 않는다(계약 «다른 교정 없음일 때만», QA C D-4).
            if !correction.busy {
                Button(done == 0 ? "같은 입력으로 다시 시도" : "이어서 교정 (\(done)/\(total))") { confirmResume(done: done, total: total) }
                    .disabled(!workspace.canLeave)
            }
        case .planChanged(let done, let total, let last):
            Text(Self.unfinished(done, total, last)).font(.caption).foregroundStyle(.secondary)
            Text("스크립트가 바뀌어 이어서 교정할 수 없습니다. AI 검수/보정으로 처음부터 다시 실행해 주세요.").font(.caption)
        }
    }
    private static func unfinished(_ done: Int, _ total: Int, _ last: CorrectionFailureRecord?) -> String {
        // 실패 기록이 없으면(앱 종료 등으로 끊긴 시도) 짧은 원인을 쓰지 않는다.
        "AI 보정 미완료 · \(done)/\(total) 구간 완료" + (last.map { " · " + $0.kind.shortLabel(exitCode: $0.exitCode) } ?? "")
    }
    /// 이어하기 확인창 (tone 문구 17). 기본 버튼 «취소».
    private func confirmResume(done: Int, total: Int) {
        guard workspace.canLeave, !correction.busy, !readOnly else { return }
        let alert = NSAlert()
        alert.messageText = done == 0 ? "같은 입력으로 다시 시도할까요?" : "이어서 교정할까요?"
        alert.informativeText = (done == 0 ? "처음 확인한 입력으로 \(total)개 구간 전부를 다시 보냅니다." : "완료한 \(done)개 구간은 다시 보내지 않습니다.") +
            " 남은 \(total - done)개 구간의 전사와 처음 확인한 참석자·맥락·참고 내용을 OpenAI로 전송합니다. 계정 사용량이 소모될 수 있습니다. 원음은 보내지 않습니다."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: done == 0 ? "다시 시도" : "이어서 교정")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        correction.resume(file)
    }
    private var currentLabel: String {
        let number = workspace.scriptFile?.script.versions?.last?.number ?? 0
        return number > 0 ? "현재 결과 · AI 보정 \(number) 기반" : "현재 결과"
    }
    private func undoNameChange() {
        guard workspace.canLeave, !readOnly else { return }
        workspace.playback.stop(); deletionError = nil
        let source = shown
        Task {
            do {
                var candidate = source.script
                try candidate.undoNameChange()
                try await workspace.saveScript(candidate, original: source)
            } catch { deletionError = "이름 변경을 되돌리지 못했습니다. 새로고침 후 다시 시도해 주세요." }
        }
    }
    private func changeDeletion(_ block: ScriptBlock?) {
        guard workspace.canLeave, !readOnly else { return }
        workspace.playback.stop(); deletionError = nil
        let source = shown, oldIndex = index
        Task {
            do {
                var candidate = source.script
                if let block { try candidate.deleteParagraph(block) }
                else { try candidate.undoParagraphDeletion() }
                try await workspace.saveScript(candidate, original: source)
                let remaining = candidate.blocks()
                selected = remaining.isEmpty ? nil : remaining[min(oldIndex, remaining.count - 1)].id
            } catch { deletionError = "발화 변경을 저장하지 못했습니다. 새로고침 후 다시 시도해 주세요." }
        }
    }
    private var resultMenu: some View {
        Menu("다른 결과 보기") {
            Button(currentLabel, action: workspace.returnToCurrent)
            if let current = workspace.scriptFile {
                ForEach((current.script.versions ?? []).reversed()) { version in
                    Button("\(version.title) · \(version.createdAt.formatted(date: .numeric, time: .shortened))") { workspace.selectVersion(version) }
                }
                Divider()
                ForEach(workspace.scripts.filter {
                    $0.sessionId == current.script.transcript.sessionId ||
                    ($0.sourceAudioSHA256 != nil && $0.sourceAudioSHA256 == current.script.transcript.provenance.sourceAudioSHA256)
                }) { other in
                    Button("\(other.id == current.id ? "✓ " : "")\(other.engine.title) · \(other.createdAt.formatted(date: .numeric, time: .shortened))") { workspace.selectScript(other.id) }
                }
            }
        }.fixedSize().disabled(!workspace.canLeave)
    }
    private var index: Int { blocks.firstIndex { $0.id == selectedBlock?.id } ?? 0 }
    private func move(_ direction: Int, scroll: ScrollViewProxy) {
        let next = index + direction
        guard blocks.indices.contains(next) else { return }
        selected = blocks[next].id
        withAnimation { scroll.scrollTo(selected, anchor: .center) }
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("구간 정보").font(.headline); Spacer(); Button("닫기") { information = false } }
                if let block = selectedBlock {
                    Text("\(LibraryScript.timestamp(block.startUs)) – \(LibraryScript.timestamp(block.endUs))").font(.caption.monospaced())
                    Text("연결된 원구간 \(block.turnIDs.count)개").font(.caption)
                    // usage-bundle1: 녹음 중단·일부 결과는 맨 위 경고 줄, 자동 경고 8종은 «자동 경고 N건» 접힘(기본 닫힘).
                    ForEach(block.persistentWarnings, id: \.id) { issue in
                        PersistentWarningLine(text: issue.kind.persistentWarningText ?? issueLabel(issue.kind)).font(.callout)
                    }
                    let warnings = block.autoWarningSummary
                    if !warnings.isEmpty {
                        DisclosureGroup("자동 경고 \(warnings.reduce(0) { $0 + $1.count })건") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("화자 분리와 시간 정렬이 남긴 자동 판정입니다. 원음으로 확인한 결과가 아닙니다.").foregroundStyle(.secondary)
                                ForEach(warnings, id: \.kind) { item in Text("\(issueLabel(item.kind)) · \(item.count)건") }
                            }.padding(.top, 4)
                        }.font(.callout).id(block.id)
                    }
                    let edits = shown.script.correction?.visibleEdits.filter { block.turnIDs.contains($0.turnID) } ?? []
                    ForEach(edits, id: \.turnID) { edit in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(edit.decisionLabel).fontWeight(.semibold)
                            Text(edit.reason); Text("\(edit.applied ? "AI 교정" : "AI 후보"): \(edit.text)")
                            ForEach(Array((edit.changes ?? []).enumerated()), id: \.offset) { _, decision in
                                Text("\(decision.applied ? "반영" : "보류"): \(decision.change.quote) → \(decision.change.replacement)")
                                Text(decision.basis)
                            }
                            ForEach(Array((edit.unresolved ?? []).enumerated()), id: \.offset) { _, item in Text("\(item.quote) · \(item.reason)") }
                        }.font(.caption)
                    }
                    DisclosureGroup("모델 원문") { Text(block.turns.map { shown.script.modelText(for: $0) }.joined(separator: "\n")).font(.caption) }
                }
                Divider()
                Text("녹음·변환 정보").font(.headline)
                Text(file.script.transcript.provenance.engine.title)
                Text(file.reading.speakerCountSummary)
                Text(file.script.speakerCountApplication)
                Text(file.script.dateSource)
                Text("전사 문맥: \(file.script.input.transcriptionContextSummary)")
                Text("참석자: \(file.script.input.participants ?? "미입력")")
                Text("맥락: \(file.script.input.context)")
                Text("참고: \(file.script.input.reference)")
                if !readOnly {
                    Button("새 입력으로 다시 전사") { workspace.retranscribeScript(LibraryScriptSummary(file)) }.disabled(!workspace.canRetranscribe(file.script.transcript.sessionId))
                    Button("Scripts에서 삭제", role: .destructive) { workspace.deleteScript(LibraryScriptSummary(file)) }.disabled(workspace.foldersLocked)
                }
            }.font(.caption).textSelection(.enabled).padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ReadingParagraphRow: View {
    let block: ScriptBlock
    @ObservedObject var editor: ScriptEditingSession
    let selected: Bool
    let playing: Bool
    let canAct: Bool
    let canPlay: Bool
    let select: () -> Void
    let rename: () -> Void
    let play: () -> Void
    let delete: () -> Void
    private var editing: Bool { editor.block?.id == block.id }
    private var name: String { block.name == "화자 미확정" ? "화자 미배정" : block.name }
    private static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown, .red, .yellow]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(block.colorIndex.map { Self.colors[$0] } ?? .secondary).frame(width: 6, height: 6)
                Button(name, action: rename).buttonStyle(.plain).font(.callout.weight(.semibold)).disabled(!canAct).accessibilityLabel("\(name) 화자 이름 변경")
                if block.edited { Text("사용자 수정").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Text(LibraryScript.timestamp(block.startUs)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            InlineScriptText(text: editing ? $editor.text : .constant(block.text), editable: editing && !editor.savingBody,
                focus: editing, label: editing ? "본문 편집" : "스크립트 본문", changed: editor.bodyChanged,
                commit: editor.saveBody, cancel: editor.cancelBody, activated: select)
            ForEach(block.persistentWarnings, id: \.id) { issue in
                PersistentWarningLine(text: issue.kind.persistentWarningText ?? issueLabel(issue.kind)).font(.caption)
            }
            if selected || editing {
                HStack(spacing: 10) {
                    Button(playing ? "재생 정지" : "원음 듣기", systemImage: playing ? "stop.fill" : "play.fill", action: play).disabled(!canPlay)
                    if block.isSpeech && !editor.readOnly {
                        Button(editor.savingBody ? "저장 중…" : editing && editor.bodyDirty ? "저장" : "수정") {
                            if editing { editor.saveBody() } else { editor.begin(block) }
                        }.disabled(editor.savingBody || (!editing && !canAct))
                    }
                    if editing {
                        Button("취소", action: editor.cancelBody).disabled(editor.savingBody)
                        Text(editor.bodyDirty ? "저장하지 않은 변경" : "본문 편집 중").font(.caption).foregroundStyle(.secondary)
                    }
                    if !editing && !editor.readOnly {
                        Button("삭제", role: .destructive, action: delete).disabled(!canAct)
                            .accessibilityLabel("발화 삭제")
                    }
                    Spacer(minLength: 0)
                }.controlSize(.small)
                if editing, let message = editor.bodyMessage { Text(message).font(.caption).foregroundStyle(.red) }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor.opacity(0.6) : .clear))
            .contentShape(Rectangle()).onTapGesture(perform: select)
    }
}

/// 녹음 중단·일부 결과 경고 줄. ⚠ 기호와 문장으로 표시하고 색만으로 구분하지 않는다 (usage-bundle1 문구 1).
private struct PersistentWarningLine: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("⚠").accessibilityHidden(true)
            Text(text)
        }.accessibilityElement(children: .combine).accessibilityLabel("경고: \(text)")
    }
}

private struct PlaybackPositionLabel: View {
    @ObservedObject var playback: SegmentPlayback
    var body: some View {
        if playback.playingID != nil { Text(LibraryScript.timestamp(playback.positionUs)).font(.caption.monospaced()).foregroundStyle(.secondary) }
    }
}
