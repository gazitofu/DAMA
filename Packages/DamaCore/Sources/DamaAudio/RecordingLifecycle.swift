import Foundation

/// Main-thread admission and shutdown order shared by recording and processing.
/// Recording never waits for inference to stop before starting its audio capture.
@MainActor public final class RecordingLifecycle {
    public private(set) var shuttingDown = false
    public init() {}

    public func allowsLocalInference(phase: CapturePhase, needsFinalization: Bool) -> Bool {
        !shuttingDown && !phase.busy && !needsFinalization
    }

    public func beginShutdown() -> Bool {
        guard !shuttingDown else { return false }
        shuttingDown = true
        return true
    }

    /// Even a failed recording save must drain local inference before replying.
    /// A false result keeps the app open so the original can be recovered.
    public func finishShutdown(saveRecording: () async -> Bool,
                               pauseLocalInference: () async -> Void) async -> Bool {
        guard shuttingDown else { return false }
        defer { shuttingDown = false }
        let saved = await saveRecording()
        await pauseLocalInference()
        return saved
    }
}
