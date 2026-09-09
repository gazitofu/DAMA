// Dama v1 handoff contracts; not a complete app.
// Foundation-only declarations. Actual capture/network/WhisperKit adapters are not implemented.
import Foundation

// Export v1 requires explicit JSON null for nullable fields.
// Synthesized encodeIfPresent would omit these keys and violate the schema.
private extension KeyedEncodingContainer {
    mutating func encodeRequiredNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) }
        else { try encodeNil(forKey: key) }
    }
}

public typealias Microseconds = Int64

public struct Speaker: Codable, Sendable {
    public var id: String
    public var providerId: String
    public var displayName: String
}

public struct DiarizationInterval: Codable, Sendable {
    public var id: String
    public var startUs: Microseconds
    public var endUs: Microseconds
    public var speakerId: String
    // Keys are provider speaker labels; map through Speaker.providerId.
    public var confidence: [String: Double]?

    private enum CodingKeys: String, CodingKey {
        case id, startUs, endUs, speakerId, confidence
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startUs, forKey: .startUs)
        try container.encode(endUs, forKey: .endUs)
        try container.encode(speakerId, forKey: .speakerId)
        try container.encodeRequiredNullable(confidence, forKey: .confidence)
    }
}

public enum AssignmentSource: String, Codable, Sendable {
    case provider, reconciled, user, unknown
}
public enum TimingOrigin: String, Codable, Sendable {
    case model, userSelected, inheritedUnaligned, none
}
public enum TokenKind: String, Codable, Sendable { case lexical, punctuation }
public enum EngineKind: String, Codable, Sendable {
    case managedPyannoteWhisper, hybridPyannoteWhisperKit
}

public struct TranscriptWord: Codable, Sendable {
    public var id: String
    public var ordinal: Int
    public var text: String
    public var editedText: String?
    public var prefix: String
    public var startUs: Microseconds?
    public var endUs: Microseconds?
    public var modelSpeakerId: String?
    public var speakerId: String?
    public var assignmentSource: AssignmentSource
    public var alignmentScore: Double?
    public var overlap: Bool
    public var reviewIssueIds: [String]
    public var sourceIntervalIds: [String]
    public var timingOrigin: TimingOrigin
    public var tokenKind: TokenKind

    private enum CodingKeys: String, CodingKey {
        case id, ordinal, text, editedText, prefix, startUs, endUs, modelSpeakerId, speakerId, assignmentSource, alignmentScore, overlap, reviewIssueIds, sourceIntervalIds, timingOrigin, tokenKind
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encode(text, forKey: .text)
        try container.encodeRequiredNullable(editedText, forKey: .editedText)
        try container.encode(prefix, forKey: .prefix)
        try container.encodeRequiredNullable(startUs, forKey: .startUs)
        try container.encodeRequiredNullable(endUs, forKey: .endUs)
        try container.encodeRequiredNullable(modelSpeakerId, forKey: .modelSpeakerId)
        try container.encodeRequiredNullable(speakerId, forKey: .speakerId)
        try container.encode(assignmentSource, forKey: .assignmentSource)
        try container.encodeRequiredNullable(alignmentScore, forKey: .alignmentScore)
        try container.encode(overlap, forKey: .overlap)
        try container.encode(reviewIssueIds, forKey: .reviewIssueIds)
        try container.encode(sourceIntervalIds, forKey: .sourceIntervalIds)
        try container.encode(timingOrigin, forKey: .timingOrigin)
        try container.encode(tokenKind, forKey: .tokenKind)
    }
}

public enum TurnKind: String, Codable, Sendable { case speech, missingSpeech }
public struct TranscriptTurn: Codable, Sendable {
    public var id: String
    public var kind: TurnKind
    public var startUs: Microseconds?
    public var endUs: Microseconds?
    public var speakerId: String?
    public var wordIds: [String]
    public var markerText: String?
    public var reviewed: Bool
    public var reviewIssueIds: [String]

    private enum CodingKeys: String, CodingKey {
        case id, kind, startUs, endUs, speakerId, wordIds, markerText, reviewed, reviewIssueIds
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeRequiredNullable(startUs, forKey: .startUs)
        try container.encodeRequiredNullable(endUs, forKey: .endUs)
        try container.encodeRequiredNullable(speakerId, forKey: .speakerId)
        try container.encode(wordIds, forKey: .wordIds)
        try container.encodeRequiredNullable(markerText, forKey: .markerText)
        try container.encode(reviewed, forKey: .reviewed)
        try container.encode(reviewIssueIds, forKey: .reviewIssueIds)
    }
}
public enum IssueKind: String, Codable, Sendable {
    case ambiguous_speaker, overlapping_speech, missing_speech
    case boundary_conflict, unrepresented_speaker, invalid_timestamp
    case low_confidence, capture_interrupted, partial_result
}
public enum IssueSeverity: String, Codable, Sendable { case info, warning, error }
public enum IssueStatus: String, Codable, Sendable { case open, resolved, acknowledged }
public struct ReviewIssue: Codable, Sendable {
    public var id: String
    public var kind: IssueKind
    public var startUs: Microseconds?
    public var endUs: Microseconds?
    public var severity: IssueSeverity
    public var status: IssueStatus
    public var wordIds: [String]
    public var sourceIntervalIds: [String]

    private enum CodingKeys: String, CodingKey {
        case id, kind, startUs, endUs, severity, status, wordIds, sourceIntervalIds
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeRequiredNullable(startUs, forKey: .startUs)
        try container.encodeRequiredNullable(endUs, forKey: .endUs)
        try container.encode(severity, forKey: .severity)
        try container.encode(status, forKey: .status)
        try container.encode(wordIds, forKey: .wordIds)
        try container.encode(sourceIntervalIds, forKey: .sourceIntervalIds)
    }
}
public struct TranscriptProvenance: Codable, Sendable {
    public var engine: EngineKind
    public var diarizationModel: String
    public var asrModel: String
    public var createdAt: String // ISO 8601; validate at the boundary.
    public var algorithmVersion: String
    public var sourceAudioSHA256: String?
    public var sampleRateHz: Int
    public var isSynthetic: Bool

    private enum CodingKeys: String, CodingKey {
        case engine, diarizationModel, asrModel, createdAt, algorithmVersion, sourceAudioSHA256, sampleRateHz, isSynthetic
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(engine, forKey: .engine)
        try container.encode(diarizationModel, forKey: .diarizationModel)
        try container.encode(asrModel, forKey: .asrModel)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(algorithmVersion, forKey: .algorithmVersion)
        try container.encodeRequiredNullable(sourceAudioSHA256, forKey: .sourceAudioSHA256)
        try container.encode(sampleRateHz, forKey: .sampleRateHz)
        try container.encode(isSynthetic, forKey: .isSynthetic)
    }
}
public struct RevisionMetadata: Codable, Sendable {
    public var id: String
    public var baseRevisionId: String?
    public var sourceRunId: String
    public var humanEdited: Bool
    public var savedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, baseRevisionId, sourceRunId, humanEdited, savedAt
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeRequiredNullable(baseRevisionId, forKey: .baseRevisionId)
        try container.encode(sourceRunId, forKey: .sourceRunId)
        try container.encode(humanEdited, forKey: .humanEdited)
        try container.encode(savedAt, forKey: .savedAt)
    }
}
public struct TranscriptDocument: Codable, Sendable {
    public var schemaVersion: String
    public var sessionId: String
    public var runId: String
    public var durationUs: Microseconds
    public var language: String
    public var provenance: TranscriptProvenance
    public var speakers: [Speaker]
    public var diarization: [DiarizationInterval]
    public var exclusiveDiarization: [DiarizationInterval]
    public var words: [TranscriptWord]
    public var turns: [TranscriptTurn]
    public var reviewIssues: [ReviewIssue]
    public var revision: RevisionMetadata
}

// Vendor DTOs are deliberately separate from normalized export types.
public struct PyannoteDiarizationDTO: Decodable, Sendable {
    public var start: Double
    public var end: Double
    public var speaker: String
    public var confidence: [String: Double]?
}
public struct PyannoteTranscriptionDTO: Decodable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String
}
public struct PyannoteOutputDTO: Decodable, Sendable {
    public var diarization: [PyannoteDiarizationDTO]
    public var exclusiveDiarization: [PyannoteDiarizationDTO]?
    public var wordLevelTranscription: [PyannoteTranscriptionDTO]?
    public var turnLevelTranscription: [PyannoteTranscriptionDTO]?
    public var warning: String?
    public var error: String?
}
public struct PyannoteJobDTO: Decodable, Sendable {
    public var jobId: String
    public var status: String // Preserve unknown future provider states.
    public var createdAt: String?
    public var updatedAt: String?
    public var output: PyannoteOutputDTO?
}

public enum SpeakerCountConstraint: Sendable {
    case automatic
    case exact(Int)
    case range(minimum: Int?, maximum: Int?)
    // Adapter MUST validate positive counts and minimum <= maximum.
}
public struct EngineInput: Sendable {
    public var sessionId: String
    public var runId: String
    public var analysisAudioURL: URL
    public var durationUs: Microseconds
    public var speakerCount: SpeakerCountConstraint
    public var uploadAllowed: Bool // Resolved session policy, not implicit permission.
}
public struct ProcessingProgress: Sendable {
    public var stage: String
    public var fraction: Double? // nil for indeterminate remote processing.
}
public protocol TranscriptEngine: Sendable {
    var kind: EngineKind { get }
    func process(
        _ input: EngineInput,
        progress: @escaping @Sendable (ProcessingProgress) async -> Void
    ) async throws -> TranscriptDocument
}
public protocol TranscriptRepository: Sendable {
    func load(sessionId: String, revisionId: String?) async throws -> TranscriptDocument
    func commitRevision(_ document: TranscriptDocument) async throws
}
