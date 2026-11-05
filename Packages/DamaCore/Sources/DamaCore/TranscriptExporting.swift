import Darwin
import Foundation

public enum TranscriptExportVersion: String, Equatable, Sendable {
    case automatic
    case current
}

public enum TranscriptExportFormat: String, Equatable, Sendable {
    case json
    case text
}

public struct TranscriptExportSelection: Equatable, Sendable {
    public let version: TranscriptExportVersion
    public let sessionId: String
    public let runId: String
    public let revisionId: String

    public init(
        version: TranscriptExportVersion,
        sessionId: String,
        runId: String,
        revisionId: String
    ) {
        self.version = version
        self.sessionId = sessionId
        self.runId = runId
        self.revisionId = revisionId
    }
}

public struct TranscriptExportResult: Sendable {
    public let selection: TranscriptExportSelection
    public let format: TranscriptExportFormat

    public init(selection: TranscriptExportSelection, format: TranscriptExportFormat) {
        self.selection = selection
        self.format = format
    }
}

public enum TranscriptExportFaultStage: String, Equatable, Sendable {
    case beforeTemporaryWrite
    case beforeDestinationReplacement
}

public typealias TranscriptExportFaultInjector = @Sendable (TranscriptExportFaultStage) throws -> Void

public struct TranscriptExportError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable {
        case invalidSelection
        case invalidDocument
        case unsafeDestination
        case writeFailure
    }

    public let code: Code
    public let context: String

    public init(code: Code, context: String) {
        self.code = code
        self.context = context
    }

    public var description: String {
        "Transcript export error \(code.rawValue) for \(context)"
    }
}

public struct TranscriptExporter: Sendable {
    private let faultInjector: TranscriptExportFaultInjector?

    public init(faultInjector: TranscriptExportFaultInjector? = nil) {
        self.faultInjector = faultInjector
    }

    public func data(
        for document: TranscriptDocument,
        selection: TranscriptExportSelection,
        format: TranscriptExportFormat
    ) throws -> Data {
        do {
            try TranscriptValidator().validate(document)
        } catch {
            throw TranscriptExportError(code: .invalidDocument, context: "document")
        }
        guard selection.sessionId == document.sessionId,
              selection.runId == document.runId,
              selection.revisionId == document.revision.id else {
            throw TranscriptExportError(code: .invalidSelection, context: "version")
        }
        switch selection.version {
        case .automatic:
            guard !document.revision.humanEdited,
                  document.revision.baseRevisionId == nil else {
                throw TranscriptExportError(code: .invalidSelection, context: "automatic-version")
            }
        case .current:
            break
        }

        switch format {
        case .json:
            do {
                return try NormalizedTranscriptCodec.encode(document)
            } catch {
                throw TranscriptExportError(code: .invalidDocument, context: "json")
            }
        case .text:
            return Data(text(document, selection: selection).utf8)
        }
    }

    public func write(_ data: Data, to destinationURL: URL) throws {
        guard destinationURL.isFileURL, destinationURL.path.hasPrefix("/") else {
            throw TranscriptExportError(code: .unsafeDestination, context: "destination")
        }
        let destination = destinationURL.standardizedFileURL
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).export-\(UUID().uuidString).tmp"
        )
        do {
            try faultInjector?(.beforeTemporaryWrite)
            try data.write(to: temporary, options: [.withoutOverwriting])
            guard try Data(contentsOf: temporary) == data else {
                throw TranscriptExportError(code: .writeFailure, context: "temporary-file")
            }
            try faultInjector?(.beforeDestinationReplacement)
            guard rename(temporary.path, destination.path) == 0 else {
                throw TranscriptExportError(code: .writeFailure, context: "destination")
            }
        } catch let error as TranscriptExportError {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw TranscriptExportError(code: .writeFailure, context: "destination")
        }
    }

    private func text(
        _ document: TranscriptDocument,
        selection: TranscriptExportSelection
    ) -> String {
        let versionLabel = selection.version == .automatic ? "자동본" : "현재 수정본"
        let syntheticLabel = document.provenance.isSynthetic ? "합성 테스트 데이터" : "사용자 데이터"
        var lines = [
            "# DAMA 원문 스크립트",
            "# 데이터: \(syntheticLabel)",
            "# 선택 버전: \(versionLabel)",
            "# 세션: \(selection.sessionId)",
            "# Run: \(selection.runId)",
            "# Revision: \(selection.revisionId)",
            "# 엔진: \(document.provenance.engine.rawValue)",
            "# 주의: 공급자 화자 점수와 시간 정렬 점수는 정답 확률이 아닙니다.",
            ""
        ]
        let words = Dictionary(uniqueKeysWithValues: document.words.map { ($0.id, $0) })
        let speakers = Dictionary(uniqueKeysWithValues: document.speakers.map { ($0.id, $0) })
        let issues = Dictionary(uniqueKeysWithValues: document.reviewIssues.map { ($0.id, $0) })
        let regularIntervals = Dictionary(
            uniqueKeysWithValues: document.diarization.map { ($0.id, $0) }
        )
        let exclusiveIntervals = Dictionary(
            uniqueKeysWithValues: document.exclusiveDiarization.map { ($0.id, $0) }
        )

        for turn in document.turns {
            let range: String
            if turn.startUs == nil || turn.endUs == nil {
                range = TranscriptTimePresentation.unavailable
            } else {
                range = "\(TranscriptTimePresentation.timestamp(turn.startUs))–\(TranscriptTimePresentation.timestamp(turn.endUs))"
            }
            let speaker = turn.speakerId.flatMap { speakers[$0]?.displayName } ?? "화자 미확정"
            lines.append("[\(range)] \(speaker)")

            let turnWords = turn.wordIds.compactMap { words[$0] }
            if turn.kind == .missingSpeech {
                lines.append(turn.markerText ?? "")
            } else {
                lines.append(turnWords.map { $0.prefix + ($0.editedText ?? $0.text) }.joined())
            }

            let issueIDs = orderedUnique(turn.reviewIssueIds + turnWords.flatMap(\.reviewIssueIds))
            for issueID in issueIDs {
                if let issue = issues[issueID] {
                    lines.append("불확실성: \(issue.kind.rawValue) (\(issue.status.rawValue))")
                }
            }
            if turnWords.contains(where: \.overlap) {
                lines.append("불확실성: 겹침 감지 — 모든 화자의 발화가 전사되었다는 보장이 없습니다.")
            }
            if turn.speakerId == nil {
                lines.append("불확실성: 화자 미확정")
            }
            if turnWords.contains(where: {
                $0.editedText != nil && $0.timingOrigin == .inheritedUnaligned
            }) {
                lines.append("시간 재정렬 안 됨")
            }

            let issueIntervalIDs = issueIDs.flatMap { issues[$0]?.sourceIntervalIds ?? [] }
            let intervalIDs = orderedUnique(
                turnWords.flatMap(\.sourceIntervalIds) + issueIntervalIDs
            )
            for intervalID in intervalIDs {
                let interval: DiarizationInterval
                let source: String
                if let regular = regularIntervals[intervalID] {
                    interval = regular
                    source = "일반"
                } else if let exclusive = exclusiveIntervals[intervalID] {
                    interval = exclusive
                    source = "배타적"
                } else {
                    continue
                }
                let range = "\(TranscriptTimePresentation.timestamp(interval.startUs))–\(TranscriptTimePresentation.timestamp(interval.endUs))"
                let confidence: String
                if let map = interval.confidence {
                    let entries = map.keys.sorted().map { key in "\(key)=\(map[key]!)" }
                    confidence = entries.isEmpty ? "{}" : entries.joined(separator: ", ")
                } else {
                    confidence = "미제공"
                }
                lines.append(
                    "근거 구간 \(interval.id) [\(range)] \(source) — 공급자 화자 점수: \(confidence)"
                )
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
