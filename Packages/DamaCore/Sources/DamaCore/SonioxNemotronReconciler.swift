import Foundation

/// Soniox tokens + local Nemotron 3 probabilities. Word assignment is the approved B2 (v4) policy;
/// v1/v2 differ in how the exclusive intervals are derived, v3 adds split-word unification (spec r3),
/// v4 adds in-word unknown fragment filling (D-01) and in-word Turn continuity (D-03) (turn-continuity 2026-11-17).
public enum SonioxNemotronReconciler {
    public enum Version: String, Sendable, CaseIterable {
        case v1 = "soniox-nemotron-word-v1"
        case v2 = "soniox-nemotron-word-v2"
        case v3 = "soniox-nemotron-word-v3"
        case v4 = "soniox-nemotron-word-v4"
        var rule: NemotronIntervals.Rule { self == .v1 ? .singleActive : .mostProbable }
        var unifiesSplitWords: Bool { self == .v3 || self == .v4 }
        var continuesWords: Bool { self == .v4 }
    }
    /// New runs (2026-11-17 turn-continuity); stored v1/v2/v3 runs keep reproducing with their own version.
    public static let currentVersion = Version.v4
    public static let version = currentVersion.rawValue
    public static let diarizationModel = "nemotron-3-diarization-coreml-offline"
    /// INV-06 단서 (turn-continuity D-03): 이 결과의 Turn이 어절 안 같은 화자 사이 다른 화자 구간을 장벽으로 보지 않는 버전인가.
    static func continuesWithinWords(_ provenance: TranscriptProvenance) -> Bool {
        provenance.engine == .hybridSonioxNemotron && Version(rawValue: provenance.algorithmVersion)?.continuesWords == true
    }

    public static func normalize(soniox: Data, probabilities: Data, frameCount: Int, channels: Int,
                                 sonioxJobID: String, sessionID: String, runID: String, durationUs: Int64,
                                 audioSHA256: String, model: String, createdAt: String,
                                 synthetic: Bool = false, captureInterrupted: Bool = false,
                                 version: Version = currentVersion) throws -> TranscriptDocument {
        guard UUID(uuidString: runID) != nil else { throw LibraryFailure.invalidInput }
        let source = try SonioxNormalizer.normalize(soniox, jobID: sonioxJobID, sessionID: sessionID,
            runID: runID, durationUs: durationUs, audioSHA256: audioSHA256, model: model,
            synthetic: synthetic, createdAt: createdAt)
        let values = try NemotronIntervals.decode(f32: probabilities, frameCount: frameCount, channels: channels)
        let evidence = try NemotronIntervals.derive(probabilities: values, frameCount: frameCount, channels: channels,
                                                    durationUs: durationUs, runID: runID, rule: version.rule)
        let base = try SonioxDiarizationNormalizer.normalize(source: source, speakers: evidence.speakers,
            regular: evidence.regular, exclusive: evidence.exclusive, engine: .hybridSonioxNemotron,
            diarizationModel: diarizationModel, version: version.rawValue, sessionID: sessionID, runID: runID,
            durationUs: durationUs, audioSHA256: audioSHA256, model: model, createdAt: createdAt,
            synthetic: synthetic, captureInterrupted: captureInterrupted, providerWarning: false)
        return try SonioxPrecisionReconciler.applying(base, runID: runID, createdAt: createdAt,
            policy: .wordRepair, version: version.rawValue, keepsSpeakerIDs: true, unifiesSplitWords: version.unifiesSplitWords,
            fillsWordFragments: version.continuesWords, continuesWithinWords: version.continuesWords)
    }
}
