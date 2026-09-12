import AppKit
import DamaAudio
import DamaCore
import DamaManaged
import SwiftUI

struct ProcessingProgressCard: View {
    let run: ManagedRun?
    let tracking: Bool
    let preparing: Bool
    let startedAt: Date?
    var scriptSaved = false
    var body: some View {
        let state = ProcessingPresentation(run: run, tracking: tracking, preparing: preparing, scriptSaved: scriptSaved)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if state.spinning { ProgressView().controlSize(.regular).accessibilityLabel("변환 진행 중") }
                else { Image(systemName: state.completed ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(state.completed ? Color.green : Color.secondary).font(.title2) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.title).font(.headline)
                    Text(state.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let step = state.step {
                HStack(spacing: 10) {
                    ForEach(Array(ProcessingPresentation.steps.enumerated()), id: \.offset) { index, title in
                        HStack(spacing: 5) {
                            Image(systemName: index < step || state.completed ? "checkmark.circle.fill" : index == step ? "circle.inset.filled" : "circle")
                            Text(title).lineLimit(1)
                        }.font(.caption).foregroundStyle(index <= step ? Color.accentColor : Color.secondary)
                        if index < 3 { Rectangle().fill(Color.secondary.opacity(0.2)).frame(maxWidth: 24).frame(height: 1) }
                    }
                }.accessibilityElement(children: .combine)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack(spacing: 16) {
                    if state.spinning, let startedAt {
                        Text("이번 처리 경과 \(ProcessingPresentation.elapsed(since: startedAt, now: timeline.date))")
                    }
                    if let checked = run?.lastServerCheckAt {
                        Text("마지막 서버 확인 \(checked.formatted(date: .omitted, time: .standard))")
                    }
                }.font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.15)))
    }
}

struct ScriptBlockRow: View {
    let block: ScriptBlock
    let rename: () -> Void
    let editText: () -> Void
    var editParagraphs: (() -> Void)?
    var review: (() -> Void)?
    var play: () -> Void = {}
    var playing = false
    var canPlay = false
    var playEvent: ((ScriptReviewEvent) -> Void)?
    var playingEventID: String?
    var corrections: [CorrectionEdit] = []
    var resolvedTurnIDs: Set<String> = []
    var resolveCorrection: ((CorrectionEdit, Bool) -> Void)?
    @State private var events = false
    // 10 stable slots by original speaker order. Text labels remain the identity cue.
    private static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown, .red, .yellow]
    private var color: Color { block.colorIndex.map { Self.colors[$0] } ?? .secondary }
    var body: some View {
        let reviewEvents = block.reviewEvents
        let pendingCorrections = corrections.filter { !$0.applied && !resolvedTurnIDs.contains($0.turnID) }
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(action: rename) {
                        HStack(spacing: 6) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(block.name).fontWeight(.semibold)
                            Image(systemName: "chevron.down").font(.caption2)
                        }.font(.callout)
                    }.buttonStyle(.plain).accessibilityLabel("\(block.name) 화자 이름 변경")
                    if !reviewEvents.isEmpty || !pendingCorrections.isEmpty {
                        Button { events.toggle() } label: {
                            Image(systemName: "exclamationmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(Color.black, Color.yellow)
                        }.buttonStyle(.plain).help("이 구간의 이벤트 보기")
                            .accessibilityLabel("\(block.name) 확인 구간 \(reviewEvents.count)개, AI 확인 \(pendingCorrections.count)개")
                            .popover(isPresented: $events) {
                                ScrollView {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("이 구간의 이벤트").font(.headline)
                                    ForEach(pendingCorrections, id: \.turnID) { edit in
                                        Text("AI 확인 필요: \(edit.reason)").font(.callout)
                                        Text("교정안: \(edit.text)").font(.caption).foregroundStyle(.secondary)
                                        ForEach(Array((edit.unresolved ?? []).enumerated()), id: \.offset) { _, item in
                                            Text("미해결: \(item.quote) · \(item.reason)").font(.caption)
                                        }
                                    }
                                    ForEach(reviewEvents) { event in
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(event.kinds, id: \.rawValue) { kind in
                                                Text(issueLabel(kind)).font(.callout)
                                            }
                                            Text("\(LibraryScript.timestamp(event.startUs)) – \(LibraryScript.timestamp(event.endUs))")
                                                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                            if let playEvent, event.startUs != nil, event.endUs != nil {
                                                Button(playingEventID == event.id ? "재생 정지" : "앞뒤 원음 듣기",
                                                       systemImage: playingEventID == event.id ? "stop.fill" : "play.fill") { playEvent(event) }
                                                    .disabled(!canPlay)
                                            }
                                            DisclosureGroup("세부 표시 \(event.issues.count)개") {
                                                ForEach(event.issues, id: \.id) { issue in
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Text(issueLabel(issue.kind))
                                                        Text("\(LibraryScript.timestamp(issue.startUs)) – \(LibraryScript.timestamp(issue.endUs))")
                                                            .foregroundStyle(.secondary)
                                                    }.font(.caption).padding(.vertical, 3)
                                                }
                                            }
                                        }
                                        Divider()
                                    }
                                    HStack { Spacer(); Button("닫기") { events = false } }
                                }.padding(20).frame(width: 360).textSelection(.enabled)
                                }.frame(width: 360, height: 420)
                            }
                    }
                    Spacer(minLength: 8)
                    if let review { Button("검수 기록", action: review).buttonStyle(.plain).font(.caption) }
                    if block.isSpeech, let editParagraphs {
                        Button("문단", action: editParagraphs).buttonStyle(.plain).font(.caption)
                            .accessibilityLabel("문단 합치기·나누기")
                    }
                    Button(action: play) {
                        Label("\(LibraryScript.timestamp(block.startUs)) – \(LibraryScript.timestamp(block.endUs))", systemImage: playing ? "stop.fill" : "play.fill")
                            .font(.system(.caption, design: .monospaced))
                    }.buttonStyle(.plain).disabled(!canPlay)
                        .help(block.startUs == block.endUs ? "발화 길이가 없어 앞뒤 원음을 재생합니다" : "이 구간 원음 재생·정지")
                }
                if block.isSpeech {
                    Button(action: editText) {
                        Text(block.text.isEmpty ? "(빈 대사)" : block.text)
                            .font(.system(size: 17)).lineSpacing(7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("대사 수정: \(block.text)")
                } else { Text(block.text).foregroundStyle(.secondary) }
                if block.edited { Text("사용자 수정 · 시간 재정렬 안 됨").font(.caption).foregroundStyle(.secondary) }
                if !corrections.isEmpty {
                    DisclosureGroup("AI 교정 이력 \(corrections.count)개") {
                        ForEach(corrections, id: \.turnID) { edit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("원문: \(edit.original)")
                                Text("교정안: \(edit.text)")
                                Text("\(edit.decisionLabel) · \(edit.reason)").foregroundStyle(.secondary)
                                if let text = edit.appliedText, !edit.applied { Text("현재 반영: \(text)") }
                                ForEach(Array((edit.changes ?? []).enumerated()), id: \.offset) { _, decision in
                                    Text("\(decision.applied ? "반영" : "보류"): \(decision.change.quote) → \(decision.change.replacement) · \(decision.basis) \(decision.change.reason)")
                                }
                                ForEach(Array((edit.unresolved ?? []).enumerated()), id: \.offset) { _, item in
                                    Text("미해결: \(item.quote) · \(item.reason)")
                                }
                                if !edit.applied, !resolvedTurnIDs.contains(edit.turnID), let resolveCorrection {
                                    HStack {
                                        Button(edit.changes == nil ? "교정안 적용" : "전체 교정안 적용") { resolveCorrection(edit, true) }.disabled(edit.text == edit.original || edit.text.isEmpty)
                                        Button(edit.changes == nil ? "원문 유지" : "전체 원문 유지") { resolveCorrection(edit, false) }
                                    }
                                } else if resolvedTurnIDs.contains(edit.turnID) {
                                    Text("사용자 선택·수정 우선").foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4).textSelection(.enabled)
                        }
                    }.font(.caption)
                }
            }.padding(18)
        }.fixedSize(horizontal: false, vertical: true)
            .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
    private func issueLabel(_ kind: IssueKind) -> String {
        switch kind {
        case .ambiguous_speaker: "화자가 미확정이거나 후보가 비슷합니다."
        case .overlapping_speech: "여러 화자의 음성 구간이 겹칩니다. 원음으로 확인해 주세요."
        case .missing_speech: "음성은 감지되었지만 전사가 누락되었을 수 있습니다."
        case .boundary_conflict: "단어 시간이 화자 전환 경계에 걸쳐 있습니다."
        case .capture_interrupted: "녹음이 중단되어 이후 구간이 녹음되지 않았을 수 있습니다."
        case .unrepresented_speaker: "음성에서 감지된 화자가 스크립트에 나타나지 않습니다."
        case .invalid_timestamp: "발화 길이가 없거나 시간이 불확실합니다. 앞뒤 원음으로 확인해 주세요."
        case .low_confidence: "공급자의 화자 점수가 낮아 확인이 필요합니다."
        case .partial_result: "일부 전사 결과를 받지 못했습니다."
        case .provider_disagreement: "두 제공자의 화자 구분이 일치하지 않습니다. 원 후보와 원음을 확인해 주세요."
        }
    }
}

struct LibraryShell: View {
    @ObservedObject var workspace: LibraryWorkspace
    @ObservedObject private var processing = ProcessingWorkspace.shared
    @ObservedObject private var recording = RecordingWorkspace.shared
    @ObservedObject private var capture = RecordingWorkspace.shared.capture
    @ObservedObject private var correction = CorrectionWorkspace.shared
    // Playback position ticks do not invalidate the entire transcript view.
    @State private var playingID: String?
    @State private var playbackMessage: String?
    @State private var edit: LibraryEdit?
    @State private var settings = false
    @State private var terms = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DAMA").font(.headline)
                Spacer()
                if correction.busy {
                    Text("AI 교정 중").font(.caption).foregroundStyle(.secondary)
                    Button("교정 중단", action: correction.cancel)
                }
                if capture.phase == .recording { Label("녹음 중 · \(LibraryScript.timestamp(capture.elapsedUs))", systemImage: "record.circle.fill").foregroundStyle(.red) }
                if workspace.busy { ProgressView().controlSize(.small); Text("불러오거나 저장하는 중").font(.caption) }
                Button("설정", systemImage: "gearshape") { settings = true }
            }.padding(.horizontal, 20).frame(height: 48)
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 16) {
                    Picker("새 전사 엔진", selection: $processing.selectedProvider) {
                        ForEach(TranscriptionProvider.selectable, id: \.self) { Text($0.title).tag($0) }
                    }.frame(width: 260)
                    if [.sonioxPrecision, .qwen].contains(processing.selectedProvider) { Text("AI 교정 OFF").font(.caption) }
                    else { Toggle("엔진 비교 · 자동 교정 끔", isOn: $processing.comparison) }
                    if processing.selectedProvider.usesSoniox {
                        Toggle("기본 문맥 전송", isOn: $processing.sonioxContext)
                        Button("용어…") { terms = true }.disabled(!processing.sonioxContext)
                            .popover(isPresented: $terms) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("회의 공통 용어 · Soniox/Qwen · 한 줄에 하나씩").font(.headline)
                                    TextEditor(text: $workspace.meetingTerms).frame(width: 340, height: 140)
                                    Text("맥락·참석자·예상 발화자 수와 함께 전송합니다. 폴더 발췌는 별도 선택하며, 전송 전에 전체 내용을 확인할 수 있습니다.").font(.caption).frame(width: 340)
                                    Button("완료") { terms = false }
                                }.padding(16)
                            }
                    }
                    Spacer(minLength: 0)
                }
                if processing.selectedProvider.usesSoniox {
                    HStack {
                        Toggle("참고 폴더 발췌 추가", isOn: $processing.sonioxFolderContext).disabled(!processing.sonioxContext)
                        Text("기본 문맥: 맥락·참석자·예상 인원·직접 입력 참고·용어. 폴더는 남은 용량 안에서 선택합니다.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if processing.selectedProvider == .qwen {
                    HStack {
                        Text(processing.qwenReady ? "로컬 엔진 준비됨 · 한국어 · AI 교정 OFF" : "로컬 엔진 설치 필요").font(.caption)
                        Button("엔진 연결…") { processing.chooseQwenRuntime() }
                        Toggle("참고 폴더 로컬 입력",isOn:$processing.qwenFolderContext)
                        TextField("회의 공통 용어",text:$workspace.meetingTerms).textFieldStyle(.roundedBorder).frame(maxWidth:280)
                    }
                    Text("전사·정렬은 이 Mac에서 처리합니다. 화자 분리는 Precision-2를 사용하며, 같은 오디오·인원 설정의 결과가 있으면 재사용합니다.").font(.caption).foregroundStyle(.secondary)
                }
                Text("새 변환·재전사에 적용합니다. 재개는 원래 엔진으로 계속하며, 이전 스크립트는 별도로 보존합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 10).disabled(processing.busy || !workspace.canLeave)
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 250)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            let issues = LibraryFolder.allCases.flatMap { workspace.scanIssues[$0] ?? [] } + processing.scanIssues
            if !issues.isEmpty {
                Divider()
                DisclosureGroup("읽지 못한 파일·폴더 \(issues.count)개") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(issues) { issue in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.url.path).textSelection(.enabled)
                                    Text(issue.reason.message).foregroundStyle(.secondary)
                                    if issue.sessionID != nil { Text("이 녹음은 처리 이력을 확인할 때까지 제출·재개가 보류됩니다.").foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.font(.caption)
                    }.frame(maxHeight: 140)
                }.padding(12)
            }
            if let message = workspace.message ?? correction.message ?? playbackMessage ?? processing.message ?? capture.message ?? recording.message {
                Divider()
                HStack(alignment: .top) {
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("닫기") { workspace.message = nil; correction.message = nil; workspace.playback.message = nil; processing.message = nil; recording.message = nil }
                }.padding(12).background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(LibraryWindowGuard(workspace: workspace))
        .onAppear { workspace.start() }
        .onReceive(workspace.playback.$playingID.removeDuplicates()) { playingID = $0 }
        .onReceive(workspace.playback.$message.removeDuplicates()) { playbackMessage = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !workspace.notesDirty { workspace.refresh() }
        }
        .sheet(isPresented: $settings) { LibrarySettings(workspace: workspace) }
        .sheet(item: $edit, onDismiss: { workspace.editing = false }) { item in
            LibraryEditSheet(edit: item, workspace: workspace)
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(workspace.folder.rawValue).font(.headline); Spacer(); Text("최신순").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if workspace.folder == .speeches {
                        ForEach(workspace.speeches) { speech in
                            VStack(alignment: .leading, spacing: 9) {
                                Button { workspace.selectSpeech(speech.id) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(speech.title).font(.body.weight(.medium)).lineLimit(2)
                                        Text(date(speech.recordedAt)).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                let complete = workspace.completedScript(for: speech)
                                if processing.activeSessionID == speech.id || workspace.preparingSpeechID == speech.id {
                                    HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("변환 중").font(.caption).foregroundStyle(.secondary) }
                                } else { Button {
                                    if let complete { workspace.selectScript(complete.id) } else { workspace.selectSpeech(speech.id) }
                                } label: {
                                    Label(complete == nil ? "변환필요" : "변환완료", systemImage: complete == nil ? "circle.fill" : "checkmark.circle.fill")
                                        .font(.caption2).foregroundStyle(complete == nil ? Color.red : Color.green)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background((complete == nil ? Color.red : Color.green).opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                                }.buttonStyle(.plain) }
                            }.padding(12).background(workspace.selectedSpeechID == speech.id ? Color(nsColor: .textBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contextMenu {
                                    Button("Speech 삭제…", role: .destructive) { workspace.deleteSpeech(speech) }.disabled(workspace.foldersLocked)
                                }
                        }
                    } else {
                        ForEach(workspace.scripts) { file in
                            Button { workspace.selectScript(file.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(file.script.title).font(.body.weight(.medium)).lineLimit(2)
                                    Text(date(file.script.createdAt)).font(.caption).foregroundStyle(.secondary)
                                    Text(file.script.transcript.provenance.engine.title).font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(workspace.selectedScriptID == file.id ? Color(nsColor: .textBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                                .contextMenu {
                                    Button("재전사…") { workspace.retranscribeScript(file) }.disabled(!workspace.canRetranscribe(file.script.transcript.sessionId))
                                    Button("Script 삭제…", role: .destructive) { workspace.deleteScript(file) }.disabled(workspace.foldersLocked)
                                }
                        }
                    }
                }.padding(.horizontal, 4)
            }.disabled(!workspace.canLeave)
            Spacer(minLength: 0)
            Button("목록 새로고침", systemImage: "arrow.clockwise", action: workspace.refresh).buttonStyle(.plain).font(.caption).disabled(!workspace.canLeave).padding(.leading, 12)
            Divider()
            ForEach(LibraryFolder.allCases) { kind in
                HStack {
                    Button { workspace.selectFolder(kind) } label: {
                        Label(kind.rawValue, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }.buttonStyle(.plain)
                    Menu {
                        Button("폴더 선택…") { workspace.chooseFolder(kind) }.disabled(workspace.foldersLocked)
                        Button("Finder에서 열기") { workspace.revealFolder(kind) }.disabled(workspace.folders[kind] == nil)
                    } label: { Image(systemName: "chevron.down") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("\(kind.rawValue) 폴더 메뉴")
                }.background(workspace.folder == kind ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
        }.padding(12).padding(.top, 10).background(Color(nsColor: .controlBackgroundColor))
    }
    @ViewBuilder private var detail: some View {
        if workspace.folders[workspace.folder] == nil {
            if workspace.needsDefaultFolderAccess {
                VStack(spacing: 16) {
                    Text("DAMA 기본 폴더").font(.title2)
                    Text(workspace.defaultFolderDescription).foregroundStyle(.secondary)
                    Button("기본 폴더 사용", action: workspace.authorizeDefaultFolders).buttonStyle(.borderedProminent)
                    Button("다른 폴더 선택…") { workspace.chooseFolder(workspace.folder) }
                }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                empty("\(workspace.folder.rawValue) 폴더를 선택해 주세요.", message: "녹음과 스크립트를 보관할 위치를 지정합니다.") {
                    workspace.chooseFolder(workspace.folder)
                }
            }
        } else if workspace.folder == .speeches {
            if let speech = workspace.speech { speechDetail(speech) }
            else { empty("녹음 파일이 없습니다.", message: "메뉴바에서 녹음을 시작하거나 이 폴더에 M4A·WAV 파일을 넣어 주세요.", action: nil) }
        } else if let file = workspace.scriptFile { scriptDetail(file) }
        else { empty("아직 스크립트가 없습니다.", message: "Speeches에서 녹음을 선택해 변환하세요.", action: nil) }
    }
    private func empty(_ title: String, message: String, action: (() -> Void)?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "folder").font(.system(size: 36)).foregroundStyle(.secondary)
            Text(title).font(.title2)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action { Button("폴더 선택…", action: action) }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func speechDetail(_ speech: LibrarySpeech) -> some View {
        let run = processing.run(for: speech.id)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Speeches").font(.caption).foregroundStyle(.secondary)
                Text(speech.title).font(.title)
                Text("\(date(speech.recordedAt)) · \(LibraryScript.timestamp(speech.durationUs))").font(.callout).foregroundStyle(.secondary)
                Text(speech.dateSource).font(.caption2).foregroundStyle(.secondary)
            }.padding(32)
            Divider()
            if run != nil || processing.activeSessionID == speech.id || workspace.preparingSpeechID == speech.id {
                ProcessingProgressCard(run: run, tracking: processing.activeSessionID == speech.id,
                    preparing: workspace.preparingSpeechID == speech.id,
                    startedAt: processing.activeSessionID == speech.id ? processing.attemptStartedAt : nil,
                    scriptSaved: run.map { value in workspace.scripts.contains { $0.id == value.id } } ?? false)
                    .padding(.horizontal, 32).padding(.vertical, 16)
                if processing.activeSessionID == speech.id, run?.provider == .qwen {
                    Button("로컬 전사 일시 정지", action: processing.pause)
                        .padding(.horizontal, 32).padding(.bottom, 12)
                }
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("예상 발화자 수").fontWeight(.medium)
                        TextField("자동", text: $workspace.speakerCount).textFieldStyle(.roundedBorder).frame(width: 150).accessibilityLabel("예상 발화자 수").disabled(!workspace.canLeave)
                        Text(workspace.notesValid ? (processing.selectedProvider.usesSoniox ? "기본 문맥을 켜면 예상 인원을 Soniox에 힌트로 전송합니다 (1~15명). 인원을 강제하지 않습니다." : "입력한 인원을 pyannote 화자 수 제약으로 전달합니다. 비워 두면 자동 판단합니다.") : "1 이상의 정수를 입력해 주세요.")
                            .font(.caption).foregroundStyle(workspace.notesValid ? Color.secondary : Color.red)
                    }
                    Text("실제로 말한 인원을 아는 경우에만 지정하세요. 운영 결합은 Precision-2 제약과 Soniox 힌트를 함께 사용합니다.").font(.caption).foregroundStyle(.secondary)
                    noteField("맥락", text: $workspace.context, height: 90)
                    noteField("참석자 · 한 줄에 이름과 소속/역할", text: $workspace.participants, height: 70)
                    noteField("참고 정보", text: $workspace.reference, height: 80)
                    Text("용어 표기를 지정하려면 ‘용어 | 주제 | 원표기 | 표준표기’를 한 줄씩 입력하세요. 맥락과 해당 발화에서 주제가 확인되는 경우에 적용합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("변환 후 문맥 자동 교정", isOn: Binding(get: { correction.automatic && !processing.comparison && ![.sonioxPrecision, .qwen].contains(processing.selectedProvider) }, set: { correction.automatic = $0 }))
                        .disabled(processing.comparison || [.sonioxPrecision, .qwen].contains(processing.selectedProvider))
                    HStack {
                        Text(correction.referenceURL?.lastPathComponent ?? "참고 폴더 없음").font(.caption).foregroundStyle(.secondary)
                        Button("참고 폴더 연결…", action: correction.chooseReferences).disabled(correction.busy)
                        if correction.referenceURL != nil { Button("연결 해제", action: correction.disconnectReferences).disabled(correction.busy) }
                    }
                    Text("자동 교정 시 참석자·맥락·참고 정보를 활용합니다. 전송할 참고 발췌는 변환 확인창에서 볼 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                    if processing.localOnly.contains(speech.id) { Text("이 녹음은 로컬 저장만 하도록 설정되어 있습니다.").font(.callout) }
                }.padding(32)
            }
            Divider()
            HStack {
                Button(workspace.notesDirty ? "정보 저장" : "정보 저장됨", action: workspace.saveNotes).disabled(!workspace.notesDirty || !workspace.notesValid || !workspace.canLeave)
                Button("삭제…", systemImage: "trash") { workspace.deleteSpeech(speech) }.disabled(workspace.foldersLocked)
                Spacer()
                if workspace.folders[.scripts] == nil { Button("Scripts 폴더 선택…") { workspace.chooseFolder(.scripts) } }
                if run != nil || workspace.completedScript(for: speech) != nil {
                    Button("재전사…", action: workspace.retranscribeSpeech).disabled(!workspace.canRetranscribe(speech.id))
                }
                Button(conversionTitle(speech, run: run), action: workspace.convert)
                    .buttonStyle(.borderedProminent)
                    .disabled(!workspace.canLeave || !workspace.notesValid || processing.busy || workspace.folders[.scripts] == nil || processing.localOnly.contains(speech.id))
            }.padding(24)
        }
    }
    private func conversionTitle(_ speech: LibrarySpeech, run: ManagedRun?) -> String {
        if processing.activeSessionID == speech.id { return "변환 중…" }
        if workspace.preparingSpeechID == speech.id { return "오디오 준비 중…" }
        if let run {
            if run.stage == "readyForReview" { return workspace.scripts.contains { $0.id == run.id } ? "스크립트 열기" : "스크립트 저장" }
            return processing.canResume(run) ? "변환 재개" : "처리 상태 확인"
        }
        return workspace.completedScript(for: speech) != nil ? "스크립트 열기" : "변환"
    }
    private func noteField(_ label: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).fontWeight(.medium)
            ExactTextEditor(text: text, label: label).frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        }.disabled(!workspace.canLeave)
    }
    private func beginEdit(_ item: LibraryEdit) { guard workspace.canLeave else { return }; workspace.editing = true; edit = item }
    private func scriptDetail(_ file: LibraryScriptFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Scripts").font(.caption).foregroundStyle(.secondary)
                    Text("스크립트").font(.title)
                    Button { beginEdit(LibraryEdit(file: file, kind: .title, value: file.script.title)) } label: {
                        Label(file.script.title, systemImage: "pencil").font(.headline)
                    }.buttonStyle(.plain).accessibilityLabel("스크립트 제목 수정")
                    Text(date(file.script.recordedAt)).font(.caption).foregroundStyle(.secondary)
                    Text("생성 \(file.script.createdAt.formatted(date: .numeric, time: .standard))").font(.caption).foregroundStyle(.secondary)
                    Text("\(file.script.transcript.provenance.engine.title) · \(file.script.transcript.provenance.asrModel)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("재전사…") { workspace.retranscribeScript(file) }.disabled(!workspace.canRetranscribe(file.script.transcript.sessionId))
                Button("삭제…", systemImage: "trash") { workspace.deleteScript(file) }.disabled(workspace.foldersLocked)
                Button("내보내기", systemImage: "square.and.arrow.up", action: workspace.exportMarkdown).disabled(!workspace.canLeave)
            }.padding(32)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Menu("같은 원음 결과 비교") {
                            ForEach(workspace.scripts.filter { $0.script.transcript.provenance.sourceAudioSHA256 != nil && $0.script.transcript.provenance.sourceAudioSHA256 == file.script.transcript.provenance.sourceAudioSHA256 }) { other in
                                Button("\(other.id == file.id ? "✓ " : "")\(other.script.transcript.provenance.engine.title) · \(other.script.createdAt.formatted(date: .omitted, time: .standard))") { workspace.selectScript(other.id) }
                            }
                        }.fixedSize().disabled(!workspace.canLeave)
                        Button("평가 내보내기", action: workspace.exportEvaluation).disabled(!workspace.canLeave)
                        Spacer()
                    }.padding(.bottom, 12)
                    Text(file.script.reviewSummary).font(.caption).foregroundStyle(.secondary)
                    Text("경고가 없는 구간도 미검수입니다. 문제 구간과 무작위 정상 표본을 함께 확인하세요.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
                    DisclosureGroup("검수 사건 \(file.reading.reviewEvents.count)개") {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(file.reading.reviewEvents) { event in
                                    HStack(alignment: .top) {
                                        Button("\(LibraryScript.timestamp(event.startUs)) 원음") { workspace.play(event, file: file) }
                                            .disabled(capture.phase.busy || event.startUs == nil || event.endUs == nil)
                                        Text(event.kinds.map { issueLabel($0) }.joined(separator: " · ")).font(.caption)
                                    }
                                }
                            }
                        }.frame(maxHeight: 220)
                    }.padding(.bottom, 12)
                    DisclosureGroup("사용자 검수 이력") {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach((file.script.reviewRecords ?? []).reversed()) { record in
                                    VStack(alignment: .leading) {
                                        Text("\(record.error.title) · \(record.sample.title) · 원음 \(record.audioChecked ? "확인" : "미확인")")
                                        Text("\(record.recordedAt.formatted()) · \(record.activeSeconds.map { String(format: "%.1f초", $0) } ?? "시간 미측정")")
                                        ForEach(record.turns, id: \.turnID) { turn in
                                            Text("\(LibraryScript.timestamp(turn.startUs)) [\(turn.beforeName)] \(turn.beforeText) → [\(turn.afterName)] \(turn.afterText)")
                                        }
                                        if !record.note.isEmpty { Text(record.note) }
                                    }.font(.caption).textSelection(.enabled)
                                }
                            }
                        }.frame(maxHeight: 200)
                    }.padding(.bottom, 18)
                    correctionHeader(file).padding(.bottom, 18)
                    Text(file.reading.speakerCountSummary)
                        .font(.callout).foregroundStyle(file.reading.speakerCountMismatch ? Color.orange : Color.secondary)
                    Text(file.script.speakerCountApplication).font(.caption).foregroundStyle(.secondary).padding(.bottom, 18)
                    DisclosureGroup("녹음·변환 정보") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("녹음: \(date(file.script.recordedAt)) · \(file.script.timeZoneID)")
                            Text(file.script.dateSource)
                            Text("Run: \(file.script.transcript.runId)")
                            Text("전사 문맥: \(file.script.input.transcriptionContextSummary)")
                            Text("결합/정규화: \(file.script.transcript.provenance.algorithmVersion)")
                            if let source = file.script.input.sonioxSourceRunID { Text("Soniox 원본 Run: \(source)") }
                            if let source = file.script.input.precisionSourceRunID { Text("Precision-2 원본 Run: \(source)") }
                            if let source=file.script.input.qwenDiarizationRunID { Text("화자 분리 재사용 Run: \(source)") }
                            Text("예상 발화자 수: \(file.script.input.speakerCount.map(String.init) ?? "자동 (미입력)")")
                            Text("문단 표시: \(ScriptReadingPolicy.algorithmVersion)")
                            Text("참석자: \(file.script.input.participants ?? "미입력")")
                            Text("맥락: \(file.script.input.context.isEmpty ? "미입력" : file.script.input.context)")
                            Text("참고 정보: \(file.script.input.reference.isEmpty ? "미입력" : file.script.input.reference)")
                        }.font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }.padding(.bottom, 18)
                    ForEach(file.reading.blocks) { block in
                        ScriptBlockRow(block: block,
                            rename: { beginEdit(LibraryEdit(file: file, kind: .speaker(block), value: block.name)) },
                            editText: { beginEdit(LibraryEdit(file: file, kind: .text(block), value: block.text)) },
                            editParagraphs: { beginEdit(LibraryEdit(file: file, kind: .paragraphs(block), value: "")) },
                            review: { beginEdit(LibraryEdit(file: file, kind: .review(block), value: "")) },
                            play: { workspace.play(block, file: file) },
                            playing: playingID == file.id + ":" + block.id,
                            canPlay: !capture.phase.busy && block.startUs != nil && block.endUs != nil,
                            playEvent: { workspace.play($0, file: file) },
                            playingEventID: block.reviewEvents.first { playingID == file.id + ":event:" + $0.id }?.id,
                            corrections: file.script.correction?.visibleEdits.filter { block.turnIDs.contains($0.turnID) } ?? [],
                            resolvedTurnIDs: Set(file.script.turnTexts.keys),
                            resolveCorrection: { edit, apply in workspace.resolveCorrection(edit, apply: apply, file: file) })
                            .padding(.vertical, 9)
                    }
                }.padding(.horizontal, 32).padding(.vertical, 20)
            }
        }
    }
    private func date(_ date: Date?) -> String { date?.formatted(date: .numeric, time: .shortened) ?? "녹음 날짜 미확인" }
    private func correctionHeader(_ file: LibraryScriptFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if correction.activeID == file.id {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("문맥 교정 중 · \(correction.total > 0 ? correction.completed * 100 / correction.total : 0)% · \(correction.completed)/\(correction.total) 구간 완료")
                    Spacer(); Button("교정 중단", action: correction.cancel)
                }
                if correction.total > 0 { ProgressView(value: Double(correction.completed), total: Double(correction.total)) }
            } else {
                HStack {
                    if let saved = file.script.correction {
                        Text(saved.state == .completed ? "AI 문맥 교정 완료" : "AI 교정 미완료 · 원문 사용 가능").font(.callout)
                        if saved.state == .completed {
                            Button(file.script.showsOriginal == true ? "교정본 보기" : "교정 전 보기") { workspace.toggleOriginal(file) }.disabled(!workspace.canLeave)
                        }
                    } else { Text("맥락과 참석자 정보를 활용해 표기를 교정할 수 있습니다.").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(file.script.correction == nil ? "AI 교정" : "다시 교정") { correction.review(file) }.disabled(correction.busy || !workspace.canLeave)
                }
            }
        }
    }
}

struct LibrarySettings: View {
    @ObservedObject var workspace: LibraryWorkspace
    @ObservedObject private var correction = CorrectionWorkspace.shared
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var capture = RecordingWorkspace.shared.capture
    @State private var costSettings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DAMA 설정").font(.title2)
            ForEach(LibraryFolder.allCases) { kind in
                HStack {
                    VStack(alignment: .leading) { Text(kind.rawValue).fontWeight(.medium); Text(workspace.folders[kind]?.path ?? "선택되지 않음").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                    Menu("선택") {
                        Button("폴더 선택…") { workspace.chooseFolder(kind) }.disabled(workspace.foldersLocked)
                        Button("Finder에서 열기") { workspace.revealFolder(kind) }.disabled(workspace.folders[kind] == nil)
                    }.fixedSize()
                }
            }
            Button("내부에 보존된 녹음을 Speeches에 저장", action: workspace.recoverRecordings).disabled(workspace.foldersLocked || workspace.folders[.speeches] == nil)
            if capture.needsFinalization {
                Button("녹음 저장 다시 시도") { Task { _ = await capture.retryFinalization() } }
            }
            Divider()
            APIKeySettings()
            Divider()
            Button("월 비용·무료 혜택 기록…") { costSettings = true }
            Text("문맥 교정 · Codex CLI").font(.headline)
            Text(correction.executable.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button("Codex 실행 파일 선택…", action: correction.chooseExecutable).disabled(correction.busy)
            Text("이 Mac에 설치·로그인된 Codex를 사용합니다. CLI 실행과 계정 접근은 앱 권한에 따라 제한될 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 470)
            .sheet(isPresented: $costSettings) { OperatingCostSheet(workspace: workspace) }
    }
}

struct LibraryEdit: Identifiable {
    enum Kind { case title, speaker(ScriptBlock), text(ScriptBlock), paragraphs(ScriptBlock), review(ScriptBlock) }
    let id = UUID()
    let file: LibraryScriptFile
    let kind: Kind
    let value: String
}

struct OperatingCostSheet: View {
    @ObservedObject var workspace: LibraryWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var cost: MonthlyOperatingCost
    @State private var values: [String: String]
    @State private var error: String?
    private static let fields: [(String, WritableKeyPath<MonthlyOperatingCost, Double?>)] = [
        ("pyannote 정상 월 구독료", \.normalSubscriptionUSD), ("pyannote 포함 크레딧", \.includedCreditUSD),
        ("pyannote 정상 단가 사용액", \.precisionUsageUSD), ("Soniox 정상 단가 사용액", \.sonioxUsageUSD),
        ("기타 현금 비용", \.otherCostUSD), ("실제 청구 합계", \.actualBilledUSD), ("TIRO 등 실제 비교 청구액", \.referenceBillUSD)]
    init(workspace: LibraryWorkspace) {
        self.workspace = workspace
        let saved = workspace.monthlyCost
        _cost = State(initialValue: saved)
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: Self.fields.map { ($0.0, saved[keyPath: $0.1].map { String($0) } ?? "") }))
    }
    private func parsed() throws -> MonthlyOperatingCost {
        var result = cost
        for (label, path) in Self.fields {
            let text = (values[label] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { result[keyPath: path] = nil }
            else {
                guard let value = Double(text), value.isFinite, value >= 0 else { throw LibraryFailure.invalidInput }
                result[keyPath: path] = value
            }
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("월 비용·무료 혜택 기록").font(.title2)
            Text("USD · 계정 대시보드/청구서 기준 수동 입력. 빈칸은 미측정이며, 확인한 무료 청구액만 0으로 입력하세요.").font(.caption)
            TextField("대상 월 (YYYY-MM)", text: $cost.month).textFieldStyle(.roundedBorder)
            ForEach(Self.fields, id: \.0) { label, _ in
                HStack {
                    Text(label).frame(width: 210, alignment: .leading)
                    TextField("미입력", text: Binding(get: { values[label] ?? "" }, set: { values[label] = $0 })).textFieldStyle(.roundedBorder)
                }
            }
            Text("정상 월 비용 = 구독료 + max(0, pyannote 사용액 − 포함 크레딧) + Soniox 사용액 + 기타 비용").font(.caption)
            Text((try? parsed().normalTotalUSD).map { String(format: "혜택 종료 후 정상 월 비용: $%.2f", $0) } ?? "혜택 종료 후 정상 월 비용: 미측정").font(.headline)
            TextField("무료 혜택 종료일 (확인 전은 빈칸)", text: $cost.trialEnds).textFieldStyle(.roundedBorder)
            TextField("무료 포함량·조건", text: $cost.trialAllowance).textFieldStyle(.roundedBorder)
            TextField("청구서/단가 근거·기록일·재처리 사용량 메모", text: $cost.evidence).textFieldStyle(.roundedBorder)
            Text("새 달의 기록은 해당 월 평가 JSON으로 내보낸 뒤 교체하세요. 구독을 유지하면 호출을 줄여도 고정비가 남습니다. 미입력 값을 공개 가격으로 자동 채우지 않습니다.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer(); Button("취소") { dismiss() }
                Button("비용 기록 저장") {
                    do { try workspace.saveMonthlyCost(parsed()); dismiss() }
                    catch { self.error = "금액은 0 이상의 숫자 또는 빈칸으로 입력하세요." }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
}
struct LibraryEditSheet: View {
    let edit: LibraryEdit
    @ObservedObject var workspace: LibraryWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var texts: [String: String]
    @State private var breaks: [String: String] = [:]
    @State private var scope: SpeakerNameScope = .all
    @State private var audioChecked = false
    @State private var reviewError: ReviewError = .unclassified
    @State private var sample: ReviewSample = .unclassified
    @State private var reviewNote = ""
    @State private var elapsed: Double?
    @State private var timerStarted: Date?
    @State private var error: String?
    init(edit: LibraryEdit, workspace: LibraryWorkspace) {
        self.edit = edit; self.workspace = workspace; _value = State(initialValue: edit.value)
        if case let .text(block) = edit.kind {
            _texts = State(initialValue: Dictionary(uniqueKeysWithValues: block.turns.map { ($0.id, edit.file.script.text(for: $0)) }))
        } else { _texts = State(initialValue: [:]) }
        if case let .paragraphs(block) = edit.kind {
            _breaks = State(initialValue: Dictionary(uniqueKeysWithValues: block.turns.map { turn in
                (turn.id, edit.file.script.paragraphBreaks?[turn.id].map { $0 ? "split" : "join" } ?? "auto")
            }))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2)
            if case let .text(block) = edit.kind {
                if block.turns.count > 1 { Text("한 문단으로 표시되는 대화입니다. 원래 시간 구간별로 수정할 수 있습니다.").font(.caption).foregroundStyle(.secondary) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(block.turns, id: \.id) { turn in
                            Text("\(LibraryScript.timestamp(turn.startUs)) – \(LibraryScript.timestamp(turn.endUs))").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            ExactTextEditor(text: Binding(get: { texts[turn.id] ?? "" }, set: { texts[turn.id] = $0 }), label: "대사 수정")
                                .frame(height: 100).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        }
                    }
                }.frame(maxHeight: 320)
                DisclosureGroup("모델 원문 보기") {
                    ScrollView { Text(block.turns.map { edit.file.script.modelText(for: $0) }.joined(separator: "\n")).textSelection(.enabled) }.frame(maxHeight: 120)
                }
                Text("모델 원문은 보존됩니다. 시간은 재정렬하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            } else if case let .review(block) = edit.kind {
                ScrollView { Text(block.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120)
                Text("선택한 원 발화 범위에 대해 기록합니다. 내용 수정 없이 정상 표본도 남길 수 있습니다.").font(.caption)
            } else if case let .paragraphs(block) = edit.kind {
                Text("아래 발화 앞에서 문단을 나누거나 앞 문단과 합칠 수 있습니다. 다른 화자·미확정·누락 경계는 유지합니다.").font(.caption)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(block.turns, id: \.id) { turn in
                            Text(LibraryScript.timestamp(turn.startUs)).font(.caption).foregroundStyle(.secondary)
                            Text(edit.file.script.text(for: turn)).font(.callout).textSelection(.enabled)
                            Picker("이 발화 앞 경계", selection: Binding(get: { breaks[turn.id] ?? "auto" }, set: { breaks[turn.id] = $0 })) {
                                Text("자동").tag("auto")
                                Text("새 문단").tag("split")
                                if edit.file.script.canJoinParagraph(before: turn.id) { Text("앞 문단과 합치기").tag("join") }
                            }
                            Divider()
                        }
                    }
                }.frame(maxHeight: 340)
                Text("원문·문장부호·시간·화자 정보는 바꾸지 않습니다. ‘자동’을 선택하면 수동 경계를 해제합니다.").font(.caption).foregroundStyle(.secondary)
            } else {
                ExactTextEditor(text: $value, label: title).frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
            if case let .speaker(block) = edit.kind {
                Picker("적용 범위", selection: $scope) {
                    Text("이 부분만 바꾸기").tag(SpeakerNameScope.one)
                    Text("이 부분부터 바꾸기").tag(SpeakerNameScope.from)
                    Text("전체 바꾸기").tag(SpeakerNameScope.all)
                }.pickerStyle(.radioGroup)
                Text("\(edit.file.script.affectedTurns(in: block, scope: scope).count)개 원 발화에 적용됩니다.").font(.caption).foregroundStyle(.secondary)
            }
            if let block = reviewBlock {
                Button("선택 구간 원음 재생·정지") { workspace.play(block, file: edit.file) }
                    .disabled(RecordingWorkspace.shared.capture.phase.busy || block.startUs == nil || block.endUs == nil)
                Toggle("기록할 전체 범위를 원음으로 확인함", isOn: $audioChecked)
                Picker("오류 유형", selection: $reviewError) {
                    ForEach(ReviewError.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("표본 유형", selection: $sample) {
                    ForEach(ReviewSample.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("검수 메모 · 용어·숫자·부정·조건 등", text: $reviewNote).textFieldStyle(.roundedBorder)
                HStack {
                    Button(timerStarted == nil ? "능동 시간 측정 시작" : "시간 측정 일시 정지") {
                        if timerStarted == nil { timerStarted = Date(); if elapsed == nil { elapsed = 0 } }
                        else { pauseTimer() }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        Text(elapsed.map { String(format: "%.0f초", $0 + (timerStarted.map { tick.date.timeIntervalSince($0) } ?? 0)) } ?? "미측정").font(.caption)
                    }
                }
                Text("다른 앱으로 전환하면 측정을 일시 정지합니다. 원음 미확인·윤문 기록은 학습 정답으로 자동 채택하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).disabled(workspace.busy)
                Button("수정 저장", action: save).keyboardShortcut(.defaultAction).disabled(workspace.busy || !valid)
            }
        }.padding(24).frame(width: 520).interactiveDismissDisabled()
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in pauseTimer() }
            .onDisappear { pauseTimer(); workspace.playback.stop() }
    }
    private var title: String { switch edit.kind { case .title: "스크립트 제목 수정"; case .speaker: "화자 이름 변경"; case .text: "대사 수정"; case .paragraphs: "문단 합치기·나누기"; case .review: "구간 검수 기록" } }
    private var valid: Bool { switch edit.kind { case .text, .paragraphs, .review: return reviewError != .noError || audioChecked; default: return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var reviewBlock: ScriptBlock? {
        switch edit.kind { case let .text(b), let .speaker(b), let .paragraphs(b), let .review(b): b; case .title: nil }
    }
    private func pauseTimer() {
        if let start = timerStarted { elapsed = (elapsed ?? 0) + max(0, Date().timeIntervalSince(start)); timerStarted = nil }
    }
    private func save() {
        pauseTimer()
        Task {
            do {
                var candidate = edit.file.script
                switch edit.kind {
                case .review: break
                case .title: try candidate.renameTitle(value)
                case let .speaker(block): try candidate.rename(block, name: value, scope: scope)
                case let .text(block):
                    for turn in block.turns where texts[turn.id] != edit.file.script.text(for: turn) {
                        try candidate.editText(turn.id, text: texts[turn.id] ?? "")
                    }
                case let .paragraphs(block):
                    for turn in block.turns {
                        let choice = breaks[turn.id] ?? "auto"
                        try candidate.setParagraphBreak(before: turn.id, split: choice == "auto" ? nil : choice == "split")
                    }
                }
                if let block = reviewBlock {
                    let ids: [String]
                    if case .speaker = edit.kind { ids = edit.file.script.affectedTurns(in: block, scope: scope) }
                    else { ids = block.turnIDs }
                    try candidate.recordReview(before: edit.file.script, turnIDs: ids, audioChecked: audioChecked,
                        error: reviewError, sample: sample, activeSeconds: elapsed, note: reviewNote)
                }
                try await workspace.saveScript(candidate, original: edit.file)
                dismiss()
            } catch { self.error = "수정을 저장하지 못했습니다. 외부 파일 변경 또는 폴더 권한을 확인해 주세요. 입력한 내용은 유지됩니다." }
        }
    }
}
