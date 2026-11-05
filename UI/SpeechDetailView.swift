import DamaAudio
import DamaCore
import DamaManaged
import SwiftUI

struct SpeechDetailView: View {
    let speech: LibrarySpeech
    @ObservedObject var workspace: LibraryWorkspace
    let settings: () -> Void
    @ObservedObject private var processing = ProcessingWorkspace.shared
    @ObservedObject private var correction = CorrectionWorkspace.shared
    @State private var information = false
    @StateObject private var titleSession: SpeechTitleSession
    init(speech: LibrarySpeech, workspace: LibraryWorkspace, settings: @escaping () -> Void) {
        self.speech = speech; self.workspace = workspace; self.settings = settings
        _titleSession = StateObject(wrappedValue: SpeechTitleSession(speech: speech, workspace: workspace))
    }
    private var run: ManagedRun? { processing.run(for: speech.id) }
    private var provider: TranscriptionProvider { processing.selectedProvider }
    private var contextUsed: Bool { provider.consumesContext(sonioxEnabled: processing.sonioxContext) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speeches").font(.caption).foregroundStyle(.secondary)
                    // usage-bundle1: 녹음 제목 입력칸(스크립트 제목칸과 같은 부품). Enter·이탈 때만 인덱스에 저장.
                    InlineScriptText(text: $titleSession.title, editable: !workspace.editing, title: true, label: "녹음 제목",
                        changed: titleSession.changed, commit: titleSession.commit, cancel: titleSession.cancel)
                    HStack {
                        Text("\(speech.recordedAt?.formatted(date: .numeric, time: .shortened) ?? "녹음 날짜 미확인") · \(LibraryScript.timestamp(speech.durationUs))")
                        if let message = titleSession.message { Text("· \(message)") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Button("정보", systemImage: "info.circle") { information.toggle() }
            }.padding(28)
            .onChange(of: workspace.displayTitles) { _, _ in titleSession.receive(workspace.speechTitle(speech)) }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if workspace.scriptsLoading {
                        // Saved-Script state is unknown until the listing finishes.
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("불러오거나 저장하는 중").font(.headline) }
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    } else if run != nil || processing.activeSessionID == speech.id || workspace.preparingSpeechID == speech.id {
                        ProcessingProgressCard(run: run, tracking: processing.activeSessionID == speech.id,
                            preparing: workspace.preparingSpeechID == speech.id,
                            startedAt: processing.activeSessionID == speech.id ? processing.attemptStartedAt : nil,
                            scriptSaved: run.map { value in workspace.scripts.contains { $0.id == value.id } } ?? false,
                            retiredProvider: run.map(processing.isRetired) ?? false)
                        if run?.stage == "waitingForCredentials" { Button("API 키 설정", action: settings) }
                        if processing.activeSessionID == speech.id, run?.provider == .qwen { Button("로컬 전사 일시 정지", action: processing.pause) }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(workspace.completedScript(for: speech) == nil ? "변환할 준비가 되었습니다" : "저장된 스크립트가 있습니다").font(.headline)
                            Text(workspace.completedScript(for: speech) == nil ? "입력을 확인하고 변환을 시작하세요." : "연결된 스크립트를 열어 내용을 확인하세요.").font(.caption).foregroundStyle(.secondary)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text(provider == .sonioxNemotron ? "Soniox 전사 + Nemotron 3 화자 분리" : provider.title).font(.headline)
                    if provider.consumesSpeakerCount(sonioxEnabled: processing.sonioxContext) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("실제 화자 수 (선택)").fontWeight(.medium)
                            TextField("자동", text: $workspace.speakerCount).textFieldStyle(.roundedBorder).frame(width: 130).accessibilityLabel("실제 화자 수")
                            Text(workspace.notesValid ? countExplanation : "1 이상의 정수를 입력해 주세요.").font(.caption).foregroundStyle(workspace.notesValid ? Color.secondary : Color.red)
                        }.disabled(!workspace.canLeave)
                    }
                    if contextUsed {
                        noteField("맥락 (선택)", text: $workspace.context, height: 75)
                        noteField("참석자 (선택) · 이름과 소속/역할", text: $workspace.participants, height: 65)
                        DisclosureGroup("용어·참고") {
                            VStack(alignment: .leading, spacing: 18) {
                                noteField("회의 공통 용어 · 한 줄에 하나씩", text: $workspace.meetingTerms, height: 85)
                                noteField("직접 입력 참고", text: $workspace.reference, height: 85)
                                if provider.usesSoniox { Toggle("참고 폴더 발췌 추가", isOn: $processing.sonioxFolderContext) }
                                else { Toggle("참고 폴더 로컬 입력", isOn: $processing.qwenFolderContext) }
                                HStack {
                                    Text(correction.referenceURL?.lastPathComponent ?? "참고 폴더 없음").font(.caption).foregroundStyle(.secondary)
                                    Spacer(); Button("폴더 선택", action: correction.chooseReferences).disabled(correction.busy)
                                    if correction.referenceURL != nil { Button("연결 해제", action: correction.disconnectReferences).disabled(correction.busy) }
                                }
                                Text("Markdown·텍스트 파일의 일부를 선택합니다. \(provider == .qwen ? "로컬 입력" : "전송") 전에 포함된 내용을 확인할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                            }.padding(.top, 14)
                        }.disabled(!workspace.canLeave || processing.busy)
                    }
                    DisclosureGroup("새 전사 설정") {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("전사 엔진", selection: $processing.selectedProvider) {
                                ForEach(TranscriptionProvider.selectable, id: \.self) { Text($0.title).tag($0) }
                            }
                            if provider.usesSoniox { Toggle("기본 문맥 전송", isOn: $processing.sonioxContext) }
                            if provider == .sonioxNemotron {
                                HStack {
                                    if processing.modelStatus == .downloading { ProgressView().controlSize(.small) }
                                    Text(processing.modelStatusText).font(.caption)
                                    if [.missing, .failed, .mismatch].contains(processing.modelStatus) {
                                        Button(processing.modelStatus == .missing ? "모델 받기" : "다시 받기", action: processing.downloadModel)
                                    }
                                }
                                Text("화자 분리는 이 Mac에서 하며 음성을 전송하지 않습니다. 모델은 처음 한 번 Hugging Face에서 받습니다.").font(.caption).foregroundStyle(.secondary)
                            }
                            if provider == .qwen {
                                HStack {
                                    Text(processing.qwenReady ? "로컬 엔진 준비됨" : "로컬 엔진 설치 필요").font(.caption)
                                    Button("로컬 엔진 연결", action: processing.chooseQwenRuntime)
                                }
                                Text("전사·정렬과 참고 입력은 이 Mac에서 처리합니다. Precision-2 화자 분리 결과는 같은 오디오·인원 설정이면 재사용합니다.").font(.caption).foregroundStyle(.secondary)
                            }
                            Text("새 변환·재전사에 적용합니다. 재개는 저장된 원래 입력을 사용합니다. AI 검수/보정은 스크립트에서 실행할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 14)
                    }.disabled(!workspace.canLeave || processing.busy)
                    if information {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("녹음 정보").font(.headline)
                            Text(speech.dateSource).font(.caption).foregroundStyle(.secondary)
                            if let run { Text("현재 작업: \(run.provider.title) · \(processing.label(run))").font(.caption) }
                            HStack {
                                Button("새 입력으로 다시 전사", action: workspace.retranscribeSpeech).disabled(!workspace.canRetranscribe(speech.id))
                                Button("Speeches에서 삭제", role: .destructive) { workspace.deleteSpeech(speech) }.disabled(workspace.foldersLocked)
                            }
                        }
                    }
                    if processing.localOnly.contains(speech.id) { Text("이 녹음은 로컬 저장만 하도록 설정되어 있습니다.").font(.callout) }
                }.frame(maxWidth: 760, alignment: .leading).padding(28).frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Button(workspace.notesDirty ? "정보 저장" : "정보 저장됨", action: workspace.saveNotes).disabled(!workspace.notesDirty || !workspace.notesValid || !workspace.canLeave)
                Spacer()
                if workspace.folders[.scripts] == nil { Button("Scripts 폴더 선택") { workspace.chooseFolder(.scripts) } }
                Button(conversionTitle, action: workspace.convert).buttonStyle(.borderedProminent)
                    .disabled(!workspace.canLeave || workspace.scriptsLoading || !workspace.notesValid || processing.busy || workspace.folders[.scripts] == nil || processing.localOnly.contains(speech.id))
            }.padding(24)
        }
    }
    private var countExplanation: String {
        if provider == .sonioxNemotron {
            return "Nemotron 3에는 화자 수를 지정할 수 없습니다. 입력한 수는 스크립트 정보에서 감지 인원과 비교해 보여 줍니다." +
                (processing.sonioxContext ? " Soniox에는 1~15명 힌트로 전달합니다." : "")
        }
        if provider == .soniox { return "Soniox에 1~15명 힌트로 전달합니다. 인원을 강제하지 않습니다." }
        return "실제로 말한 인원을 알면 지정하세요. Precision-2에 화자 수 제약으로 전달합니다." + (provider.usesSoniox && processing.sonioxContext ? " Soniox에는 1~15명 힌트를 함께 보냅니다." : "")
    }
    private var conversionTitle: String {
        if processing.activeSessionID == speech.id { return "변환 중…" }
        if workspace.preparingSpeechID == speech.id { return "오디오 준비 중…" }
        if let run {
            if run.stage == "readyForReview" { return workspace.scripts.contains { $0.id == run.id } ? "스크립트 열기" : "스크립트 저장 다시 시도" }
            if processing.isRetired(run) { return "다시 전사…" }
            if processing.canResume(run) { return "변환 재개" }
            return run.canRetranscribe ? "다시 전사…" : "처리 상태 확인"
        }
        if workspace.completedScript(for: speech) != nil { return "스크립트 열기" }
        return [.sonioxPrecision, .sonioxNemotron].contains(provider) ? "결합본 만들기" : "변환하기"
    }
    private func noteField(_ label: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).fontWeight(.medium)
            ExactTextEditor(text: text, label: label).frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        }.disabled(!workspace.canLeave)
    }
}
