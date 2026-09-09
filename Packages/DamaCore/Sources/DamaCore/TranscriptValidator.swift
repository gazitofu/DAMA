import Foundation

public struct TranscriptValidator: Sendable {
    public init() {}

    public func validate(_ document: TranscriptDocument) throws {
        try require(document.schemaVersion == "1.0", .invalidValue, "$.schemaVersion")
        try nonempty(document.sessionId, "$.sessionId")
        try nonempty(document.runId, "$.runId")
        try nonempty(document.language, "$.language")
        try require(document.durationUs >= 0, .invalidTimestamp, "$.durationUs")
        try validateProvenance(document.provenance)
        try validateRevision(document.revision, runId: document.runId)

        let speakers = try unique(document.speakers, path: "$.speakers", id: { $0.id })
        var providerIds = Set<String>()
        for (index, speaker) in document.speakers.enumerated() {
            try nonempty(speaker.id, "$.speakers[\(index)].id")
            try nonempty(speaker.providerId, "$.speakers[\(index)].providerId")
            try nonempty(speaker.displayName, "$.speakers[\(index)].displayName")
            try require(providerIds.insert(speaker.providerId).inserted, .duplicateIdentifier,
                        "$.speakers[\(index)].providerId")
        }

        let regular = document.diarization
        let exclusive = document.exclusiveDiarization
        let intervals = try unique(regular + exclusive, path: "$.intervals", id: { $0.id })
        for (index, interval) in (regular + exclusive).enumerated() {
            let path = "$.intervals[\(index)]"
            try nonempty(interval.id, "\(path).id")
            try requiredTimes(interval.startUs, interval.endUs, duration: document.durationUs, path: path)
            try require(interval.endUs > interval.startUs, .invalidTimestamp, path)
            try known(interval.speakerId, in: speakers, path: "\(path).speakerId")
            if let confidence = interval.confidence {
                for (label, score) in confidence {
                    try nonempty(label, "\(path).confidence")
                    try require(providerIds.contains(label), .danglingReference, "\(path).confidence")
                    try require(score.isFinite && (0...100).contains(score), .invalidValue,
                                "\(path).confidence")
                }
            }
        }
        try validateExclusive(exclusive)

        let words = try unique(document.words, path: "$.words", id: { $0.id })
        let issues = try unique(document.reviewIssues, path: "$.reviewIssues", id: { $0.id })
        _ = try unique(document.turns, path: "$.turns", id: { $0.id })
        var ordinals = Set<Int>()
        var previousOrdinal: Int?
        for (index, word) in document.words.enumerated() {
            let path = "$.words[\(index)]"
            try nonempty(word.id, "\(path).id")
            try require(word.ordinal >= 0, .invalidValue, "\(path).ordinal")
            try require(ordinals.insert(word.ordinal).inserted, .duplicateIdentifier, "\(path).ordinal")
            if let previousOrdinal {
                try require(previousOrdinal < word.ordinal, .invalidValue, "\(path).ordinal")
            }
            previousOrdinal = word.ordinal
            try optionalTimes(word.startUs, word.endUs, duration: document.durationUs, path: path)
            if let speakerId = word.modelSpeakerId {
                try known(speakerId, in: speakers, path: "\(path).modelSpeakerId")
            }
            if let speakerId = word.speakerId {
                try known(speakerId, in: speakers, path: "\(path).speakerId")
            }
            if word.assignmentSource == .unknown {
                try require(word.speakerId == nil, .invalidValue, "\(path).speakerId")
            }
            if word.editedText != nil {
                try require(word.timingOrigin != .model, .invalidValue, "\(path).timingOrigin")
            }
            if let score = word.alignmentScore {
                try require(score.isFinite && (0...1).contains(score), .invalidValue,
                            "\(path).alignmentScore")
            }
            try references(word.reviewIssueIds, known: issues, path: "\(path).reviewIssueIds")
            try references(word.sourceIntervalIds, known: intervals, path: "\(path).sourceIntervalIds")
        }

        try validateIssues(document.reviewIssues, words: words, intervals: intervals,
                           duration: document.durationUs)
        try validateTurns(document, words: words, speakers: speakers, issues: issues)
    }

    private func validateProvenance(_ value: TranscriptProvenance) throws {
        try nonempty(value.diarizationModel, "$.provenance.diarizationModel")
        try nonempty(value.asrModel, "$.provenance.asrModel")
        try nonempty(value.algorithmVersion, "$.provenance.algorithmVersion")
        try date(value.createdAt, "$.provenance.createdAt")
        try require(value.sampleRateHz > 0, .invalidValue, "$.provenance.sampleRateHz")
        if let hash = value.sourceAudioSHA256 {
            let valid = hash.utf8.count == 64 && hash.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            }
            try require(valid, .invalidValue, "$.provenance.sourceAudioSHA256")
        }
    }

    private func validateRevision(_ value: RevisionMetadata, runId: String) throws {
        try nonempty(value.id, "$.revision.id")
        if let base = value.baseRevisionId { try nonempty(base, "$.revision.baseRevisionId") }
        try nonempty(value.sourceRunId, "$.revision.sourceRunId")
        try require(value.sourceRunId == runId, .invalidValue, "$.revision.sourceRunId")
        try date(value.savedAt, "$.revision.savedAt")
    }

    private func validateExclusive(_ intervals: [DiarizationInterval]) throws {
        for leftIndex in intervals.indices {
            for rightIndex in intervals.indices where rightIndex > leftIndex {
                let left = intervals[leftIndex]
                let right = intervals[rightIndex]
                if left.speakerId != right.speakerId {
                    try require(!overlaps(left.startUs, left.endUs, right.startUs, right.endUs),
                                .invalidValue, "$.exclusiveDiarization[\(rightIndex)]")
                }
            }
        }
    }

    private func validateIssues(
        _ values: [ReviewIssue],
        words: [String: TranscriptWord],
        intervals: [String: DiarizationInterval],
        duration: Microseconds
    ) throws {
        for (index, issue) in values.enumerated() {
            let path = "$.reviewIssues[\(index)]"
            try nonempty(issue.id, "\(path).id")
            try optionalTimes(issue.startUs, issue.endUs, duration: duration, path: path)
            try references(issue.wordIds, known: words, path: "\(path).wordIds")
            try references(issue.sourceIntervalIds, known: intervals, path: "\(path).sourceIntervalIds")
        }
    }

    private func validateTurns(
        _ document: TranscriptDocument,
        words: [String: TranscriptWord],
        speakers: [String: Speaker],
        issues: [String: ReviewIssue]
    ) throws {
        var ownership: [String: Int] = [:]
        let markers = document.turns.filter { $0.kind == .missingSpeech }
        let interrupted = document.reviewIssues.filter { $0.kind == .capture_interrupted }

        for (index, turn) in document.turns.enumerated() {
            let path = "$.turns[\(index)]"
            try nonempty(turn.id, "\(path).id")
            try optionalTimes(turn.startUs, turn.endUs, duration: document.durationUs, path: path)
            if let speakerId = turn.speakerId {
                try known(speakerId, in: speakers, path: "\(path).speakerId")
            }
            try references(turn.reviewIssueIds, known: issues, path: "\(path).reviewIssueIds")
            try noDuplicates(turn.wordIds, path: "\(path).wordIds")

            if turn.kind == .missingSpeech {
                try require(turn.wordIds.isEmpty && !(turn.markerText ?? "").isEmpty,
                            .invalidTurnMembership, path)
                continue
            }
            try require(!turn.wordIds.isEmpty && turn.markerText == nil,
                        .invalidTurnMembership, path)

            var selected: [TranscriptWord] = []
            for (wordIndex, wordId) in turn.wordIds.enumerated() {
                guard let word = words[wordId] else {
                    throw TranscriptContractError(code: .danglingReference,
                                                  path: "\(path).wordIds[\(wordIndex)]")
                }
                ownership[wordId, default: 0] += 1
                try require(word.speakerId == turn.speakerId, .invalidTurnMembership,
                            "\(path).wordIds[\(wordIndex)]")
                if let wordStart = word.startUs, let wordEnd = word.endUs {
                    guard let turnStart = turn.startUs, let turnEnd = turn.endUs else {
                        throw TranscriptContractError(code: .invalidTimestamp, path: path)
                    }
                    try require(turnStart <= wordStart && wordEnd <= turnEnd,
                                .invalidTimestamp, "\(path).wordIds[\(wordIndex)]")
                }
                selected.append(word)
            }
            for pairIndex in 1..<selected.count {
                let previous = selected[pairIndex - 1]
                let current = selected[pairIndex]
                try require(previous.ordinal < current.ordinal, .invalidTurnMembership,
                            "\(path).wordIds[\(pairIndex)]")
                if let previousStart = previous.startUs, let currentStart = current.startUs {
                    try require(previousStart <= currentStart, .invalidTimestamp,
                                "\(path).wordIds[\(pairIndex)]")
                }
                try validateBarrier(
                    previous: previous,
                    current: current,
                    markers: markers,
                    interrupted: interrupted,
                    diarization: document.diarization,
                    path: "\(path).wordIds[\(pairIndex)]"
                )
            }
        }

        for (index, word) in document.words.enumerated() {
            try require(ownership[word.id] == 1, .invalidTurnMembership, "$.words[\(index)].id")
        }
    }

    private func validateBarrier(
        previous: TranscriptWord,
        current: TranscriptWord,
        markers: [TranscriptTurn],
        interrupted: [ReviewIssue],
        diarization: [DiarizationInterval],
        path: String
    ) throws {
        guard let previousEnd = previous.endUs, let currentStart = current.startUs,
              previousEnd <= currentStart else { return }

        let timedMarkers = markers.compactMap { marker -> (Microseconds, Microseconds)? in
            guard let start = marker.startUs, let end = marker.endUs else { return nil }
            return (start, end)
        }
        try require(!timedMarkers.contains { overlaps(previousEnd, currentStart, $0.0, $0.1) },
                    .invalidBarrier, path)

        let timedInterruptions = interrupted.compactMap { issue -> (Microseconds, Microseconds)? in
            guard let start = issue.startUs, let end = issue.endUs else { return nil }
            return (start, end)
        }
        try require(!timedInterruptions.contains { overlaps(previousEnd, currentStart, $0.0, $0.1) },
                    .invalidBarrier, path)

        if let previousModel = previous.modelSpeakerId, let currentModel = current.modelSpeakerId {
            try require(previousModel == currentModel, .invalidBarrier, path)
            let interveningChange = diarization.contains { interval in
                interval.speakerId != previousModel &&
                    overlaps(previousEnd, currentStart, interval.startUs, interval.endUs)
            }
            try require(!interveningChange, .invalidBarrier, path)
        }
    }

    private func unique<T>(
        _ values: [T],
        path: String,
        id: (T) -> String
    ) throws -> [String: T] {
        var result: [String: T] = [:]
        for (index, value) in values.enumerated() {
            let identifier = id(value)
            try nonempty(identifier, "\(path)[\(index)].id")
            guard result[identifier] == nil else {
                throw TranscriptContractError(code: .duplicateIdentifier, path: "\(path)[\(index)].id")
            }
            result[identifier] = value
        }
        return result
    }

    private func references<T>(_ values: [String], known: [String: T], path: String) throws {
        try noDuplicates(values, path: path)
        for (index, value) in values.enumerated() {
            try nonempty(value, "\(path)[\(index)]")
            guard known[value] != nil else {
                throw TranscriptContractError(code: .danglingReference, path: "\(path)[\(index)]")
            }
        }
    }

    private func noDuplicates(_ values: [String], path: String) throws {
        var seen = Set<String>()
        for (index, value) in values.enumerated() where !seen.insert(value).inserted {
            throw TranscriptContractError(code: .duplicateReference, path: "\(path)[\(index)]")
        }
    }

    private func optionalTimes(
        _ start: Microseconds?,
        _ end: Microseconds?,
        duration: Microseconds,
        path: String
    ) throws {
        if start == nil || end == nil {
            try require(start == nil && end == nil, .invalidTimestamp, path)
            return
        }
        try requiredTimes(start!, end!, duration: duration, path: path)
    }

    private func requiredTimes(
        _ start: Microseconds,
        _ end: Microseconds,
        duration: Microseconds,
        path: String
    ) throws {
        try require(start >= 0 && start <= end && end <= duration, .invalidTimestamp, path)
    }

    private func date(_ value: String, _ path: String) throws {
        try nonempty(value, path)
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try require(basic.date(from: value) != nil || fractional.date(from: value) != nil,
                    .invalidValue, path)
    }

    private func known<T>(_ value: String, in values: [String: T], path: String) throws {
        try nonempty(value, path)
        try require(values[value] != nil, .danglingReference, path)
    }

    private func nonempty(_ value: String, _ path: String) throws {
        try require(!value.isEmpty, .invalidValue, path)
    }

    private func require(
        _ condition: @autoclosure () -> Bool,
        _ code: TranscriptContractError.Code,
        _ path: String
    ) throws {
        guard condition() else { throw TranscriptContractError(code: code, path: path) }
    }

    private func overlaps(
        _ leftStart: Microseconds,
        _ leftEnd: Microseconds,
        _ rightStart: Microseconds,
        _ rightEnd: Microseconds
    ) -> Bool {
        max(leftStart, rightStart) < min(leftEnd, rightEnd)
    }
}
