import AppKit
import DamaAudio
import DamaManaged
import DamaCore
import DamaNemotron
import SwiftUI

@MainActor
final class ProcessingWorkspace: ObservableObject {
    static let shared = ProcessingWorkspace()
    @Published private(set) var runs: [ManagedRun] = []
    @Published private(set) var scanIssues: [FileScanIssue] = []
    @Published private(set) var runHistoryAvailable = false
    @Published private(set) var localOnly: Set<String> = []
    @Published private(set) var busy = false
    @Published private(set) var activeSessionID: String?
    @Published private(set) var attemptStartedAt: Date?
    @Published var message: String?
    @Published var selectedProvider = TranscriptionProvider.operatingSelection(stored: UserDefaults.standard.string(forKey: "transcription.operatingProvider")) {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: "transcription.operatingProvider") }
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
    private var activeProvider: TranscriptionProvider?

    enum ModelStatus: Equatable { case checking, missing, downloading, ready, failed, mismatch }
    @Published private(set) var modelStatus = ModelStatus.checking
    private var modelStore: NemotronModelStore? { (try? AudioFiles.root()).map { NemotronModelStore(internalRoot: $0) } }
    var modelStatusText: String {
        switch modelStatus {
        case .checking, .missing: "화자 분리 모델 필요 · 약 200MB"
        case .downloading: "화자 분리 모델을 받는 중"
        case .ready: "화자 분리 모델 준비됨 · Nemotron 3"
        case .failed: "화자 분리 모델을 받지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해 주세요."
        case .mismatch: "받은 모델이 이 버전의 DAMA가 확인한 파일과 달라 사용하지 않았습니다."
        }
    }
    /// Hashes about 200MB off the main actor; a mismatching copy is removed.
    func refreshModelStatus() {
        guard modelStatus != .downloading, let store = modelStore else { return }
        Task {
            let state = await Task.detached { try? store.removeIfMismatched() }.value
            guard modelStatus != .downloading else { return }
            modelStatus = state == .ready ? .ready : state == .mismatch ? .mismatch : .missing
        }
    }
    /// The only network use of the local path; runs only from the model button.
    func downloadModel() {
        guard modelStatus != .downloading, let store = modelStore else { return }
        modelStatus = .downloading
        Task {
            do {
                try await store.install { cache in try await FluidNemotronDownloader.download(into: cache) }
                modelStatus = .ready
            } catch NemotronModelError.mismatch { modelStatus = .mismatch }
            catch { modelStatus = .failed }
        }
    }
    /// Continuing this run would need pyannote.ai, which DAMA no longer calls.
    func isRetired(_ run: ManagedRun) -> Bool { run.needsPyannote(among: runs) }

    private func admitsProcessing(_ provider: TranscriptionProvider) -> Bool {
        let recording = RecordingWorkspace.shared
        guard !recording.lifecycle.shuttingDown else { return false }
        if [.qwen, .sonioxNemotron].contains(provider) && !recording.lifecycle.allowsLocalInference(
            phase: recording.capture.phase, needsFinalization: recording.capture.needsFinalization) {
            message = provider == .qwen ? "녹음 원본을 저장한 뒤 Qwen 비교 전사를 시작하거나 재개해 주세요."
                : "녹음 원본을 저장한 뒤 화자 분리를 시작하거나 재개해 주세요."
            return false
        }
        return true
    }

    func start() {
        guard processor == nil else { return }
        do {
            let root = try AudioFiles.root()
            let processor = ManagedProcessor(root: root, qwen: QwenRunner(runtimeURL:qwenRuntimeURL),
                diarizer: FluidNemotronDiarizer(), nemotronModels: NemotronModelStore(internalRoot: root),
                admitsLocalInference: {
                    await MainActor.run {
                        let recording = RecordingWorkspace.shared
                        return !recording.lifecycle.shuttingDown && recording.lifecycle.allowsLocalInference(
                            phase: recording.capture.phase, needsFinalization: recording.capture.needsFinalization)
                    }
                }, allowsPyannote: false)
            self.processor = processor
            refreshModelStatus()
            Task {
                do {
                    await refreshRuns(recover: true)
                    let records = try await AudioLibrary(root: AudioFiles.root()).list()
                    for record in records where try await processor.isLocalOnly(record.id) { localOnly.insert(record.id) }
                } catch { message = "처리 상태를 불러오지 못했습니다. 자동으로 작업을 다시 제출하지 않습니다." }
            }
        } catch { message = "처리 저장소를 열지 못했습니다." }
    }

    func run(for id: String) -> ManagedRun? { runs.first { $0.sessionID == id && $0.parentRunID == nil } }

    func refresh() {
        guard !busy else { return }
        Task { await refreshRuns(recover: true) }
    }

    private func refreshRuns(recover: Bool = false) async {
        guard let processor else { return }
        do {
            let scan = try await processor.scanRuns(recover: recover)
            runs = scan.items; scanIssues = scan.issues; runHistoryAvailable = true
        } catch is CancellationError {
            // A cancelled status monitor must not mark a healthy history as unavailable.
        } catch {
            runHistoryAvailable = false
            message = "처리 이력을 읽지 못해 제출·재개를 보류했습니다. 기존 목록은 유지됩니다."
        }
    }

    private func historyAllowsProcessing(_ sessionID: String) -> Bool {
        runHistoryAvailable && !scanIssues.contains { $0.sessionID == sessionID }
    }

    func canRetranscribe(_ sessionID: String) -> Bool {
        !busy && historyAllowsProcessing(sessionID) && !localOnly.contains(sessionID) && runs.filter { $0.sessionID == sessionID && $0.parentRunID == nil && (selectedProvider == .qwen || $0.provider != .qwen) }.allSatisfy { $0.canRetranscribe || isRetired($0) }
    }

    func preparedInput(_ input: ConversionNotes) async throws -> ConversionNotes {
        let selected = input.forTranscription(selectedProvider, sonioxContext: sonioxContext)
        let notes = try await CorrectionWorkspace.shared.preparedInput(selected,
            enabled: false,
            includeSonioxFolder: sonioxFolderContext, includeQwenFolder: qwenFolderContext)
        let prepared = selectedProvider.usesSoniox ? try SonioxRequest.prepare(notes, includeFolder: sonioxFolderContext) : notes
        try prepared.validate()
        return prepared
    }

    func reviewTransmission(_ record: AudioManifest, input original: ConversionNotes = ConversionNotes(), retranscribing: Bool = false) async {
        var input=original
        guard !busy, let processor, record.analysis != nil, !localOnly.contains(record.id) else { return }
        await refreshRuns(recover: true)
        guard historyAllowsProcessing(record.id) else {
            message = "이 녹음의 처리 이력을 확인할 수 없어 전송을 보류했습니다. 읽지 못한 파일을 확인해 주세요."; return
        }
        guard admitsProcessing(input.provider) else { return }
        if input.provider == .qwen {
            guard qwenReady else { message="Qwen 로컬 엔진이 준비되지 않았습니다. 엔진 설정에서 설치된 환경을 연결해 주세요.";return }
            do { input.qwenDiarizationRunID=try await processor.reusableDiarization(sessionID:record.id,
                audioHash:record.analysis!.sha256,speakerCount:input.speakerCount) }
            catch { message="기존 화자 분리 결과를 확인하지 못했습니다. 새 음성을 전송하지 않았습니다.";return }
        }
        if input.provider == .sonioxPrecision {
            do {
                input.sonioxSourceRunID = try await processor.reusableSoniox(sessionID: record.id, audioHash: record.analysis!.sha256, input: input)
                input.precisionSourceRunID = try await processor.reusableDiarization(sessionID: record.id, audioHash: record.analysis!.sha256, speakerCount: input.speakerCount)
            } catch { message = "기존 결과의 조건을 확인하지 못했습니다. 전송하지 않았습니다."; return }
        }
        if input.provider == .sonioxNemotron {
            guard modelStatus == .ready else { message = "화자 분리 모델이 없습니다. 새 전사 설정에서 모델을 먼저 받아 주세요."; return }
            do {
                input.sonioxSourceRunID = try await processor.reusableSoniox(sessionID: record.id, audioHash: record.analysis!.sha256, input: input)
                input.nemotronSourceRunID = try await processor.reusableNemotron(sessionID: record.id, audioHash: record.analysis!.sha256)
            } catch { message = "기존 결과의 조건을 확인하지 못했습니다. 전송하지 않았습니다."; return }
        }
        guard !busy, admitsProcessing(input.provider) else { return }
        if input.provider.usesSoniox && record.durationUs > SonioxRequest.maximumDurationUs {
            message = "Soniox는 300분 이하의 녹음을 지원합니다. 음성을 전송하지 않았습니다."; return
        }
        if retranscribing && !canRetranscribe(record.id) { message = "진행 중이거나 일시 정지된 전사를 먼저 완료해 주세요."; return }
        let alert = NSAlert()
        alert.messageText = retranscribing ? "음성을 다시 전송해 재전사할까요?" : "음성을 전송할까요?"
        alert.informativeText = "\(record.title) · \(record.durationUs / 1_000_000)초\n\n이 녹음의 음성을 \(input.provider.destination)로 보내 화자별 스크립트를 만듭니다. 모델: \(input.provider.model). 계정에 따라 비용이 발생할 수 있습니다. 원본은 이 Mac에 보관합니다.\n\n계정의 처리 지역과 보관 정책을 확인해 주세요. 앱에서 지워도 서버에서 즉시 삭제되지는 않습니다."
        if input.provider.usesSoniox {
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
        if input.provider == .sonioxPrecision {
            alert.messageText = "운영 스크립트를 만들까요?"
            alert.informativeText = "\(record.title) · \(record.durationUs / 1_000_000)초\n\nSoniox: " +
                (input.sonioxSourceRunID.map { "동일 음성·문맥 결과 재사용 (\($0))" } ?? "전체 음성 전송 · stt-async-v5 전사 및 자체 화자분리") +
                "\nPrecision-2: " + (input.precisionSourceRunID.map { "동일 음성·화자 수 설정 결과 재사용 (\($0))" } ?? "전체 음성을 pyannote.ai에 전송 · 화자분리만 (전사 OFF)") +
                "\n\n새 요청에만 해당 서비스 사용량이 발생합니다. 완료된 결과는 보존하고, Soniox 단독과 결합본을 따로 엽니다. AI 교정 OFF. 화자 충돌·경계·겹말은 검수 대상으로 남습니다.\n\n" +
                (input.speakerCount.map { "실제 발화자 \($0)명: Precision-2 제약" } ?? "실제 발화자 수 미입력: Precision-2 자동 판단") +
                (input.sonioxSpeakerCountHint.map { " · Soniox \($0)명 힌트 (강제 아님)" } ?? " · Soniox 자동 판단") +
                "\n참석자 명단과 실제 발화자 수는 다를 수 있습니다. 선택한 문맥은 Soniox에만 보내며 참고 문서를 정답으로 강제하지 않습니다.\n\n기존 수정본은 보존됩니다. Soniox 서버 파일은 자동 삭제하지 않으며 보관 정책이 적용됩니다."
        }
        if input.provider == .sonioxNemotron {
            alert.messageText = "운영 스크립트를 만들까요?"
            alert.informativeText = "\(record.title) · \(record.durationUs / 1_000_000)초\n\nSoniox: " +
                (input.sonioxSourceRunID.map { "동일 음성·문맥 결과 재사용 (\($0))" } ?? "전체 음성 전송 · stt-async-v5 전사 및 자체 화자분리") +
                "\nNemotron 3: " + (input.nemotronSourceRunID.map { "동일 음성·모델 결과 재사용 (\($0))" } ?? "이 Mac에서 화자 분리 · 음성 전송 없음") +
                "\n\n새 Soniox 요청에만 사용량이 발생합니다. 완료된 결과는 보존하고, Soniox 단독과 결합본을 따로 엽니다. AI 교정 OFF. 화자 충돌·경계·겹말은 검수 대상으로 남습니다.\n\n" +
                (input.speakerCount.map { "실제 발화자 \($0)명: Nemotron 3에는 지정하지 않음" } ?? "실제 발화자 수 미입력") +
                (input.sonioxSpeakerCountHint.map { " · Soniox \($0)명 힌트 (강제 아님)" } ?? " · Soniox 자동 판단") +
                "\n참석자 명단과 실제 발화자 수는 다를 수 있습니다. 선택한 문맥은 Soniox에만 보내며 참고 문서를 정답으로 강제하지 않습니다.\n\n기존 수정본은 보존됩니다. Soniox 서버 파일은 자동 삭제하지 않으며 보관 정책이 적용됩니다."
        }
        if retranscribing && [.sonioxPrecision, .sonioxNemotron, .qwen].contains(input.provider) &&
            runs.contains(where: { $0.sessionID == record.id && $0.stage == "submissionUncertain" }) {
            alert.informativeText += "\n\n이전 작업의 접수 여부가 불명확합니다. 새 API 요청이 필요하면 중복 처리·과금이 발생할 수 있습니다. 기존 접수 불명 작업은 자동 재제출하지 않습니다."
        }
        if input.aiCorrection == true {
            alert.informativeText += "\n\n전사 후 Codex CLI로 자동 교정합니다. 전사·참석자·맥락·아래 참고 발췌를 OpenAI에 전송하며 Codex 계정 사용량이 소모될 수 있습니다. 원문과 시간은 보존합니다."
        }
        CorrectionWorkspace.addPreview(to: alert, input: input)
        alert.addButton(withTitle: "닫기")
        alert.addButton(withTitle: [.sonioxPrecision, .sonioxNemotron].contains(input.provider) ? "결합본 만들기" : input.provider == .qwen ? "비교 전사 시작" : retranscribing ? "재전사 시작" : input.aiCorrection == true ? "전송하고 자동 교정" : "음성 전송")
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
        let combined = input.provider == .sonioxPrecision, local = input.provider == .sonioxNemotron
        launch(sessionID: record.id, provider: input.provider,
               needsKey: local ? false : combined ? input.precisionSourceRunID == nil : input.provider != .qwen || input.qwenDiarizationRunID == nil,
               needsSonioxKey: (combined || local) && input.sonioxSourceRunID == nil) { key, sonioxKey in
            try await processor.begin(sessionID: record.id, confirmed: true, key: key, input: confirmedInput,
                                      retranscribing: retranscribing, sonioxKey: sonioxKey)
        }
    }

    func resume(_ run: ManagedRun) {
        guard !busy, let processor, admitsProcessing(run.provider) else { return }
        let combined = run.provider == .sonioxPrecision, local = run.provider == .sonioxNemotron
        let p2Done = (run.precisionRunID ?? run.input?.precisionSourceRunID).map { id in runs.contains { $0.id == id && $0.stage == "readyForReview" } } ?? false
        let sonioxDone = (run.sonioxRunID ?? run.input?.sonioxSourceRunID).map { id in runs.contains { $0.id == id && $0.stage == "readyForReview" } } ?? false
        launch(sessionID: run.sessionID, provider: run.provider,
               needsKey: local ? false : combined ? !p2Done : run.provider != .qwen || run.input?.qwenDiarizationRunID == nil,
               needsSonioxKey: (combined || local) && !sonioxDone) { key, sonioxKey in
            try await processor.resume(run.id, key: key, sonioxKey: sonioxKey)
        }
    }

    private func saveCompletedSources() {
        let saved = Set(UserDefaults.standard.stringArray(forKey: "library.savedSourceRuns") ?? [])
        for run in runs where run.parentRunID != nil && run.sessionID == activeSessionID && run.provider == .soniox && run.stage == "readyForReview" && !saved.contains(run.id) {
            if !LibraryWorkspace.shared.scripts.contains(where: { $0.id == run.id }) {
                LibraryWorkspace.shared.processingFinished(run, select: false)
            }
        }
    }
    private func launch(sessionID: String, provider: TranscriptionProvider, needsKey: Bool = true,
                        needsSonioxKey: Bool = false, _ action: @escaping @Sendable (String, String) async throws -> ManagedRun) {
        guard AudioFiles.uiFixtureFolder == nil else {
            message = "합성 UI 검증에서는 모델 실행과 외부 전송을 차단합니다."; return
        }
        // Recheck after asynchronous preparation and the modal consent dialog.
        guard !busy, processor != nil, historyAllowsProcessing(sessionID), admitsProcessing(provider) else { return }
        let key: String, sonioxKey: String
        do {
            key = needsKey ? try KeychainStore.read(provider: provider == .sonioxPrecision ? .pyannote : provider) ?? "" : ""
            sonioxKey = needsSonioxKey ? try KeychainStore.read(provider: .soniox) ?? "" : ""
        } catch { message = "키체인에서 API 키를 읽지 못했습니다. 녹음은 계속 사용할 수 있습니다."; return }
        busy = true; activeSessionID = sessionID; attemptStartedAt = Date(); message = nil
        activeProvider = provider
        task = Task {
            let monitor = Task {
                while !Task.isCancelled {
                    await refreshRuns()
                    saveCompletedSources()
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer { monitor.cancel(); busy = false; activeSessionID = nil; activeProvider = nil; attemptStartedAt = nil; task = nil }
            do {
                try Task.checkCancellation()
                let result = try await action(key, sonioxKey)
                await refreshRuns()
                saveCompletedSources()
                if result.stage == "readyForReview" {
                    message = "전사 완료 · 검수 전. 결과의 화자와 원문을 확인해 주세요."
                    LibraryWorkspace.shared.processingFinished(result)
                } else {
                    message = label(result)
                    if [.sonioxPrecision, .sonioxNemotron].contains(result.provider), let id = result.sonioxRunID,
                       runs.contains(where: { $0.id == id && $0.stage == "readyForReview" }) {
                        message = "결합 처리 미완료 · Soniox 단독 결과는 Scripts에서 열 수 있습니다. " + label(result)
                    }
                }
            } catch { message = "처리를 시작하지 못했습니다. 원본과 기존 결과는 유지됩니다." }
        }
    }

    func pause() { task?.cancel() }
    var localInferenceActive: Bool {
        busy && (activeProvider == .qwen || (activeProvider == .sonioxNemotron &&
            runs.contains { $0.sessionID == activeSessionID && $0.parentRunID == nil && $0.stage == "localDiarizing" }))
    }
    func pauseLocalInferenceForRecording() {
        guard localInferenceActive else { return }
        task?.cancel()
        if activeProvider == .qwen { message = "녹음을 우선해 Qwen 비교 전사를 중단합니다. 저장된 진행 상태에서 직접 재개할 수 있습니다." }
    }
    func pauseAndWait() async {
        guard localInferenceActive else { return }
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
        case "localDiarizing": "이 Mac에서 화자를 나누고 있습니다"
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
        !busy && historyAllowsProcessing(run.sessionID) && !isRetired(run) && (run.resumesLocalDiarization || ["localDiarizing", "queued", "uploading", "uploaded", "remotePending", "normalizing", "localTranscribing", "waitingForCredentials", "waitingForBilling", "waitingForNetwork", "paused"].contains(run.stage))
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
