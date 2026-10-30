import Foundation

/// Soniox tokens + local Nemotron 3 probabilities -> `soniox-nemotron-word-v1`.
/// Interval evidence follows `nemotron-intervals-v1`; word assignment is the approved B2 (v4) policy unchanged.
public enum SonioxNemotronReconciler {
    public static let version = "soniox-nemotron-word-v1"
    public static let diarizationModel = "nemotron-3-diarization-coreml-offline"

    public static func normalize(soniox: Data, probabilities: Data, frameCount: Int, channels: Int,
                                 sonioxJobID: String, sessionID: String, runID: String, durationUs: Int64,
                                 audioSHA256: String, model: String, createdAt: String,
                                 synthetic: Bool = false, captureInterrupted: Bool = false) throws -> TranscriptDocument {
        guard UUID(uuidString: runID) != nil else { throw LibraryFailure.invalidInput }
        let source = try SonioxNormalizer.normalize(soniox, jobID: sonioxJobID, sessionID: sessionID,
            runID: runID, durationUs: durationUs, audioSHA256: audioSHA256, model: model,
            synthetic: synthetic, createdAt: createdAt)
        let values = try NemotronIntervals.decode(f32: probabilities, frameCount: frameCount, channels: channels)
        let evidence = try NemotronIntervals.derive(probabilities: values, frameCount: frameCount, channels: channels,
                                                    durationUs: durationUs, runID: runID)
        let base = try SonioxDiarizationNormalizer.normalize(source: source, speakers: evidence.speakers,
            regular: evidence.regular, exclusive: evidence.exclusive, engine: .hybridSonioxNemotron,
            diarizationModel: diarizationModel, version: version, sessionID: sessionID, runID: runID,
            durationUs: durationUs, audioSHA256: audioSHA256, model: model, createdAt: createdAt,
            synthetic: synthetic, captureInterrupted: captureInterrupted, providerWarning: false)
        return try SonioxPrecisionReconciler.applying(base, runID: runID, createdAt: createdAt,
            policy: .wordRepair, version: version, keepsSpeakerIDs: true)
    }
}
