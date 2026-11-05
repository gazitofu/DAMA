import Foundation

/// Uses token time, never a wholesale replacement of Soniox speaker IDs.
public enum SonioxPrecisionNormalizer {
    public static let version = "soniox-p2-v2"
    public static func normalize(soniox: Data, diarization: Data, sonioxJobID: String,
                                 sessionID: String, runID: String, durationUs: Int64,
                                 audioSHA256: String, model: String, createdAt: String,
                                 synthetic: Bool = false, captureInterrupted: Bool = false) throws -> TranscriptDocument {
        let source = try SonioxNormalizer.normalize(soniox, jobID: sonioxJobID, sessionID: sessionID,
            runID: runID, durationUs: durationUs, audioSHA256: audioSHA256, model: model,
            synthetic: synthetic, createdAt: createdAt)
        let job = try JSONDecoder().decode(PyannoteJobDTO.self, from: diarization)
        guard job.status == "succeeded", let output = job.output, output.error == nil,
              let exclusiveSource = output.exclusiveDiarization else { throw ManagedNormalizationError.partialResult }
        let labels = Set((output.diarization + exclusiveSource).map(\.speaker)).sorted()
        let speakers = labels.enumerated().map {
            Speaker(id: "\(runID)-p2-\($0.offset)", providerId: $0.element, displayName: "화자 \($0.offset + 1)")
        }
        let mapping = Dictionary(uniqueKeysWithValues: speakers.map { ($0.providerId, $0.id) })
        let regular = try P2TimeEvidence.intervals(output.diarization, prefix: "d", mapping: mapping, durationUs: durationUs)
        let exclusive = try P2TimeEvidence.intervals(exclusiveSource, prefix: "e", mapping: mapping, durationUs: durationUs)
        return try SonioxDiarizationNormalizer.normalize(source: source, speakers: speakers, regular: regular,
            exclusive: exclusive, engine: .hybridSonioxPyannote, diarizationModel: "precision-2", version: version,
            sessionID: sessionID, runID: runID, durationUs: durationUs, audioSHA256: audioSHA256, model: model,
            createdAt: createdAt, synthetic: synthetic, captureInterrupted: captureInterrupted,
            providerWarning: output.warning != nil)
    }
}
