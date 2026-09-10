import AppKit
import DamaAudio
import DamaCore
import SwiftUI

struct LibraryShell: View {
    @ObservedObject var workspace: LibraryWorkspace
    @ObservedObject private var processing = ProcessingWorkspace.shared
    @ObservedObject private var recording = RecordingWorkspace.shared
    @ObservedObject private var capture = RecordingWorkspace.shared.capture
    @State private var edit: LibraryEdit?
    @State private var settings = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DAMA").font(.headline)
                Spacer()
                if capture.phase == .recording { Label("녹음 중 · \(LibraryScript.timestamp(capture.elapsedUs))", systemImage: "record.circle.fill").foregroundStyle(.red) }
                if workspace.busy { ProgressView().controlSize(.small); Text("불러오거나 저장하는 중").font(.caption) }
                Button("설정", systemImage: "gearshape") { settings = true }
            }.padding(.horizontal, 20).frame(height: 48)
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 250)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let message = workspace.message ?? processing.message ?? capture.message ?? recording.message {
                Divider()
                HStack(alignment: .top) {
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("닫기") { workspace.message = nil; processing.message = nil; recording.message = nil }
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
                                Button {
                                    if let complete { workspace.selectScript(complete.id) } else { workspace.selectSpeech(speech.id) }
                                } label: {
                                    Label(complete == nil ? "변환필요" : "변환완료", systemImage: complete == nil ? "circle.fill" : "checkmark.circle.fill")
                                        .font(.caption2).foregroundStyle(complete == nil ? Color.red : Color.green)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background((complete == nil ? Color.red : Color.green).opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                                }.buttonStyle(.plain)
                            }.padding(12).background(workspace.selectedSpeechID == speech.id ? Color(nsColor: .textBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    } else {
                        ForEach(workspace.scripts) { file in
                            Button { workspace.selectScript(file.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(file.script.title).font(.body.weight(.medium)).lineLimit(2)
                                    Text(date(file.script.createdAt)).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(workspace.selectedScriptID == file.id ? Color(nsColor: .textBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
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
            empty("\(workspace.folder.rawValue) 폴더를 선택해 주세요.", message: "녹음과 스크립트를 보관할 위치를 지정합니다.") {
                workspace.chooseFolder(workspace.folder)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("총 참여 화자 수").fontWeight(.medium)
                        TextField("자동", text: $workspace.speakerCount).textFieldStyle(.roundedBorder).frame(width: 150).accessibilityLabel("총 참여 화자 수").disabled(!workspace.canLeave)
                        Text(workspace.notesValid ? "비워 두면 자동으로 판단합니다." : "1 이상의 정수를 입력해 주세요.")
                            .font(.caption).foregroundStyle(workspace.notesValid ? Color.secondary : Color.red)
                    }
                    noteField("맥락", text: $workspace.context, height: 90)
                    noteField("참고 정보", text: $workspace.reference, height: 80)
                    Text("맥락·참고 정보는 로컬 참고 메모이며 Markdown 내보내기에 포함됩니다.").font(.caption).foregroundStyle(.secondary)
                    if let run { Text(processing.label(run)).font(.callout) }
                    if processing.localOnly.contains(speech.id) { Text("이 녹음은 로컬 저장만 하도록 설정되어 있습니다.").font(.callout) }
                }.padding(32)
            }
            Divider()
            HStack {
                Button(workspace.notesDirty ? "정보 저장" : "정보 저장됨", action: workspace.saveNotes).disabled(!workspace.notesDirty || !workspace.notesValid || !workspace.canLeave)
                Spacer()
                if workspace.folders[.scripts] == nil { Button("Scripts 폴더 선택…") { workspace.chooseFolder(.scripts) } }
                Button(workspace.completedScript(for: speech) != nil ? "스크립트 열기" : run?.stage == "readyForReview" ? "스크립트 저장" : run != nil ? "변환 재개" : "변환", action: workspace.convert)
                    .buttonStyle(.borderedProminent)
                    .disabled(!workspace.canLeave || !workspace.notesValid || processing.busy || workspace.folders[.scripts] == nil || processing.localOnly.contains(speech.id))
            }.padding(24)
        }
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
                }
                Spacer()
                Button("내보내기", systemImage: "square.and.arrow.up", action: workspace.exportMarkdown).disabled(!workspace.canLeave)
            }.padding(32)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    DisclosureGroup("녹음·변환 정보") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("녹음: \(date(file.script.recordedAt)) · \(file.script.timeZoneID)")
                            Text(file.script.dateSource)
                            Text("참여 화자 수: \(file.script.input.speakerCount.map(String.init) ?? "자동 (미입력)")")
                            Text("맥락: \(file.script.input.context.isEmpty ? "미입력" : file.script.input.context)")
                            Text("참고 정보: \(file.script.input.reference.isEmpty ? "미입력" : file.script.input.reference)")
                        }.font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }.padding(.bottom, 18)
                    ForEach(file.script.transcript.turns, id: \.id) { turn in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Button { beginEdit(LibraryEdit(file: file, kind: .speaker(turn.id), value: file.script.name(for: turn))) } label: {
                                    Label(file.script.name(for: turn), systemImage: "chevron.down").font(.callout.weight(.semibold))
                                }.buttonStyle(.plain)
                                Spacer()
                                Text("\(LibraryScript.timestamp(turn.startUs)) – \(LibraryScript.timestamp(turn.endUs))")
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            if turn.kind == .speech {
                                Button { beginEdit(LibraryEdit(file: file, kind: .text(turn.id), value: file.script.text(for: turn))) } label: {
                                    Text(file.script.text(for: turn).isEmpty ? "(빈 대사)" : file.script.text(for: turn))
                                        .font(.system(size: 17)).lineSpacing(7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("대사 수정: \(file.script.text(for: turn))")
                            } else { Text(file.script.text(for: turn)).foregroundStyle(.secondary) }
                            if file.script.turnTexts[turn.id] != nil { Text("사용자 수정 · 시간 재정렬 안 됨").font(.caption).foregroundStyle(.secondary) }
                            if !turn.reviewIssueIds.isEmpty {
                                DisclosureGroup("확인할 내용") {
                                    ForEach(file.script.transcript.reviewIssues.filter { turn.reviewIssueIds.contains($0.id) }, id: \.id) { issue in
                                        Text(issueLabel(issue.kind)).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 22)
                        Divider()
                    }
                }.padding(.horizontal, 32).padding(.vertical, 20)
            }
        }
    }
    private func date(_ date: Date?) -> String { date?.formatted(date: .numeric, time: .shortened) ?? "녹음 날짜 미확인" }
    private func issueLabel(_ kind: IssueKind) -> String {
        switch kind {
        case .ambiguous_speaker: "화자 미확정 · 후보가 비슷합니다."
        case .overlapping_speech: "동시에 여러 화자가 감지되었습니다. 두 사람의 발화가 모두 전사되었다는 뜻은 아닙니다."
        case .missing_speech: "[음성 감지 / 전사 누락 의심]"
        case .boundary_conflict: "단어 시간이 화자 전환 경계를 걸칩니다."
        case .capture_interrupted: "녹음이 중단되었습니다. 이후 구간은 녹음되지 않았을 수 있습니다."
        default: kind.rawValue
        }
    }
}

struct LibrarySettings: View {
    @ObservedObject var workspace: LibraryWorkspace
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
            HStack { Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 470)
    }
}

struct LibraryEdit: Identifiable {
    enum Kind { case title, speaker(String), text(String) }
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
    @State private var scope: SpeakerNameScope = .all
    @State private var error: String?
    init(edit: LibraryEdit, workspace: LibraryWorkspace) {
        self.edit = edit; self.workspace = workspace; _value = State(initialValue: edit.value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2)
            ExactTextEditor(text: $value, label: title).frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if case let .speaker(id) = edit.kind {
                Picker("적용 범위", selection: $scope) {
                    Text("이 부분만 바꾸기").tag(SpeakerNameScope.one)
                    Text("이 부분부터 바꾸기").tag(SpeakerNameScope.from)
                    Text("전체 바꾸기").tag(SpeakerNameScope.all)
                }.pickerStyle(.radioGroup)
                Text("\(edit.file.script.affectedTurns(id, scope: scope).count)개 발화에 적용됩니다.").font(.caption).foregroundStyle(.secondary)
            }
            if case let .text(id) = edit.kind, let turn = edit.file.script.transcript.turns.first(where: { $0.id == id }) {
                DisclosureGroup("모델 원문 보기") { Text(edit.file.script.modelText(for: turn)).textSelection(.enabled) }
                Text("모델 원문은 보존됩니다. 시간은 재정렬하지 않습니다.").font(.caption).foregroundStyle(.secondary)
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
                case let .speaker(id): try candidate.rename(id, name: value, scope: scope)
                case let .text(id): try candidate.editText(id, text: value)
                }
                try await workspace.saveScript(candidate, original: edit.file)
                dismiss()
            } catch { self.error = "수정을 저장하지 못했습니다. 외부 파일 변경 또는 폴더 권한을 확인해 주세요. 입력한 내용은 유지됩니다." }
        }
    }
}
