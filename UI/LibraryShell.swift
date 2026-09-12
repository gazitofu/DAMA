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
    @State private var aiRequest: ScriptAIRequest?
    @State private var settings = false
    @State private var terms = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
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
            SpeakerNameSheet(edit: item, workspace: workspace)
        }
        .sheet(item: $aiRequest, onDismiss: { workspace.editing = false }) { item in
            CorrectionInputSheet(request: item, workspace: workspace)
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
        } else if let file = workspace.displayedScript {
            ScriptReadingView(file: file, workspace: workspace,
                rename: { file, block in beginEdit(LibraryEdit(file: file, kind: .speaker(block), value: block.name)) },
                correct: { file in
                    guard workspace.canLeave, !correction.busy else { return }
                    workspace.editing = true; aiRequest = ScriptAIRequest(file: file)
                })
                .id(file.id + (file.script.snapshotTitle == nil ? ":current" : ":" + file.script.revisionID))
        }
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
    private func date(_ date: Date?) -> String { date?.formatted(date: .numeric, time: .shortened) ?? "녹음 날짜 미확인" }
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
    enum Kind { case speaker(ScriptBlock) }
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
