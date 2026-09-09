import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
public final class MicrophoneCapture: ObservableObject {
    @Published public private(set) var phase: CapturePhase = .idle
    @Published public private(set) var elapsedUs: Int64 = 0
    @Published public private(set) var level: Float = 0
    @Published public private(set) var message: String?
    @Published public private(set) var inputDescription = "시스템 기본 마이크"
    @Published public private(set) var lastSaved: AudioManifest?
    public var onSaved: ((AudioManifest) -> Void)?
    private var engine: AVAudioEngine?
    private var pool: CaptureBufferPool?
    private var writer: CaptureWriter?
    private var draining: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var engineObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var activity: NSObjectProtocol?
    private var root: URL?

    public init() {}

    public func toggle() {
        if phase == .recording { Task { _ = await stop() } }
        else if !phase.busy { start() }
    }

    public func start() {
        guard !phase.busy, !needsFinalization else { return }
        phase = phase.beginning()
        elapsedUs = 0
        level = 0
        message = nil
        lastSaved = nil
        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            let allowed: Bool
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
            else { allowed = status == .authorized }
            guard allowed else {
                phase = .failed
                message = "마이크 접근이 꺼져 있습니다. 시스템 설정에서 다마의 마이크 접근을 허용해 주세요."
                return
            }
            phase = .starting
            do {
                let root = try AudioFiles.root()
                self.root = root
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                let pool = try CaptureBufferPool(format: format)
                let writer = try CaptureWriter(root: root, pool: pool,
                    title: Date().formatted(date: .numeric, time: .shortened) + " 녹음")
                self.engine = engine
                self.pool = pool
                self.writer = writer
                inputDescription = "시스템 기본 마이크 · \(Int(format.sampleRate)) Hz · \(format.channelCount)채널"
                input.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, time in
                    pool.offer(buffer, sampleTime: time.isSampleTimeValid ? time.sampleTime : nil)
                }
                try engine.start()
                activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "다마 마이크 원본 저장")
                engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                    object: engine, queue: .main) { [weak self] _ in
                        Task { @MainActor in _ = await self?.stop(reason: .deviceChanged) }
                    }
                sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                    object: nil, queue: .main) { [weak self] _ in
                        Task { @MainActor in _ = await self?.stop(reason: .sleep) }
                    }
                draining = Task.detached(priority: .userInitiated) {
                    while !Task.isCancelled {
                        await writer.drain()
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                }
                monitor = Task { [weak self] in
                    var lastFrames: Int64 = 0
                    var lastArrival = ContinuousClock.now
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled, let self else { break }
                        let received = pool.receivedFrames
                        let snapshot = await writer.snapshot()
                        if received > lastFrames {
                            lastArrival = .now
                            lastFrames = received
                            if self.phase == .starting { self.phase = .recording }
                        }
                        self.elapsedUs = (try? AudioFiles.microseconds(frames: received, rate: format.sampleRate)) ?? 0
                        self.level = snapshot.level
                        if let failure = snapshot.failure { _ = await self.stop(reason: failure); break }
                        if lastArrival.duration(to: .now) > .seconds(3) {
                            _ = await self.stop(reason: .inputStopped); break
                        }
                    }
                }
            } catch {
                if writer != nil { _ = await stop(reason: .writeFailed) }
                else {
                    phase = .failed
                    message = "원본을 저장할 수 없어 녹음을 시작하지 못했습니다. 저장 공간과 마이크 연결을 확인해 주세요."
                }
            }
        }
    }

    @discardableResult public func stop(reason: AudioFailure? = nil) async -> Bool {
        guard phase == .recording || phase == .starting else { return false }
        phase = .finalizing
        monitor?.cancel()
        monitor = nil
        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        engineObserver = nil
        sleepObserver = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        pool?.close()
        draining?.cancel()
        draining = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        do {
            guard let writer else { throw AudioFailure.incompleteCapture }
            let saved = try await writer.finish(reason: reason)
            self.writer = nil
            pool = nil
            lastSaved = saved
            phase = saved.state == "saved" ? .idle : .interrupted
            message = saved.state == "saved" ? "원본 저장됨"
                : "녹음이 중단되었습니다. 이후 구간은 녹음되지 않았을 수 있습니다. 보존된 길이: \(saved.durationUs / 1_000_000)초."
            onSaved?(saved)
            return saved.state == "saved"
        } catch {
            phase = .interrupted
            message = "원본 저장을 확정하지 못했습니다. 저장 공간을 확인해 주세요. 확정된 청크와 미완료 파일은 보존되어 있습니다."
            // Keep the writer reachable so the user can retry finalization, not overwrite it with a new session.
            return false
        }
    }

    public var needsFinalization: Bool { writer != nil && !phase.busy }
    public func retryFinalization() async -> Bool {
        guard needsFinalization else { return false }
        phase = .starting
        return await stop(reason: .writeFailed)
    }
}
