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
    private var processor: ManagedProcessor?
    private var task: Task<Void, Never>?

    func start() {
        guard processor == nil else { return }
        do {
            let processor = ManagedProcessor(root: try AudioFiles.root())
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

    func reviewTransmission(_ record: AudioManifest, input: ConversionNotes = ConversionNotes(), retranscribing: Bool = false) {
        guard !busy, let processor, record.analysis != nil, !localOnly.contains(record.id) else { return }
        if retranscribing && !canRetranscribe(record.id) { message = "진행 중이거나 일시 정지된 전사를 먼저 완료해 주세요."; return }
        let alert = NSAlert()
        alert.messageText = retranscribing ? "음성을 다시 전송해 재전사할까요?" : "음성을 전송할까요?"
        alert.informativeText = "\(record.title) · \(record.durationUs / 1_000_000)초\n\n이 녹음의 음성을 pyannote.ai로 보내 화자별 스크립트를 만듭니다. 계정에 따라 비용이 발생할 수 있습니다. 원본은 이 Mac에 보관합니다.\n\n계정의 처리 지역과 보관 정책을 확인해 주세요. 앱에서 지워도 서버에서 즉시 삭제되지는 않습니다."
        if retranscribing {
            alert.informativeText += "\n\n새 작업으로 처리하며 비용이 다시 발생할 수 있습니다. 기존 스크립트와 사용자 수정은 유지하고 새 스크립트를 만듭니다. 화자 이름과 문장 수정은 새 결과에 자동 복사하지 않습니다."
            if runs.contains(where: { $0.sessionID == record.id && $0.stage == "submissionUncertain" }) {
                alert.informativeText += "\n\n이전 작업의 접수 여부가 불명확합니다. 이미 접수되었다면 중복 처리·과금이 발생할 수 있습니다."
            }
        }
        if input.aiCorrection == true {
            alert.informativeText += "\n\n전사 후 Codex CLI로 자동 교정합니다. 전사·참석자·맥락·아래 참고 발췌를 OpenAI에 전송하며 Codex 계정 사용량이 소모될 수 있습니다. 원문과 시간은 보존합니다."
            CorrectionWorkspace.addPreview(to: alert, input: input)
        }
        alert.addButton(withTitle: "닫기")
        alert.addButton(withTitle: retranscribing ? "재전사 시작" : input.aiCorrection == true ? "전송하고 자동 교정" : "음성 전송")
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
        launch(sessionID: record.id) { key in try await processor.begin(sessionID: record.id, confirmed: true, key: key, input: input, retranscribing: retranscribing) }
    }

    func resume(_ run: ManagedRun) {
        guard !busy, let processor else { return }
        launch(sessionID: run.sessionID) { key in try await processor.resume(run.id, key: key) }
    }

    private func launch(sessionID: String, _ action: @escaping @Sendable (String) async throws -> ManagedRun) {
        guard let processor else { return }
        let key: String
        do {
            key = try KeychainStore.read() ?? ""
        } catch { message = "키체인에서 API 키를 읽지 못했습니다. 녹음은 계속 사용할 수 있습니다."; return }
        busy = true
        activeSessionID = sessionID; attemptStartedAt = Date()
        message = key.isEmpty ? "API 키가 필요합니다. 동의한 작업은 키 설정 후 계속할 수 있습니다." : nil
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
                }
            } catch { message = "처리를 시작하지 못했습니다. 원본과 기존 결과는 유지됩니다." }
        }
    }
    func pause() { task?.cancel() }

    func label(_ run: ManagedRun) -> String {
        switch run.stage {
        case "queued": "전사 대기"
        case "uploading": "음성 전송 중"
        case "submitting": "작업 접수 중"
        case "remotePending": "서버 처리 중"
        case "normalizing": "스크립트 준비 중"
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
        !busy && ["queued", "uploading", "remotePending", "normalizing", "waitingForCredentials", "waitingForBilling", "waitingForNetwork", "paused"].contains(run.stage)
    }
}

struct APIKeySettings: View {
    @State private var key = ""
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("pyannote.ai API 키").font(.headline)
            SecureField("API 키", text: $key).textFieldStyle(.roundedBorder)
            Text("입력한 키는 이 Mac의 키체인에 저장합니다. 저장만으로 연결 확인이나 음성 전송을 하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("키 저장") {
                    do { try KeychainStore.save(key); key = ""; message = "키 저장됨 · 연결 유효성 미검증" }
                    catch { key = ""; message = "키를 저장하지 못했습니다." }
                }.disabled(key.isEmpty)
                Button("키 삭제") {
                    let alert = NSAlert()
                    alert.messageText = "이 Mac의 API 키를 삭제할까요?"
                    alert.informativeText = "녹음 원본과 스크립트는 유지됩니다."
                    alert.addButton(withTitle: "취소")
                    alert.addButton(withTitle: "키 삭제")
                    guard alert.runModal() == .alertSecondButtonReturn else { return }
                    do { try KeychainStore.delete(); message = "키 삭제됨" }
                    catch { message = "키를 삭제하지 못했습니다." }
                }
            }
            if let message { Text(message).font(.callout) }
        }.padding(20).frame(width: 360)
            .onDisappear { key = "" }
    }
}
