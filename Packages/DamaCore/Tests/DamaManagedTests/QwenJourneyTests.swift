import AVFoundation
import DamaAudio
import DamaCore
import Foundation
import XCTest
@testable import DamaManaged

@MainActor final class QwenJourneyTests: XCTestCase {
    private func setup() async throws -> (URL,AudioManifest) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try FileManager.default.removeItem(at:root) }
        let format=AVAudioFormat(standardFormatWithSampleRate:16000,channels:1)!
        let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!
        pcm.frameLength=48000;pcm.floatChannelData![0].initialize(repeating:0,count:48000)
        let url=root.appendingPathComponent("fixture.wav")
        let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:pcm);file.close()
        return (root,try await AudioLibrary(root:root).importFile(url))
    }
    func testReusesSameAudioAndSettingsWithoutAPIKeyAndPreservesPriorRun() async throws {
        let (root,audio)=try await setup(), transport=QwenTestTransport(), worker=QwenTestWorker()
        let processor=ManagedProcessor(root:root,transport:transport,qwen:worker,sleep:{_ in})
        let first=try await processor.begin(sessionID:audio.id,confirmed:true,key:"fixture",input:ConversionNotes(speakerCount:1))
        XCTAssertEqual(first.stage,"readyForReview")
        let modelURL=root.appendingPathComponent("Sessions/\(audio.id)/runs/\(first.id)/normalized/model.json")
        let before=try Data(contentsOf:modelURL)
        let reuse=try await processor.reusableDiarization(sessionID:audio.id,audioHash:first.sourceAudioSHA256!,speakerCount:1)
        XCTAssertEqual(reuse,first.id)
        let wrongCount=try await processor.reusableDiarization(sessionID:audio.id,audioHash:first.sourceAudioSHA256!,speakerCount:2)
        XCTAssertNil(wrongCount)
        let wrongHash=try await processor.reusableDiarization(sessionID:audio.id,audioHash:String(repeating:"b",count:64),speakerCount:1)
        XCTAssertNil(wrongHash)
        let calls=await transport.calls
        var notes=ConversionNotes(speakerCount:1,context:"H&Q",aiCorrection:false)
        notes.transcriptionProvider = .qwen;notes.qwenDiarizationRunID=reuse
        let run=try await processor.begin(sessionID:audio.id,confirmed:true,key:"",input:notes,retranscribing:true)
        XCTAssertEqual(run.stage,"readyForReview");XCTAssertNotEqual(first.id,run.id)
        let afterCalls=await transport.calls;XCTAssertEqual(calls,afterCalls)
        let context=await worker.context;XCTAssertEqual(context,"H&Q")
        XCTAssertEqual(try Data(contentsOf:modelURL),before)
        let doc=try await FileSessionRepository(rootURL:root).loadModel(sessionId:audio.id,runId:run.id)
        XCTAssertEqual(doc.provenance.engine,.hybridPyannoteQwen)
        XCTAssertEqual(doc.words.map(\.text).joined(),"H&Q 15.38% 네 네")
    }
    func testFreshDiarizationDisablesWhisperAndResumeDoesNotResubmit() async throws {
        let (root,audio)=try await setup(),transport=QwenTestTransport(),worker=QwenTestWorker(failOnce:true)
        let processor=ManagedProcessor(root:root,transport:transport,qwen:worker,sleep:{_ in})
        var notes=ConversionNotes(speakerCount:1);notes.transcriptionProvider = .qwen
        let paused=try await processor.begin(sessionID:audio.id,confirmed:true,key:"fixture",input:notes)
        XCTAssertEqual(paused.stage,"paused")
        let payload=await transport.submission
        let json=try JSONSerialization.jsonObject(with:XCTUnwrap(payload)) as! [String:Any]
        XCTAssertEqual(json["transcription"] as? Bool,false);XCTAssertNil(json["transcriptionConfig"])
        let calls=await transport.calls
        let resumed=try await processor.resume(paused.id,key:"")
        XCTAssertEqual(resumed.stage,"readyForReview")
        let after=await transport.calls;XCTAssertEqual(after,calls)
        let reuse=try await processor.reusableDiarization(sessionID:audio.id,audioHash:resumed.sourceAudioSHA256!,speakerCount:1)
        XCTAssertEqual(reuse,resumed.id)
    }
    func testMissingRuntimeNeverUploads() async throws {
        let (root,audio)=try await setup(),transport=QwenTestTransport()
        let processor=ManagedProcessor(root:root,transport:transport,qwen:QwenRunner(runtimeURL:root.appendingPathComponent("absent")))
        var notes=ConversionNotes();notes.transcriptionProvider = .qwen
        let run=try await processor.begin(sessionID:audio.id,confirmed:true,key:"fixture",input:notes)
        XCTAssertEqual(run.failure,"runtimeUnavailable")
        let calls=await transport.calls;XCTAssertEqual(calls,0)
    }
}

private actor QwenTestWorker: QwenRunning {
    var context=""
    var failOnce: Bool
    init(failOnce:Bool=false) { self.failOnce=failOnce }
    nonisolated func validateReady() throws {}
    func transcribe(audio:URL,work:URL,input:ConversionNotes,audioHash:String,durationUs:Int64) async throws -> Data {
        if failOnce { failOnce=false;throw CancellationError() }
        context=input.qwenLocalContext
        return try JSONSerialization.data(withJSONObject:["version":"qwen-worker-v1","status":"complete",
            "audioSHA256":audioHash,"durationUs":durationUs,"text":"H&Q 15.38% 네 네",
            "words":[["text":"H&Q 15.38% 네 네","startUs":100_000,"endUs":200_000]],
            "chunks":[["startFrame":0,"endFrame":48000,"finish_reason":"eos","truncated":false]]])
    }
}
private actor QwenTestTransport: ManagedTransport {
    var calls=0
    var submission:Data?
    func upload(file:URL,to:URL) async throws -> HTTPReply { calls+=1;return HTTPReply(data:Data(),status:200) }
    func api(path:String,method:String,body:Data?,key:String) async throws -> HTTPReply {
        calls+=1
        if path=="/v1/media/input" { return HTTPReply(data:Data("{\"url\":\"https://storage.example/signed\"}".utf8),status:201) }
        if method=="POST" { submission=body;return HTTPReply(data:Data("{\"jobId\":\"fixture\"}".utf8),status:201) }
        let interval:[String:Any]=["start":0.0,"end":3.0,"speaker":"A"]
        return HTTPReply(data:try JSONSerialization.data(withJSONObject:["jobId":"fixture","status":"succeeded","output":
            ["diarization":[interval],"exclusiveDiarization":[interval],
             "wordLevelTranscription":[["start":0.1,"end":0.2,"speaker":"A","text":"fixture"]]]]),status:200)
    }
}
