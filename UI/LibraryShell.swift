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
        }
    }
}

struct LibraryShell: View {
    @ObservedObject var workspace: LibraryWorkspace
    @ObservedObject private var processing = ProcessingWorkspace.shared
    @ObservedObject private var recording = RecordingWorkspace.shared
    @ObservedObject private var capture = RecordingWorkspace.shared.capture
    @ObservedObject private var correction = CorrectionWorkspace.shared
    @ObservedObject private var playback = LibraryWorkspace.shared.playback
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
                        ForEach(TranscriptionProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.frame(width: 260)
                    Toggle("엔진 비교 · 자동 교정 끔", isOn: $processing.comparison)
                    if processing.selectedProvider == .soniox {
                        Toggle("맥락·참고 전송", isOn: $processing.sonioxContext)
                        Button("용어…") { terms = true }.disabled(!processing.sonioxContext)
                            .popover(isPresented: $terms) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Soniox 전사 용어 · 한 줄에 하나씩").font(.headline)
                                    TextEditor(text: $processing.sonioxTerms).frame(width: 340, height: 140)
                                    Text("선택한 녹음의 맥락·참고·참석자와 함께 전송합니다. 전송 전에 전체 내용을 확인할 수 있습니다.").font(.caption).frame(width: 340)
                                    Button("완료") { terms = false }
                                }.padding(16)
                            }
                    }
                    Spacer(minLength: 0)
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
            if let message = workspace.message ?? correction.message ?? playback.message ?? processing.message ?? capture.message ?? recording.message {
                Divider()
                HStack(alignment: .top) {
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("닫기") { workspace.message = nil; correction.message = nil; playback.message = nil; processing.message = nil; recording.message = nil }
                }.padding(12).background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(LibraryWindowGuard(workspace: workspace))
        .onAppear { workspace.start() }
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
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("총 참여 화자 수").fontWeight(.medium)
                        TextField("자동", text: $workspace.speakerCount).textFieldStyle(.roundedBorder).frame(width: 150).accessibilityLabel("총 참여 화자 수").disabled(!workspace.canLeave)
                        Text(workspace.notesValid ? (processing.selectedProvider == .soniox ? "Soniox는 화자 수를 자동 판단합니다. 이 입력은 녹음 정보로 보관합니다." : "비워 두면 자동으로 판단합니다.") : "1 이상의 정수를 입력해 주세요.")
                            .font(.caption).foregroundStyle(workspace.notesValid ? Color.secondary : Color.red)
                    }
                    noteField("맥락", text: $workspace.context, height: 90)
                    noteField("참석자 · 한 줄에 이름과 소속/역할", text: $workspace.participants, height: 70)
                    noteField("참고 정보", text: $workspace.reference, height: 80)
                    Text("용어 표기를 지정하려면 ‘용어 | 주제 | 원표기 | 표준표기’를 한 줄씩 입력하세요. 맥락과 해당 발화에서 주제가 확인되는 경우에 적용합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("변환 후 문맥 자동 교정", isOn: Binding(get: { correction.automatic && !processing.comparison }, set: { correction.automatic = $0 }))
                        .disabled(processing.comparison)
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
                    correctionHeader(file).padding(.bottom, 18)
                    DisclosureGroup("녹음·변환 정보") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("녹음: \(date(file.script.recordedAt)) · \(file.script.timeZoneID)")
                            Text(file.script.dateSource)
                            Text("Run: \(file.script.transcript.runId)")
                            Text("전사 문맥: \(file.script.input.sonioxContext == true ? "Soniox에 전송" : "미전송")")
                            Text("참여 화자 수: \(file.script.input.speakerCount.map(String.init) ?? "자동 (미입력)")")
                            Text("참석자: \(file.script.input.participants ?? "미입력")")
                            Text("맥락: \(file.script.input.context.isEmpty ? "미입력" : file.script.input.context)")
                            Text("참고 정보: \(file.script.input.reference.isEmpty ? "미입력" : file.script.input.reference)")
                        }.font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }.padding(.bottom, 18)
                    ForEach(file.script.blocks()) { block in
                        ScriptBlockRow(block: block,
                            rename: { beginEdit(LibraryEdit(file: file, kind: .speaker(block), value: block.name)) },
                            editText: { beginEdit(LibraryEdit(file: file, kind: .text(block), value: block.text)) },
                            play: { workspace.play(block, file: file) },
                            playing: playback.playingID == file.id + ":" + block.id,
                            canPlay: !capture.phase.busy && block.startUs != nil && block.endUs != nil,
                            playEvent: { workspace.play($0, file: file) },
                            playingEventID: block.reviewEvents.first { playback.playingID == file.id + ":event:" + $0.id }?.id,
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
            Text("문맥 교정 · Codex CLI").font(.headline)
            Text(correction.executable.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button("Codex 실행 파일 선택…", action: correction.chooseExecutable).disabled(correction.busy)
            Text("이 Mac에 설치·로그인된 Codex를 사용합니다. CLI 실행과 계정 접근은 앱 권한에 따라 제한될 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 470)
    }
}

struct LibraryEdit: Identifiable {
    enum Kind { case title, speaker(ScriptBlock), text(ScriptBlock) }
    let id = UUID()
    let file: LibraryScriptFile
    let kind: Kind
    let value: String
}
struct LibraryEditSheet: View {
    let edit: LibraryEdit
    @ObservedObject var workspace: LibraryWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var texts: [String: String]
    @State private var scope: SpeakerNameScope = .all
    @State private var error: String?
    init(edit: LibraryEdit, workspace: LibraryWorkspace) {
        self.edit = edit; self.workspace = workspace; _value = State(initialValue: edit.value)
        if case let .text(block) = edit.kind {
            _texts = State(initialValue: Dictionary(uniqueKeysWithValues: block.turns.map { ($0.id, edit.file.script.text(for: $0)) }))
        } else { _texts = State(initialValue: [:]) }
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
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).disabled(workspace.busy)
                Button("수정 저장", action: save).keyboardShortcut(.defaultAction).disabled(workspace.busy || !valid)
            }
        }.padding(24).frame(width: 500).interactiveDismissDisabled()
    }
    private var title: String { switch edit.kind { case .title: "스크립트 제목 수정"; case .speaker: "화자 이름 변경"; case .text: "대사 수정" } }
    private var valid: Bool { if case .text = edit.kind { return true }; return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func save() {
        Task {
            do {
                var candidate = edit.file.script
                switch edit.kind {
                case .title: try candidate.renameTitle(value)
                case let .speaker(block): try candidate.rename(block, name: value, scope: scope)
                case let .text(block):
                    for turn in block.turns where texts[turn.id] != edit.file.script.text(for: turn) {
                        try candidate.editText(turn.id, text: texts[turn.id] ?? "")
                    }
                }
                try await workspace.saveScript(candidate, original: edit.file)
                dismiss()
            } catch { self.error = "수정을 저장하지 못했습니다. 외부 파일 변경 또는 폴더 권한을 확인해 주세요. 입력한 내용은 유지됩니다." }
        }
    }
}
