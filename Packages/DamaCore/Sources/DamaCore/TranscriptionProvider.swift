import Foundation

public enum TranscriptionProvider: String, Codable, CaseIterable, Sendable {
    case pyannote, soniox, qwen, sonioxPrecision, precision, sonioxNemotron, nemotron
    /// pyannote-backed paths stay readable but are no longer offered (2026-10-30).
    public static var selectable: [Self] { [.sonioxNemotron, .soniox] }
    public static var operatingDefault: Self { .sonioxNemotron }
    /// A stored choice outside the current list falls back to the operating default; listed choices are kept.
    public static func operatingSelection(stored: String?) -> Self {
        guard let value = stored.flatMap(Self.init(rawValue:)), selectable.contains(value) else { return operatingDefault }
        return value
    }
    public var usesSoniox: Bool { self == .soniox || self == .sonioxPrecision || self == .sonioxNemotron }
    public func consumesContext(sonioxEnabled: Bool) -> Bool { self == .qwen || (usesSoniox && sonioxEnabled) }
    public func consumesSpeakerCount(sonioxEnabled: Bool) -> Bool { self != .soniox || sonioxEnabled }
    public var title: String {
        switch self { case .pyannote: "pyannote + Whisper (비교)"; case .soniox: "Soniox 단독 (비교)"; case .qwen: "로컬 Qwen + Precision-2 (비교)"; case .sonioxPrecision: "Soniox + Precision-2"; case .precision: "Precision-2 화자분리"
        case .sonioxNemotron: "Soniox + Nemotron 3 (운영)"; case .nemotron: "Nemotron 3 화자 분리" }
    }
    public var destination: String { [.soniox, .sonioxNemotron].contains(self) ? "Soniox (api.soniox.com)" : self == .nemotron ? "이 Mac" : "pyannote.ai" }
    public var model: String {
        switch self { case .pyannote: "faster-whisper-large-v3-turbo"; case .soniox, .sonioxPrecision, .sonioxNemotron: "stt-async-v5"; case .qwen: "Qwen3-ASR-1.7B + Qwen3-ForcedAligner-0.6B"; case .precision: "precision-2"
        case .nemotron: "nemotron-3-diarization-coreml-offline" }
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
        case .hybridSonioxPyannote: "Soniox + Precision-2"
        case .hybridSonioxNemotron: "Soniox + Nemotron 3"
        }
    }
}

public enum SonioxRequest {
    public static let maximumDurationUs: Int64 = 300 * 60 * 1_000_000
    // Conservative application byte budget, not a measured tokenizer/API limit.
    public static let maximumContextBytes = 7_500
    public static func context(_ input: ConversionNotes) throws -> Data? {
        guard input.provider.usesSoniox, input.sonioxContext == true else { return nil }
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
        guard input.provider.usesSoniox, input.sonioxContext == true else { return result }
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
