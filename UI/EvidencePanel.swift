import DamaCore
import SwiftUI

struct EvidencePanel: View {
    @ObservedObject var workspace: ReviewWorkspace
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("판단 근거").font(.headline)
                if workspace.selectedTurn == nil && workspace.selectedWords.isEmpty {
                    Text("단어 또는 확인 구간을 선택하면 근거를 볼 수 있습니다.").foregroundStyle(.secondary)
                } else {
                    if let turn = workspace.selectedTurn, turn.kind == .missingSpeech {
                        section("현재 화자", workspace.speakerName(turn.speakerId))
                        section("전사 누락 의심", turn.markerText ?? "")
                        section("시간", timeRange(turn.startUs, turn.endUs))
                    }
                    ForEach(workspace.selectedWords, id: \.id) { word in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(word.editedText ?? word.text).font(.title3)
                            section("현재 화자", workspace.speakerName(word.speakerId))
                            section("모델 후보", workspace.speakerName(word.modelSpeakerId))
                            section("화자 지정", word.assignmentSource == .user ? "사용자 지정" : word.assignmentSource == .unknown ? "미확정" : "모델 지정")
                            section("모델 원문", word.text)
                            section("시간", timeRange(word.startUs, word.endUs))
                            section("시간 정렬 점수", word.alignmentScore.map { String($0) } ?? "미제공")
                            if word.timingOrigin == .inheritedUnaligned { Text("시간 재정렬 안 됨").font(.caption) }
                            if word.overlap {
                                Text("동시에 여러 화자가 감지되었습니다. 두 사람의 발화가 모두 전사되었다는 뜻은 아닙니다.")
                                    .font(.callout)
                            }
                        }
                        Divider()
                    }
                    Text("사람 확인").font(.headline)
                    if selectedIssues.isEmpty { Text("연결된 이슈 없음 · 정확도를 보장하지는 않습니다.").font(.caption) }
                    ForEach(selectedIssues, id: \.id) { issue in
                        Button { workspace.selectIssue(issue) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issueLabel(issue.kind))
                                Text(issue.status == .acknowledged ? "확인함" : issue.status == .open ? "미확인" : "해결됨")
                                    .fontWeight(.semibold)
                            }.font(.caption)
                        }.buttonStyle(.plain)
                    }
                    Divider()
                    Text("공급자 화자 점수").font(.headline)
                    Text("공급자 화자 점수와 시간 정렬 점수는 정답 확률이 아닙니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(intervals, id: \.id) { interval in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(interval.id).fontWeight(.medium)
                            Text(workspace.document?.diarization.contains { $0.id == interval.id } == true ? "일반 구간" : "배타적 구간")
                            Text(timeRange(interval.startUs, interval.endUs))
                                .font(.system(size: 12, design: .monospaced))
                            if let map = interval.confidence {
                                if map.isEmpty { Text("제공된 점수 항목 없음 ({})") }
                                ForEach(map.keys.sorted(), id: \.self) { key in
                                    Text("\(key): \(map[key].map { String($0) } ?? "미제공")")
                                }
                            } else { Text("미제공") }
                        }.font(.caption)
                    }
                    if intervals.isEmpty { Text("연결된 근거 구간 없음").font(.caption) }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    private func section(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout)
        }
    }
    private var selectedIssues: [ReviewIssue] {
        var ids = Set(workspace.selectedWords.flatMap(\.reviewIssueIds))
        if let id = workspace.selectedIssueID { ids.insert(id) }
        for id in workspace.selectedTurn?.reviewIssueIds ?? [] { ids.insert(id) }
        return workspace.document?.reviewIssues.filter { ids.contains($0.id) } ?? []
    }
    private var intervals: [DiarizationInterval] {
        guard let document = workspace.document else { return [] }
        let ids = Set(workspace.selectedWords.flatMap(\.sourceIntervalIds) + selectedIssues.flatMap(\.sourceIntervalIds))
        return (document.diarization + document.exclusiveDiarization).filter { ids.contains($0.id) }
            .sorted { $0.startUs == $1.startUs ? $0.id < $1.id : $0.startUs < $1.startUs }
    }
}
