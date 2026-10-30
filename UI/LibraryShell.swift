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
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                Text("DAMA").font(.headline)
                if AudioFiles.uiFixtureFolder != nil { Text("합성 UI 검증").font(.caption).foregroundStyle(.orange) }
                Spacer()
                if correction.busy {
                    Text("AI 교정 중").font(.caption).foregroundStyle(.secondary)
                    Button("교정 중단", action: correction.cancel)
                }
                if capture.phase == .recording { Label("녹음 중 · \(LibraryScript.timestamp(capture.elapsedUs))", systemImage: "record.circle.fill").foregroundStyle(.red) }
                if workspace.busy || workspace.scriptsLoading || workspace.loadingScriptID != nil { ProgressView().controlSize(.small); Text("불러오거나 저장하는 중").font(.caption) }
                Button("설정", systemImage: "gearshape") { settings = true }
            }.padding(.horizontal, 20).frame(height: 48)
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
                                } else if !workspace.scriptsLoading { Button {
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
                        ForEach(workspace.primaryScripts) { file in
                            Button { workspace.selectScript(file.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(file.title).font(.body.weight(.medium)).lineLimit(2)
                                    Text(date(file.createdAt)).font(.caption).foregroundStyle(.secondary)
                                    Text(file.engine.title).font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(workspace.scriptGroupSelected(file) ? Color(nsColor: .textBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                                .contextMenu {
                                    Button("재전사…") { workspace.retranscribeScript(file) }.disabled(!workspace.canRetranscribe(file.sessionId))
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
                    }.buttonStyle(.plain).disabled(!workspace.canLeave)
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
            if let speech = workspace.speech { SpeechDetailView(speech: speech, workspace: workspace, settings: { settings = true }).id(speech.id) }
            else { empty("아직 녹음이 없습니다.", message: "메뉴바에서 녹음을 시작하거나 이 폴더에 M4A·WAV 파일을 넣어 주세요.", action: nil) }
        } else if let file = workspace.displayedScript {
            ScriptReadingView(file: file, workspace: workspace,
                rename: { file, block in beginEdit(LibraryEdit(file: file, kind: .speaker(block), value: block.name)) },
                correct: { file in
                    guard workspace.canLeave, !correction.busy else { return }
                    workspace.editing = true; aiRequest = ScriptAIRequest(file: file)
                })
                .id(file.id + (file.script.snapshotTitle == nil ? ":current" : ":" + file.script.revisionID))
        }
        else if workspace.scriptsLoading || workspace.loadingScriptID != nil {
            VStack(spacing: 12) { ProgressView(); Text("불러오거나 저장하는 중").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private func beginEdit(_ item: LibraryEdit) { guard workspace.canLeave else { return }; workspace.editing = true; edit = item }
    private func date(_ date: Date?) -> String { date?.formatted(date: .numeric, time: .shortened) ?? "녹음 날짜 미확인" }
}

struct LibrarySettings: View {
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system.rawValue
    @ObservedObject var workspace: LibraryWorkspace
    @ObservedObject private var correction = CorrectionWorkspace.shared
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var capture = RecordingWorkspace.shared.capture
    @State private var costSettings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DAMA 설정").font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text("화면 모드").font(.headline)
                Picker("화면 모드", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }.pickerStyle(.segmented).labelsHidden()
            }
            Divider()
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
            Text("문맥 교정 · Codex CLI · \(CodexCorrectionClient.modelTitle)").font(.headline)
            Text(correction.executable.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button("Codex 실행 파일 선택…", action: correction.chooseExecutable).disabled(correction.busy)
            Text("이 Mac에 설치·로그인된 Codex를 사용합니다. CLI 실행과 계정 접근은 앱 권한에 따라 제한될 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 470)
            .onChange(of: appearance) { _, _ in AppAppearance.applySaved() }
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
