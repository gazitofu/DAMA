import Foundation

public enum TranscriptionProvider: String, Codable, CaseIterable, Sendable {
    case pyannote, soniox, qwen
    public var title: String {
        switch self { case .pyannote: "pyannote + Whisper"; case .soniox: "Soniox"; case .qwen: "로컬 Qwen + Precision-2 (비교)" }
    }
    public var destination: String { self == .soniox ? "Soniox (api.soniox.com)" : "pyannote.ai" }
    public var model: String {
        switch self { case .pyannote: "faster-whisper-large-v3-turbo"; case .soniox: "stt-async-v5"; case .qwen: "Qwen3-ASR-1.7B + Qwen3-ForcedAligner-0.6B" }
    }
    public var rawFilename: String { self == .soniox ? "soniox-response.json" : "pyannote-response.json" }
}

extension EngineKind {
    public var title: String {
        switch self {
        case .managedPyannoteWhisper: "pyannote + Whisper"
        case .managedSoniox: "Soniox"
        case .hybridPyannoteWhisperKit: "pyannote + WhisperKit"
        case .hybridPyannoteQwen: "로컬 Qwen + Precision-2"
        }
    }
}

public enum SonioxRequest {
    public static let maximumDurationUs: Int64 = 300 * 60 * 1_000_000
    // Conservative application byte budget, not a measured tokenizer/API limit.
    public static let maximumContextBytes = 7_500
    public static func context(_ input: ConversionNotes) throws -> Data? {
        guard input.provider == .soniox, input.sonioxContext == true else { return nil }
        var general: [[String: String]] = []
        if let count = input.sonioxSpeakerCountHint {
            guard (1...15).contains(count) else { throw LibraryFailure.invalidInput }
            general.append(["key": "speakers", "value": "\(count) speakers"])
        }
        if !input.context.isEmpty { general.append(["key": "topic", "value": input.context]) }
        if let people = input.participants, !people.isEmpty { general.append(["key": "participants", "value": people]) }
        let terms = (input.sonioxTerms ?? "").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let text = ([input.reference] + (input.sonioxReferenceExcerpts ?? input.referenceExcerpts ?? []).map(\.text)).filter { !$0.isEmpty }.joined(separator: "\n\n")
        var value: [String: Any] = [:]
        if !general.isEmpty { value["general"] = general }
        if !terms.isEmpty { value["terms"] = terms }
        if !text.isEmpty { value["text"] = text }
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= maximumContextBytes else { throw LibraryFailure.invalidInput }
        return bytes
    }
    /// Used only for a new request, never when resuming or rendering an older Run.
    public static func prepare(_ input: ConversionNotes, includeFolder: Bool) throws -> ConversionNotes {
        var result = input
        result.sonioxReferenceExcerpts = []
        result.sonioxOmittedReferences = []
        result.sonioxSpeakerCountHint = nil
        guard input.provider == .soniox, input.sonioxContext == true else { return result }
        result.sonioxSpeakerCountHint = input.speakerCount
        _ = try context(result) // Basic context/terms must fit intact; never silently truncate them.
        for excerpt in input.referenceExcerpts ?? [] {
            guard includeFolder else { result.sonioxOmittedReferences?.append(excerpt.name); continue }
            var candidate = result
            candidate.sonioxReferenceExcerpts?.append(excerpt)
            if (try? context(candidate)) != nil { result = candidate }
            else { result.sonioxOmittedReferences?.append(excerpt.name) }
        }
        return result
    }
    public static func payload(fileID: String, runID: String, input: ConversionNotes) throws -> Data {
        guard UUID(uuidString: fileID) != nil, UUID(uuidString: runID) != nil else { throw LibraryFailure.invalidInput }
        var value: [String: Any] = ["model": TranscriptionProvider.soniox.model, "file_id": fileID,
            "language_hints": ["ko", "en"], "enable_speaker_diarization": true,
            "enable_language_identification": true, "client_reference_id": runID]
        if let context = try context(input) { value["context"] = try JSONSerialization.jsonObject(with: context) }
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
