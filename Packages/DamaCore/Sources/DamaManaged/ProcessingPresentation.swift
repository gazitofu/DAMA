import Foundation

/// Stage milestones, never a fabricated percentage of server work.
public struct ProcessingPresentation: Sendable {
    public static let steps = ["음성 전송", "작업 접수", "전사·화자 분리", "스크립트 저장"]
    public let title: String
    public let detail: String
    public let step: Int?
    public let spinning: Bool
    public let completed: Bool
    public init(run: ManagedRun?, tracking: Bool, preparing: Bool = false, scriptSaved: Bool = false) {
        completed = run?.stage == "readyForReview" && scriptSaved
        guard let run else {
            title = preparing ? "오디오를 준비하고 있습니다" : "변환을 준비하고 있습니다"
            detail = "원본과 오디오 형식을 확인합니다."
            step = nil; spinning = preparing || tracking; return
        }
        let activeStages = ["queued", "uploading", "uploadSubmitting", "uploaded", "submitting", "remotePending", "normalizing"]
        spinning = tracking && activeStages.contains(run.stage)
        if activeStages.contains(run.stage) && !tracking {
            title = "처리 상태 확인이 멈춰 있습니다"
            detail = "변환 재개를 누르면 같은 작업을 확인합니다. 서버 작업은 계속될 수 있습니다."
            step = nil; return
        }
        switch run.stage {
        case "queued":
            title = "오디오를 준비하고 있습니다"; detail = "전송할 원본과 오디오 형식을 확인합니다."; step = nil
        case "uploading", "uploadSubmitting":
            title = "음성을 전송하고 있습니다"; detail = "오디오 길이와 네트워크 속도에 따라 시간이 걸릴 수 있습니다."; step = 0
        case "submitting", "uploaded":
            title = "변환 작업을 접수하고 있습니다"; detail = "서버의 접수 응답을 기다립니다."; step = 1
        case "remotePending":
            title = ["running", "processing", "completed"].contains(run.remoteStatus ?? "") ? "전사와 화자 분리가 진행 중입니다" : "서버에서 처리 순서를 기다리고 있습니다"
            detail = "완료되면 스크립트를 자동으로 저장합니다. 서버는 진행률·남은 시간을 제공하지 않습니다."; step = 2
        case "normalizing":
            title = "스크립트를 준비하고 있습니다"; detail = "변환 결과를 읽고 이 Mac에 저장합니다."; step = 3
        case "readyForReview":
            title = scriptSaved ? "변환이 완료되었습니다" : "전사 완료 · 스크립트 저장이 필요합니다"
            detail = scriptSaved ? "스크립트에서 화자와 대화를 확인하세요." : "저장이 끝나지 않으면 아래 스크립트 저장으로 다시 시도할 수 있습니다."; step = 3
        case "waitingForNetwork":
            title = "네트워크 연결 확인이 필요합니다"; detail = "연결을 확인한 뒤 변환을 재개하세요."; step = nil
        case "waitingForCredentials":
            title = "API 키를 확인해 주세요"; detail = "설정에서 키를 저장한 뒤 변환을 재개하세요."; step = nil
        case "waitingForBilling":
            title = "결제 상태를 확인해 주세요"; detail = "\(run.provider.title) 계정 확인 후 변환을 재개하세요."; step = nil
        case "submissionUncertain":
            title = "작업 접수 여부를 확인하지 못했습니다"; detail = "중복 과금을 막기 위해 자동으로 다시 제출하지 않습니다."; step = nil
        case "paused":
            title = "처리 상태 확인을 일시 정지했습니다"; detail = "서버 작업은 계속될 수 있습니다. 변환 재개로 같은 작업을 확인하세요."; step = nil
        case "partialResult":
            title = "변환 결과를 완전히 읽지 못했습니다"; detail = "원본 응답은 보존되어 있습니다."; step = nil
        case "resultExpired":
            title = "서버 결과를 가져오지 못했습니다"; detail = "결과 보관 기간이나 계정 상태를 확인해 주세요."; step = nil
        default:
            title = "변환 상태를 확인해 주세요"; detail = "변환을 완료하지 못했습니다. 원본은 보존되어 있습니다."; step = nil
        }
    }
    public static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}
