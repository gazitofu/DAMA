import Foundation

public struct TranscriptContractError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable {
        case malformedJSON
        case typeMismatch
        case missingRequiredKey
        case unknownKey
        case decodingFailed
        case invalidValue
        case duplicateIdentifier
        case duplicateReference
        case danglingReference
        case invalidTimestamp
        case invalidTurnMembership
        case invalidBarrier
        case notSynthetic
        case ioFailure
    }

    public let code: Code
    public let path: String

    public init(code: Code, path: String) {
        self.code = code
        self.path = path
    }

    public var description: String {
        "Transcript contract error \(code.rawValue) at \(path)"
    }
}

public enum NormalizedTranscriptCodec {
    public static func decode(_ data: Data) throws -> TranscriptDocument {
        do {
            let raw = try JSONSerialization.jsonObject(with: data)
            try NormalizedJSONShape.validate(raw)
            let document = try JSONDecoder().decode(TranscriptDocument.self, from: data)
            try TranscriptValidator().validate(document)
            return document
        } catch let error as TranscriptContractError {
            throw error
        } catch let error as DecodingError {
            throw TranscriptContractError(
                code: .decodingFailed,
                path: Self.path(for: error)
            )
        } catch {
            throw TranscriptContractError(code: .malformedJSON, path: "$")
        }
    }

    public static func encode(_ document: TranscriptDocument) throws -> Data {
        try TranscriptValidator().validate(document)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(document)
            try NormalizedJSONShape.validate(JSONSerialization.jsonObject(with: data))
            return data
        } catch let error as TranscriptContractError {
            throw error
        } catch {
            throw TranscriptContractError(code: .decodingFailed, path: "$")
        }
    }

    private static func path(for error: DecodingError) -> String {
        let codingPath: [any CodingKey]
        switch error {
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            codingPath = context.codingPath
        case let .keyNotFound(key, context):
            codingPath = context.codingPath + [key]
        case let .dataCorrupted(context):
            codingPath = context.codingPath
        @unknown default:
            codingPath = []
        }
        return codingPath.reduce("$") { result, key in
            if let index = key.intValue { return "\(result)[\(index)]" }
            return "\(result).\(key.stringValue)"
        }
    }
}

public enum PyannoteJobDecoder {
    public static func decode(_ data: Data) throws -> PyannoteJobDTO {
        do {
            return try JSONDecoder().decode(PyannoteJobDTO.self, from: data)
        } catch let error as DecodingError {
            let path: String
            switch error {
            case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
                path = context.codingPath.reduce("$") { $0 + "." + $1.stringValue }
            case let .keyNotFound(key, context):
                path = (context.codingPath + [key]).reduce("$") { $0 + "." + $1.stringValue }
            @unknown default:
                path = "$"
            }
            throw TranscriptContractError(code: .decodingFailed, path: path)
        } catch {
            throw TranscriptContractError(code: .malformedJSON, path: "$")
        }
    }
}

public enum SyntheticTranscriptFixtureLoader {
    public static func load(data: Data) throws -> TranscriptDocument {
        let document = try NormalizedTranscriptCodec.decode(data)
        guard document.provenance.isSynthetic else {
            throw TranscriptContractError(code: .notSynthetic, path: "$.provenance.isSynthetic")
        }
        return document
    }

    public static func load(from url: URL) throws -> TranscriptDocument {
        do {
            return try load(data: Data(contentsOf: url))
        } catch let error as TranscriptContractError {
            throw error
        } catch {
            throw TranscriptContractError(code: .ioFailure, path: "$")
        }
    }
}

private enum NormalizedJSONShape {
    private static let root = [
        "schemaVersion", "sessionId", "runId", "durationUs", "language", "provenance",
        "speakers", "diarization", "exclusiveDiarization", "words", "turns",
        "reviewIssues", "revision"
    ]
    private static let speaker = ["id", "providerId", "displayName"]
    private static let interval = ["id", "startUs", "endUs", "speakerId", "confidence"]
    private static let word = [
        "id", "ordinal", "text", "editedText", "prefix", "startUs", "endUs",
        "modelSpeakerId", "speakerId", "assignmentSource", "alignmentScore", "overlap",
        "reviewIssueIds", "sourceIntervalIds", "timingOrigin", "tokenKind"
    ]
    private static let turn = [
        "id", "kind", "startUs", "endUs", "speakerId", "wordIds", "markerText",
        "reviewed", "reviewIssueIds"
    ]
    private static let issue = [
        "id", "kind", "startUs", "endUs", "severity", "status", "wordIds",
        "sourceIntervalIds"
    ]
    private static let provenance = [
        "engine", "diarizationModel", "asrModel", "createdAt", "algorithmVersion",
        "sourceAudioSHA256", "sampleRateHz", "isSynthetic"
    ]
    private static let revision = [
        "id", "baseRevisionId", "sourceRunId", "humanEdited", "savedAt"
    ]

    static func validate(_ value: Any) throws {
        let object = try exactObject(value, keys: root, path: "$")
        try exactObject(object["provenance"]!, keys: provenance, path: "$.provenance")
        try exactObject(object["revision"]!, keys: revision, path: "$.revision")
        try objects(object["speakers"]!, keys: speaker, path: "$.speakers")
        try objects(object["diarization"]!, keys: interval, path: "$.diarization", confidence: true)
        try objects(object["exclusiveDiarization"]!, keys: interval, path: "$.exclusiveDiarization", confidence: true)
        try objects(object["words"]!, keys: word, path: "$.words", optionalKeys: ["asrConfidence", "language"])
        try objects(object["turns"]!, keys: turn, path: "$.turns")
        try objects(object["reviewIssues"]!, keys: issue, path: "$.reviewIssues")
    }

    @discardableResult
    private static func exactObject(
        _ value: Any,
        keys: [String],
        path: String,
        optionalKeys: [String] = []
    ) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw TranscriptContractError(code: .typeMismatch, path: path)
        }
        let allowed = Set(keys + optionalKeys)
        if let missing = keys.first(where: { object[$0] == nil }) {
            throw TranscriptContractError(code: .missingRequiredKey, path: "\(path).\(missing)")
        }
        if object.keys.contains(where: { !allowed.contains($0) }) {
            throw TranscriptContractError(code: .unknownKey, path: path)
        }
        return object
    }

    private static func objects(
        _ value: Any,
        keys: [String],
        path: String,
        confidence: Bool = false,
        optionalKeys: [String] = []
    ) throws {
        guard let values = value as? [Any] else {
            throw TranscriptContractError(code: .typeMismatch, path: path)
        }
        for (index, value) in values.enumerated() {
            let itemPath = "\(path)[\(index)]"
            let object = try exactObject(value, keys: keys, path: itemPath, optionalKeys: optionalKeys)
            if confidence, let confidenceValue = object["confidence"], !(confidenceValue is NSNull),
               !(confidenceValue is [String: Any]) {
                throw TranscriptContractError(code: .typeMismatch, path: "\(itemPath).confidence")
            }
        }
    }
}
