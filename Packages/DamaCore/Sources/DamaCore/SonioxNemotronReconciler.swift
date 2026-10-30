import Foundation

/// Soniox tokens + local Nemotron 3 probabilities. Word assignment is the approved B2 (v4) policy unchanged;
/// versions differ only in how the exclusive intervals are derived.
public enum SonioxNemotronReconciler {
    public enum Version: String, Sendable, CaseIterable {
        case v1 = "soniox-nemotron-word-v1"
        case v2 = "soniox-nemotron-word-v2"
        var rule: NemotronIntervals.Rule { self == .v1 ? .singleActive : .mostProbable }
    }
    /// New runs (2026-10-30 r2); v1 runs keep reproducing with v1.
    public static let version = Version.v2.rawValue
    public static let diarizationModel = "nemotron-3-diarization-coreml-offline"

    public static func normalize(soniox: Data, probabilities: Data, frameCount: Int, channels: Int,
                                 sonioxJobID: String, sessionID: String, runID: String, durationUs: Int64,
                                 audioSHA256: String, model: String, createdAt: String,
                                 synthetic: Bool = false, captureInterrupted: Bool = false,
                                 version: Version = .v2) throws -> TranscriptDocument {
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
            policy: .wordRepair, version: version.rawValue, keepsSpeakerIDs: true)
    }
}
