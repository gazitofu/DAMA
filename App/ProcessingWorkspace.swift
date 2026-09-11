import AppKit
import DamaAudio
import DamaManaged
import DamaCore
import SwiftUI

@MainActor
final class ProcessingWorkspace: ObservableObject {
    static let shared = ProcessingWorkspace()
    @Published private(set) var runs: [ManagedRun] = []
    @Published private(set) var localOnly: Set<String> = []
    @Published private(set) var busy = false
    @Published private(set) var activeSessionID: String?
    @Published private(set) var attemptStartedAt: Date?
    @Published var message: String?
    @Published var selectedProvider = TranscriptionProvider(rawValue: UserDefaults.standard.string(forKey: "transcription.provider") ?? "") ?? .pyannote {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: "transcription.provider") }
    }
    @Published var comparison = UserDefaults.standard.object(forKey: "transcription.comparison") as? Bool ?? true {
        didSet { UserDefaults.standard.set(comparison, forKey: "transcription.comparison") }
    }
    @Published var sonioxContext = UserDefaults.standard.object(forKey: "transcription.sonioxContext") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sonioxContext, forKey: "transcription.sonioxContext") }
    }
    @Published var sonioxFolderContext = UserDefaults.standard.object(forKey: "transcription.sonioxFolderContext") as? Bool ?? false {
        didSet { UserDefaults.standard.set(sonioxFolderContext, forKey: "transcription.sonioxFolderContext") }
    }
    @Published var sonioxTerms = ""
    @Published var qwenTerms = ""
    @Published var qwenFolderContext = false
    @Published var qwenRuntimeURL = URL(fileURLWithPath: UserDefaults.standard.string(forKey:"qwen.runtime") ?? QwenRunner.defaultRuntime.path)
    var qwenReady: Bool { (try? QwenRunner(runtimeURL:qwenRuntimeURL).validateReady()) != nil }
    func chooseQwenRuntime() {
        guard !busy else { return }
        let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=false
        panel.message="준비된 Qwen 로컬 엔진의 qwen-runtime.json 파일을 선택해 주세요."
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do {
            try QwenRunner(runtimeURL:url).validateReady()
            qwenRuntimeURL=url;UserDefaults.standard.set(url.path,forKey:"qwen.runtime")
            processor=nil;start()
        } catch { message="Qwen 실행 환경 또는 모델을 찾지 못했습니다. 로컬 엔진 설치를 먼저 완료해 주세요." }
    }
    private var processor: ManagedProcessor?
    private var task: Task<Void, Never>?

    func start() {
        guard processor == nil else { return }
        do {
            let processor = ManagedProcessor(root: try AudioFiles.root(), qwen: QwenRunner(runtimeURL:qwenRuntimeURL))
            self.processor = processor
            Task {
                do {
                    runs = try await processor.runs(recover: true)
                    let records = try await AudioLibrary(root: AudioFiles.root()).list()
                    for record in records where try await processor.isLocalOnly(record.id) { localOnly.insert(record.id) }
                } catch { message = "처리 상태를 불러오지 못했습니다. 자동으로 작업을 다시 제출하지 않습니다." }
            }
        } catch { message = "처리 저장소를 열지 못했습니다." }
    }

    func run(for id: String) -> ManagedRun? { runs.first { $0.sessionID == id } }

    func canRetranscribe(_ sessionID: String) -> Bool {
        !busy && !localOnly.contains(sessionID) && runs.filter { $0.sessionID == sessionID }.allSatisfy(\.canRetranscribe)
    }

    func preparedInput(_ input: ConversionNotes) async throws -> ConversionNotes {
        var selected = input
        selected.transcriptionProvider = selectedProvider
        selected.sonioxContext = selectedProvider == .soniox && sonioxContext
        selected.sonioxTerms = selectedProvider == .soniox && sonioxContext ? sonioxTerms : nil
        selected.qwenTerms = selectedProvider == .qwen ? qwenTerms : nil
        selected.qwenDiarizationRunID=nil
        let notes = try await CorrectionWorkspace.shared.preparedInput(selected,
            enabled: selectedProvider != .qwen && !comparison && CorrectionWorkspace.shared.automatic,
            includeSonioxFolder: sonioxFolderContext, includeQwenFolder: qwenFolderContext)
        let prepared = selectedProvider == .soniox ? try SonioxRequest.prepare(notes, includeFolder: sonioxFolderContext) : notes
        try prepared.validate()
        return prepared
    }

    func reviewTransmission(_ record: AudioManifest, input original: ConversionNotes = ConversionNotes(), retranscribing: Bool = false) async {
        var input=original
        guard !busy, let processor, record.analysis != nil, !localOnly.contains(record.id) else { return }
        if input.provider == .qwen {
            guard qwenReady else { message="Qwen 로컬 엔진이 준비되지 않았습니다. 엔진 설정에서 설치된 환경을 연결해 주세요.";return }
            do { input.qwenDiarizationRunID=try await processor.reusableDiarization(sessionID:record.id,
                audioHash:record.analysis!.sha256,speakerCount:input.speakerCount) }
            catch { message="기존 화자 분리 결과를 확인하지 못했습니다. 새 음성을 전송하지 않았습니다.";return }
        }
        guard !busy else { return }
        if input.provider == .soniox && record.durationUs > SonioxRequest.maximumDurationUs {
            message = "Soniox는 300분 이하의 녹음을 지원합니다. 음성을 전송하지 않았습니다."; return
        }
        if retranscribing && !canRetranscribe(record.id) { message = "진행 중이거나 일시 정지된 전사를 먼저 완료해 주세요."; return }
        let alert = NSAlert()
        alert.messageText = retranscribing ? "음성을 다시 전송해 재전사할까요?" : "음성을 전송할까요?"
        alert.informativeText = "\(record.title) · \(record.durationUs / 1_000_000)초\n\n이 녹음의 음성을 \(input.provider.destination)로 보내 화자별 스크립트를 만듭니다. 모델: \(input.provider.model). 계정에 따라 비용이 발생할 수 있습니다. 원본은 이 Mac에 보관합니다.\n\n계정의 처리 지역과 보관 정책을 확인해 주세요. 앱에서 지워도 서버에서 즉시 삭제되지는 않습니다."
        if input.provider == .soniox {
            alert.informativeText += "\n\n한국어·영어 힌트, 화자 분리·언어 감지를 사용합니다. 화자 수는 자동 판단합니다. 앱은 서버 파일·작업을 자동 삭제하지 않습니다. Soniox 정책상 30일 후 자동 삭제됩니다."
            alert.informativeText += input.sonioxContext == true ? "\n아래 맥락·참석자·용어와 선택된 참고 발췌도 Soniox에 전송합니다." : "\n맥락·참고 정보·화자 수 힌트는 Soniox에 전송하지 않습니다."
            if let count = input.sonioxSpeakerCountHint {
                alert.informativeText += "\n예상 발화자 \(count)명은 참고 힌트입니다. 결과를 해당 인원으로 강제하지 않습니다."
            }
        }
        if input.aiCorrection != true { alert.informativeText += "\n\nAI 문맥 교정 OFF · 모델 원문으로 스크립트를 만듭니다." }
        if retranscribing {
            alert.informativeText += "\n\n새 작업으로 처리하며 비용이 다시 발생할 수 있습니다. 기존 스크립트와 사용자 수정은 유지하고 새 스크립트를 만듭니다. 화자 이름과 문장 수정은 새 결과에 자동 복사하지 않습니다."
            if runs.contains(where: { $0.sessionID == record.id && $0.stage == "submissionUncertain" }) {
                alert.informativeText += "\n\n이전 작업의 접수 여부가 불명확합니다. 이미 접수되었다면 중복 처리·과금이 발생할 수 있습니다."
            }
        }
        if input.provider == .qwen {
            alert.messageText="로컬 Qwen 비교 전사를 시작할까요?"
            alert.informativeText="\(record.title) · \(record.durationUs/1_000_000)초\n\n이 Mac에서 Qwen3-ASR-1.7B와 ForcedAligner-0.6B로 한국어 전사·정렬을 실행합니다. 맥락·참석자·용어는 로컬 모델에만 입력합니다. AI 교정은 끕니다.\n\n" +
                (input.qwenDiarizationRunID != nil ? "같은 오디오·화자 수 설정의 Precision-2 결과를 재사용합니다. 새 음성 전송·화자 분리 과금은 없습니다." : "화자 분리를 위해 전체 음성을 pyannote.ai로 전송합니다. Precision-2 요금이 발생할 수 있습니다. Whisper 전사는 요청하지 않습니다.") +
                "\n\n새 스크립트로 저장하며 기존 결과와 사람 수정은 보존합니다. 경계·겹말의 화자는 미확정으로 남길 수 있습니다."
        }
        if input.aiCorrection == true {
            alert.informativeText += "\n\n전사 후 Codex CLI로 자동 교정합니다. 전사·참석자·맥락·아래 참고 발췌를 OpenAI에 전송하며 Codex 계정 사용량이 소모될 수 있습니다. 원문과 시간은 보존합니다."
        }
        CorrectionWorkspace.addPreview(to: alert, input: input)
        alert.addButton(withTitle: "닫기")
        alert.addButton(withTitle: input.provider == .qwen ? "비교 전사 시작" : retranscribing ? "재전사 시작" : input.aiCorrection == true ? "전송하고 자동 교정" : "음성 전송")
        if !retranscribing { alert.addButton(withTitle: "로컬 저장만") }
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            Task {
                do { try await processor.setLocalOnly(record.id); localOnly.insert(record.id) }
                catch { message = "이미 전송이 시작된 기록의 정책은 소급 변경할 수 없습니다." }
            }
            return
        }
        guard response == .alertSecondButtonReturn else { return }
        let confirmedInput=input
        launch(sessionID:record.id,provider:input.provider,needsKey:input.provider != .qwen || input.qwenDiarizationRunID == nil) { key in
            try await processor.begin(sessionID:record.id,confirmed:true,key:key,input:confirmedInput,retranscribing:retranscribing)
        }
    }

    func resume(_ run: ManagedRun) {
        guard !busy, let processor else { return }
        launch(sessionID:run.sessionID,provider:run.provider,needsKey:run.provider != .qwen || run.input?.qwenDiarizationRunID == nil) { key in try await processor.resume(run.id,key:key) }
    }

    private func launch(sessionID: String, provider: TranscriptionProvider, needsKey: Bool = true, _ action: @escaping @Sendable (String) async throws -> ManagedRun) {
        guard let processor else { return }
        let key: String
        do {
            key = needsKey ? try KeychainStore.read(provider: provider) ?? "" : ""
        } catch { message = "키체인에서 API 키를 읽지 못했습니다. 녹음은 계속 사용할 수 있습니다."; return }
        busy = true
        activeSessionID = sessionID; attemptStartedAt = Date()
        message = needsKey && key.isEmpty ? "\(provider.title) API 키가 필요합니다. 동의한 작업은 키 설정 후 계속할 수 있습니다." : nil
        task = Task {
            let monitor = Task {
                while !Task.isCancelled {
                    runs = (try? await processor.runs()) ?? runs
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer { monitor.cancel(); busy = false; activeSessionID = nil; attemptStartedAt = nil; task = nil }
            do {
                let result = try await action(key)
                runs = (try? await processor.runs()) ?? runs
                if result.stage == "readyForReview" {
                    message = "전사 완료 · 검수 전. 결과의 화자와 원문을 확인해 주세요."
                    LibraryWorkspace.shared.processingFinished(result)
                } else if result.provider == .qwen {
                    message=result.failure == "runtimeUnavailable" ? "Qwen 실행 환경을 확인해 주세요. 원본과 완료 청크는 보존했습니다." : "Qwen 처리가 완료되지 않았습니다. 완료 청크를 보존했으며 변환 재개로 이어갈 수 있습니다."
                }
            } catch { message = "처리를 시작하지 못했습니다. 원본과 기존 결과는 유지됩니다." }
        }
    }
    func pause() { task?.cancel() }
    var localInferenceActive: Bool {
        guard busy, let id = activeSessionID else { return false }
        return (run(for: id)?.provider ?? selectedProvider) == .qwen
    }
    func pauseAndWait() async {
        let running = task
        running?.cancel()
        await running?.value
    }

    func label(_ run: ManagedRun) -> String {
        switch run.stage {
        case "queued": "전사 대기"
        case "uploading", "uploadSubmitting": "음성 전송 중"
        case "uploaded": "음성 전송 완료 · 작업 접수 대기"
        case "submitting": "작업 접수 중"
        case "remotePending": "서버 처리 중"
        case "normalizing": "스크립트 준비 중"
        case "localTranscribing": "Qwen 로컬 전사·정렬 중"
        case "readyForReview": "전사 완료 · 검수 전"
        case "submissionUncertain": "작업 접수 여부를 확인할 수 없습니다. 자동 재제출하지 않습니다."
        case "waitingForCredentials": "API 키 필요"
        case "waitingForBilling": "결제 상태 확인 필요"
        case "waitingForNetwork": "네트워크 연결 대기"
        case "paused": "로컬 추적 일시 정지"
        case "resultExpired": "서버 결과를 가져오지 못했습니다."
        case "partialResult": "전사 결과를 완전히 읽지 못했습니다. 원본 응답은 보존합니다."
        case "unknownRemoteStatus": "알 수 없는 서버 상태: \(run.remoteStatus ?? "미제공")"
        default: "전사 실패"
        }
    }
    func canResume(_ run: ManagedRun) -> Bool {
        !busy && ["queued", "uploading", "uploaded", "remotePending", "normalizing", "localTranscribing", "waitingForCredentials", "waitingForBilling", "waitingForNetwork", "paused"].contains(run.stage)
    }
}

struct APIKeySettings: View {
    @State private var provider: TranscriptionProvider = .pyannote
    @State private var key = ""
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("API 키 서비스", selection: $provider) {
                ForEach([TranscriptionProvider.pyannote, .soniox], id: \.self) { Text($0.title).tag($0) }
            }.onChange(of: provider) { key = ""; message = nil }
            Text("\(provider.title) API 키").font(.headline)
            SecureField("API 키", text: $key).textFieldStyle(.roundedBorder)
            Text("입력한 키는 이 Mac의 키체인에 저장합니다. 저장만으로 연결 확인이나 음성 전송을 하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("키 저장") {
                    do { try KeychainStore.save(key, provider: provider); key = ""; message = "\(provider.title) 키 저장됨 · 연결 유효성 미검증" }
                    catch { key = ""; message = "키를 저장하지 못했습니다." }
                }.disabled(key.isEmpty)
                Button("키 삭제") {
                    let alert = NSAlert()
                    alert.messageText = "이 Mac의 \(provider.title) API 키를 삭제할까요?"
                    alert.informativeText = "녹음 원본과 스크립트는 유지됩니다."
                    alert.addButton(withTitle: "취소")
                    alert.addButton(withTitle: "키 삭제")
                    guard alert.runModal() == .alertSecondButtonReturn else { return }
                    do { try KeychainStore.delete(provider: provider); message = "\(provider.title) 키 삭제됨" }
                    catch { message = "키를 삭제하지 못했습니다." }
                }
            }
            if let message { Text(message).font(.callout) }
        }.padding(20).frame(width: 360)
            .onDisappear { key = "" }
    }
}
