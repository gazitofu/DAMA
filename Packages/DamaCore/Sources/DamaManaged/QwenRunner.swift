import CryptoKit
import DamaCore
import Foundation
import Darwin

public enum QwenFailure: String, Error, Sendable { case runtimeUnavailable, localInferenceFailed, localInferenceTimedOut, localSourceChanged }

public protocol QwenRunning: Sendable {
    func validateReady() throws
    func transcribe(audio: URL, work: URL, input: ConversionNotes, audioHash: String, durationUs: Int64) async throws -> Data
}

public struct QwenRunner: QwenRunning {
    public static var defaultRuntime: URL {
        var root=URL(fileURLWithPath:#filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent(".build/qwen-runtime.json")
    }
    private let runtimeURL: URL
    public init(runtimeURL: URL = Self.defaultRuntime) { self.runtimeURL=runtimeURL }
    private struct Runtime: Decodable {
        struct Model: Decodable { let id: String; let path: String; let revision: String }
        let version: Int
        let python: String
        let worker: String
        let upstreamCommit: String
        let models: [String:Model]
    }
    private func validate(_ data: Data) throws -> Runtime {
        let r=try JSONDecoder().decode(Runtime.self,from:data)
        guard r.version==1,r.upstreamCommit=="1e28932dac8e2c68b34c29f32e2be338ffc1c852",
              r.models["asr"]?.id=="Qwen/Qwen3-ASR-1.7B",r.models["aligner"]?.id=="Qwen/Qwen3-ForcedAligner-0.6B",
              FileManager.default.isExecutableFile(atPath:r.python),FileManager.default.fileExists(atPath:r.worker),
              r.models.values.allSatisfy({ FileManager.default.fileExists(atPath:$0.path+"/config.json") }) else { throw QwenFailure.runtimeUnavailable }
        return r
    }
    public func validateReady() throws {
        do { _=try validate(Data(contentsOf:runtimeURL)) } catch { throw QwenFailure.runtimeUnavailable }
    }
    public func transcribe(audio: URL, work: URL, input: ConversionNotes, audioHash: String, durationUs: Int64) async throws -> Data {
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        let runtimeFile=work.appendingPathComponent("runtime.json")
        let runtimeData: Data
        if FileManager.default.fileExists(atPath:runtimeFile.path) { runtimeData=try Data(contentsOf:runtimeFile) }
        else { runtimeData=try Data(contentsOf:runtimeURL); try runtimeData.write(to:runtimeFile,options:.withoutOverwriting) }
        let r=try validate(runtimeData)
        // Freeze the worker for this Run, independent of future app/dependency edits.
        let workerFile=work.appendingPathComponent("worker.py")
        if !FileManager.default.fileExists(atPath:workerFile.path) {
            try Data(contentsOf:URL(fileURLWithPath:r.worker)).write(to:workerFile,options:.withoutOverwriting)
        }
        let request: [String:Any]=["audio":audio.path,"workDirectory":work.path,"audioSHA256":audioHash,
            "durationUs":durationUs,"context":input.qwenLocalContext,"language":"Korean"]
        let bytes=try JSONSerialization.data(withJSONObject:request,options:[.sortedKeys,.withoutEscapingSlashes])
        let requestFile=work.appendingPathComponent("request.json")
        if FileManager.default.fileExists(atPath:requestFile.path) {
            guard try Data(contentsOf:requestFile)==bytes else { throw QwenFailure.localSourceChanged }
        } else { try bytes.write(to:requestFile,options:.withoutOverwriting) }
        let process=Process()
        process.executableURL=URL(fileURLWithPath:r.python)
        process.arguments=[workerFile.path,"--request",requestFile.path,"--runtime",runtimeFile.path]
        process.environment=["PATH":"/usr/bin:/bin","HF_HUB_OFFLINE":"1","HF_HUB_DISABLE_TELEMETRY":"1",
            "TOKENIZERS_PARALLELISM":"false","PYTHONUNBUFFERED":"1"]
        let log=work.appendingPathComponent("process-\(UUID().uuidString).log")
        _=FileManager.default.createFile(atPath:log.path,contents:nil)
        let handle=try FileHandle(forWritingTo:log)
        defer { try? handle.close() }
        process.standardOutput=handle;process.standardError=handle
        try process.run()
        var lastProgress=Date(), previous: Data?
        do {
            while process.isRunning {
                try Task.checkCancellation()
                let progress=try? Data(contentsOf:work.appendingPathComponent("progress.json"))
                if progress != previous { previous=progress;lastProgress=Date() }
                if Date().timeIntervalSince(lastProgress)>960 { throw QwenFailure.localInferenceTimedOut }
                try await Task.sleep(for:.milliseconds(300))
            }
            try Task.checkCancellation()
        } catch {
            if process.isRunning { process.interrupt() }
            // A short grace period allows Python to release its lock; then force stop.
            let until=Date().addingTimeInterval(2)
            while process.isRunning && Date()<until {
                await Task.detached { try? await Task<Never,Never>.sleep(for:.milliseconds(50)) }.value
            }
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            throw error
        }
        guard process.terminationStatus==0 else { throw QwenFailure.localInferenceFailed }
        let result=try Data(contentsOf:work.appendingPathComponent("result.json"))
        let decoded=try JSONDecoder().decode(QwenResult.self,from:result)
        guard decoded.status=="complete",decoded.audioSHA256==audioHash,decoded.durationUs==durationUs else {
            throw QwenFailure.localSourceChanged
        }
        return result
    }
}
