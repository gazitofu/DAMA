import Foundation

public enum TranscriptionProvider: String, Codable, CaseIterable, Sendable {
    case pyannote, soniox
    public var title: String { self == .pyannote ? "pyannote + Whisper" : "Soniox" }
    public var destination: String { self == .pyannote ? "pyannote.ai" : "Soniox (api.soniox.com)" }
    public var model: String { self == .pyannote ? "faster-whisper-large-v3-turbo" : "stt-async-v5" }
    public var rawFilename: String { self == .pyannote ? "pyannote-response.json" : "soniox-response.json" }
}

extension EngineKind {
    public var title: String {
        switch self {
        case .managedPyannoteWhisper: "pyannote + Whisper"
        case .managedSoniox: "Soniox"
        case .hybridPyannoteWhisperKit: "pyannote + WhisperKit"
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
        if !input.context.isEmpty { general.append(["key": "topic", "value": input.context]) }
        if let people = input.participants, !people.isEmpty { general.append(["key": "participants", "value": people]) }
        let terms = (input.sonioxTerms ?? "").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let text = ([input.reference] + (input.referenceExcerpts ?? []).map(\.text)).filter { !$0.isEmpty }.joined(separator: "\n\n")
        var value: [String: Any] = [:]
        if !general.isEmpty { value["general"] = general }
        if !terms.isEmpty { value["terms"] = terms }
        if !text.isEmpty { value["text"] = text }
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= maximumContextBytes else { throw LibraryFailure.invalidInput }
        return bytes
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
