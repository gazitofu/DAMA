import DamaAudio
import DamaCore
import DamaManaged
import SwiftUI

struct SpeakerNameSheet: View {
    let edit: LibraryEdit
    @ObservedObject var workspace: LibraryWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var scope: SpeakerNameScope
    @State private var selectedSpeaker = ""
    @State private var error: String?
    private var block: ScriptBlock { switch edit.kind { case let .speaker(block): block } }
    private var hasSpeaker: Bool { block.speakerID != nil }
    private var originalLabel: String? { edit.file.script.originalSpeakerLabel(for: block.speakerTurnID) }
    init(edit: LibraryEdit, workspace: LibraryWorkspace) {
        self.edit = edit; self.workspace = workspace
        switch edit.kind {
        case let .speaker(block):
            _scope = State(initialValue: block.speakerID == nil ? .one : .all)
            _value = State(initialValue: block.name == "화자 미확정" ? "" : block.name)
            _selectedSpeaker = State(initialValue: edit.file.script.availableSpeakers.first(where: { $0.name == block.name })?.id ?? "")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("화자 이름 변경").font(.title2)
            Text("원 화자 \(originalLabel ?? "미배정") · 현재 이름 \(block.name)").font(.caption).foregroundStyle(.secondary)
            Picker("등록된 화자", selection: $selectedSpeaker) {
                Text("직접 입력").tag("")
                ForEach(edit.file.script.availableSpeakers) { speaker in Text(speaker.name).tag(speaker.id) }
            }.accessibilityLabel("등록된 화자")
            TextField("표시 이름", text: $value).textFieldStyle(.roundedBorder).accessibilityLabel("표시 이름")
            Text("이름을 저장하면 이 스크립트의 다른 발화에서도 선택할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            Picker("적용 범위", selection: $scope) {
                Text("이 부분만").tag(SpeakerNameScope.one)
                if hasSpeaker {
                    Text("이 부분부터").tag(SpeakerNameScope.from)
                    Text("전체").tag(SpeakerNameScope.all)
                }
            }.pickerStyle(.radioGroup)
            Text("대상 원구간 \(edit.file.script.affectedTurns(in: block, scope: scope).count)개").font(.caption)
            Text(hasSpeaker ? "‘이 부분부터’·‘전체’는 원 화자 \(originalLabel ?? "")로 분리된 부분에만 적용됩니다. 같은 이름의 다른 원 화자는 바뀌지 않습니다." : "미배정 화자는 선택한 부분만 바꿀 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).disabled(workspace.busy)
                Button("화자 저장") {
                    Task {
                        do {
                            var candidate = edit.file.script
                            try candidate.rename(block, name: value, scope: scope)
                            try await workspace.saveScript(candidate, original: edit.file)
                            dismiss()
                        } catch { self.error = "이름을 저장하지 못했습니다. 입력한 내용은 유지됩니다." }
                    }
                }.keyboardShortcut(.defaultAction).disabled(workspace.busy || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 430).interactiveDismissDisabled()
            .onChange(of: selectedSpeaker) { _, id in
                if let speaker = edit.file.script.availableSpeakers.first(where: { $0.id == id }) { value = speaker.name }
            }
            .onChange(of: value) { _, name in
                if edit.file.script.availableSpeakers.first(where: { $0.id == selectedSpeaker })?.name != name { selectedSpeaker = "" }
            }
    }
}

struct ScriptAIRequest: Identifiable {
    let id = UUID()
    let file: LibraryScriptFile
    func chunks() throws -> [CorrectionChunk] {
        var source = file.script; source.correction = nil; source.showsOriginal = nil
        return try ContextCorrection.chunks(source)
    }
}

struct CorrectionInputSheet: View {
    let request: ScriptAIRequest
    @ObservedObject var workspace: LibraryWorkspace
    @ObservedObject private var correction = CorrectionWorkspace.shared
    @Environment(\.dismiss) private var dismiss
    @State private var input: ConversionNotes?
    @State private var excerpts: [ReferenceExcerpt] = []
    @State private var included = Set<String>()
    @State private var extra = ""
    @State private var error: String?
    @State private var preparing = true
    @State private var submitting = false
    /// usage-bundle1 문구 19: 미완료 교정 시도 기록이 있으면 새 교정이 그것을 버린다는 고지.
    @State private var unfinished: (done: Int, total: Int)?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI 검수/보정").font(.title2)
                Text(workspace.scriptTitle(request.file.script)).font(.headline)
                Text("현재 결과의 원문을 보정합니다. 사용자 수정은 보존됩니다.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if preparing { ProgressView("참고 내용 확인 중…") }
                    if let input {
                        DisclosureGroup("기존 참석자·맥락·참고 내용") {
                            Text([input.participants ?? "", input.context, input.reference, input.meetingTerms ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n")).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text("추가 참고 내용 (선택)").font(.headline)
                    ExactTextEditor(text: $extra, label: "추가 참고 내용").frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                    Text("이번 보정에만 사용됩니다.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(correction.referenceURL?.lastPathComponent ?? "참고 폴더 없음").font(.caption)
                        Spacer(); Button("참고 폴더 선택", action: correction.chooseReferences).disabled(submitting || preparing)
                    }
                    if excerpts.isEmpty { Text("선택한 참고 파일이 없습니다.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(excerpts, id: \.name) { excerpt in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(excerpt.name, isOn: Binding(get: { included.contains(excerpt.name) }, set: { if $0 { included.insert(excerpt.name) } else { included.remove(excerpt.name) } }))
                            DisclosureGroup("보낼 발췌 보기") { Text(excerpt.text).font(.caption).textSelection(.enabled) }
                        }
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                }.padding(24)
            }.frame(minHeight: 220, maxHeight: 330).disabled(submitting)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if let unfinished {
                    Text("미완료 교정(\(unfinished.done)/\(unfinished.total))은 버리고 처음부터 다시 보정합니다.").font(.caption)
                }
                Text("이 스크립트의 전사·참석자·맥락·참고 내용을 OpenAI로 전송합니다. 계정 사용량이 소모될 수 있습니다. 원음은 보내지 않습니다.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer(); Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).disabled(submitting)
                    Button("보정하기", action: submit).buttonStyle(.borderedProminent).disabled(preparing || submitting || input == nil || correction.busy)
                }
            }.padding(24)
        }.frame(width: 550).interactiveDismissDisabled()
            .task { await prepare() }
            .task {
                switch await correction.attemptStatus(for: request.file.script) {
                case .none: unfinished = nil
                case .available(let done, let total, _), .planChanged(let done, let total, _): unfinished = (done, total)
                }
            }
            .onChange(of: correction.referenceURL) { _, _ in Task { await prepare() } }
    }
    private func prepare() async {
        preparing = true; input = nil; error = nil
        defer { preparing = false }
        do {
            let base = workspace.speeches.first { $0.id == request.file.script.transcript.sessionId }?.notes ?? request.file.script.input
            let prepared = try await correction.preparedInput(base, enabled: true)
            guard !(try request.chunks()).isEmpty else {
                error = "모든 본문을 사용자가 수정하여 보정할 원문이 없습니다."; return
            }
            input = prepared; excerpts = prepared.referenceExcerpts ?? []; included = Set(excerpts.map(\.name))
        } catch { self.error = "참고 내용을 읽지 못했습니다. 폴더 접근을 확인한 뒤 다시 선택해 주세요. 전송하지 않았습니다." }
    }
    private func submit() {
        guard var input else { return }
        input.referenceExcerpts = excerpts.filter { included.contains($0.name) }
        if !extra.isEmpty { input.reference += (input.reference.isEmpty ? "" : "\n\n") + "추가 참고 내용\n" + extra }
        submitting = true; error = nil
        Task {
            defer { submitting = false }
            do {
                try await workspace.validateCorrectionSource(request.file)
                // Enforce the actual complete prompt budget before the first external request.
                for chunk in try request.chunks() { _ = try ContextCorrection.prompt(chunk: chunk, input: input) }
                correction.enqueue(request.file, input: input); dismiss()
            } catch { self.error = "현재 파일 또는 참고 입력을 확인하지 못했습니다. 전송하지 않았습니다. 입력한 내용은 유지됩니다." }
        }
    }
}
