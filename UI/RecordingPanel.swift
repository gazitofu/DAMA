import DamaAudio
import DamaCore
import SwiftUI

struct RecordingPanel: View {
    @ObservedObject var workspace: RecordingWorkspace
    @ObservedObject var capture: MicrophoneCapture
    let openReview: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("다마").font(.headline)
                    Spacer()
                    Button("검수 창", action: openReview)
                }
                HStack {
                    Label(status, systemImage: capture.phase == .recording ? "record.circle" : "mic")
                    Spacer()
                    Text(TranscriptTimePresentation.timestamp(capture.elapsedUs).prefix(8)).monospacedDigit()
                }.font(.title3)
                Text(capture.inputDescription).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(min(1, capture.level))).accessibilityLabel("마이크 입력 레벨")
                if let message = capture.message { Text(message).font(.callout) }
                if capture.needsFinalization {
                    Button("원본 저장 다시 시도") { Task { _ = await capture.retryFinalization() } }
                } else {
                    Button(capture.phase == .recording ? "녹음 종료" : "녹음 시작", action: workspace.toggleRecord)
                        .buttonStyle(.borderedProminent)
                        .disabled(!workspace.ready || [.authorizing, .starting, .finalizing].contains(capture.phase))
                }
                Text("좌클릭: 녹음 시작·종료 · 우클릭: 패널 열기").font(.caption2).foregroundStyle(.secondary)
                Divider()
                Text("클라우드 전사는 다음 단계에서 연결합니다. 녹음은 API 키 없이 가능합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("파일 가져오기", action: workspace.importFile)
                        .disabled(workspace.working || capture.phase.busy)
                    if workspace.working { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("종료") { NSApp.terminate(nil) }
                }
                if let message = workspace.message { Text(message).font(.callout) }
                ForEach(workspace.records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.title).font(.headline)
                        Text("\(record.durationUs / 1_000_000)초 · \(recordLabel(record))").font(.caption)
                        if record.interruption != nil {
                            Text("녹음이 중단되었습니다. 이후 구간은 녹음되지 않았을 수 있습니다.").font(.caption)
                        }
                        HStack {
                            Button("원본 보기") { workspace.reveal(record) }.disabled(record.sources.isEmpty)
                            if record.analysis == nil && !record.sources.isEmpty {
                                Button("분석 준비") { workspace.retryAnalysis(record.id) }
                                    .disabled(workspace.working || capture.phase.busy)
                            }
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(16)
        }.frame(width: 360, height: 520)
    }
    private var status: String {
        switch capture.phase {
        case .idle: "녹음 대기"
        case .authorizing: "마이크 권한 확인 중"
        case .starting: "녹음 준비 중"
        case .recording: "녹음 중"
        case .finalizing: "녹음 저장 중"
        case .interrupted: "녹음 중단됨"
        case .failed: "녹음을 시작하지 못했습니다"
        }
    }
    private func recordLabel(_ record: AudioManifest) -> String {
        if record.state == "failed" { return "가져오기 실패" }
        if record.sources.isEmpty { return "보존된 구간 없음" }
        if record.analysis != nil { return "원본 저장됨 · 분석 준비됨" }
        return record.analysisError == nil ? "원본 저장됨" : "원본 저장됨 · 분석 확인 필요"
    }
}
