import AppKit
import DamaAudio
import DamaManaged
import SwiftUI

@MainActor
final class ProcessingWorkspace: ObservableObject {
    static let shared = ProcessingWorkspace()
    @Published private(set) var runs: [ManagedRun] = []
    @Published private(set) var localOnly: Set<String> = []
    @Published private(set) var busy = false
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

    func reviewTransmission(_ record: AudioManifest) {
        guard !busy, let processor, record.analysis != nil, !localOnly.contains(record.id) else { return }
        let alert = NSAlert()
        alert.messageText = "음성을 전송할까요?"
        alert.informativeText = "\(record.title) · \(record.durationUs / 1_000_000)초\n\n이 녹음의 음성을 pyannote.ai로 보내 화자별 스크립트를 만듭니다. 계정에 따라 비용이 발생할 수 있습니다. 원본은 이 Mac에 보관합니다.\n\n계정의 처리 지역과 보관 정책을 확인해 주세요. 앱에서 지워도 서버에서 즉시 삭제되지는 않습니다."
        alert.addButton(withTitle: "닫기")
        alert.addButton(withTitle: "음성 전송")
        alert.addButton(withTitle: "로컬 저장만")
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            Task {
                do { try await processor.setLocalOnly(record.id); localOnly.insert(record.id) }
                catch { message = "이미 전송이 시작된 기록의 정책은 소급 변경할 수 없습니다." }
            }
            return
        }
        guard response == .alertSecondButtonReturn else { return }
        launch { key in try await processor.begin(sessionID: record.id, confirmed: true, key: key) }
    }

    func resume(_ run: ManagedRun) {
        guard !busy, let processor else { return }
        launch { key in try await processor.resume(run.id, key: key) }
    }

    private func launch(_ action: @escaping @Sendable (String) async throws -> ManagedRun) {
        guard let processor else { return }
        let key: String
        do {
            key = try KeychainStore.read() ?? ""
        } catch { message = "키체인에서 API 키를 읽지 못했습니다. 녹음은 계속 사용할 수 있습니다."; return }
        busy = true
        message = key.isEmpty ? "API 키가 필요합니다. 동의한 작업은 키 설정 후 계속할 수 있습니다." : nil
        task = Task {
            let monitor = Task {
                while !Task.isCancelled {
                    runs = (try? await processor.runs()) ?? runs
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer { monitor.cancel(); busy = false; task = nil }
            do {
                let result = try await action(key)
                runs = (try? await processor.runs()) ?? runs
                if result.stage == "readyForReview" { message = "전사 완료 · 검수 전. 결과의 화자와 원문을 확인해 주세요." }
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
