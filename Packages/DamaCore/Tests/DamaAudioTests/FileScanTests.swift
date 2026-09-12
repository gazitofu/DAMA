import AVFoundation
import DamaCore
import XCTest
@testable import DamaAudio

final class FileScanTests: XCTestCase {
    private func setup() throws -> (URL, URL, FolderLibraryStore, LibraryScript) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = base.appendingPathComponent("Scripts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: base) }
        var fixture = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { fixture.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: fixture.appendingPathComponent("fixtures/normalized-transcript.json")))
        return (base, folder, FolderLibraryStore(root: base.appendingPathComponent("internal")),
                try LibraryScript(transcript: model, title: "합성 격리", recordedAt: nil, dateSource: "합성", input: ConversionNotes()))
    }

    func testMalformedSymlinkDuplicateAndChangedScriptsDoNotHideHealthyFiles() async throws {
        let (base, folder, store, script) = try setup()
        let file = try await store.saveScript(script, to: folder.appendingPathComponent("good.dama.json"), expectedHash: nil)
        let bytes = try Data(contentsOf: file.url)
        let bad = folder.appendingPathComponent("bad.dama.json"), link = folder.appendingPathComponent("link.dama.json")
        try Data("not JSON".utf8).write(to: bad)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file.url)
        let scan = try await store.scanScripts(in: folder)
        XCTAssertEqual(scan.items.map(\.id), [script.id])
        XCTAssertEqual(Set(scan.issues.map(\.url.lastPathComponent)), ["bad.dama.json", "link.dama.json"])
        XCTAssertEqual(scan.issues.first { $0.url.lastPathComponent == link.lastPathComponent }?.reason, .unsafePath)
        XCTAssertTrue(scan.items[0].reading === file.reading)
        let speech = LibrarySpeech(id: script.transcript.sessionId, fileURL: base.appendingPathComponent("synthetic.wav"), sourceHash: "synthetic", title: "합성", recordedAt: nil, dateSource: "합성", durationUs: 1, notes: ConversionNotes())
        let existing = try await store.createScript(script.transcript, speech: speech, input: ConversionNotes(), in: folder)
        XCTAssertEqual(existing.url, file.url)
        var next = script.transcript; next.runId = UUID().uuidString; next.revision.sourceRunId = next.runId
        let created = try await store.createScript(next, speech: speech, input: ConversionNotes(), in: folder)
        XCTAssertNotEqual(created.id, file.id)
        let correction = ScriptCorrection(input: ConversionNotes(), engine: "synthetic", state: .failed)
        let corrected = try await store.saveCorrection(correction, for: file)
        XCTAssertEqual(corrected.script.correction?.state, .failed)
        XCTAssertEqual(try NormalizedTranscriptCodec.encode(corrected.script.transcript), try NormalizedTranscriptCodec.encode(script.transcript))
        let duplicate = folder.appendingPathComponent("copy.dama.json")
        try FileManager.default.copyItem(at: file.url, to: duplicate)
        let duplicates = try await store.scanScripts(in: folder)
        XCTAssertEqual(duplicates.items.map(\.id), [created.id])
        XCTAssertEqual(duplicates.issues.filter { $0.reason == .duplicateIdentity }.count, 2)
        do { _ = try await store.createScript(script.transcript, speech: speech, input: ConversionNotes(), in: folder); XCTFail("ambiguous create") } catch LibraryFailure.invalidScript {}
        do { _ = try await store.saveCorrection(correction, for: corrected); XCTFail("ambiguous correction") } catch LibraryFailure.changedFile {}
        // An unrelated duplicate does not block an existing healthy result.
        let reused = try await store.createScript(next, speech: speech, input: ConversionNotes(), in: folder)
        XCTAssertEqual(reused.url, created.url)
        try FileManager.default.removeItem(at: duplicate)
        try Data("external malformed edit".utf8).write(to: file.url)
        let changed = try await store.scanScripts(in: folder)
        XCTAssertEqual(changed.items.map(\.id), [created.id])
        do { _ = try await store.saveScript(script, to: file.url, expectedHash: corrected.hash); XCTFail("stale save") } catch LibraryFailure.changedFile {}
        do { try await store.exportMarkdown(corrected, to: base.appendingPathComponent("out.md")); XCTFail("stale export") } catch LibraryFailure.changedFile {}
        XCTAssertEqual(try Data(contentsOf: file.url), Data("external malformed edit".utf8))
        try bytes.write(to: file.url)
        let reopened = try await FolderLibraryStore(root: base.appendingPathComponent("internal")).scanScripts(in: folder)
        XCTAssertEqual(Set(reopened.items.map(\.id)), [script.id, created.id])
        XCTAssertEqual(reopened.issues.count, 2)
    }

    func testBadSpeechAndIndexLeaveScriptsAccessibleAndDuplicateBundlesAreExcluded() async throws {
        let (base, scripts, store, script) = try setup()
        _ = try await store.saveScript(script, to: scripts.appendingPathComponent("good.dama.json"), expectedHash: nil)
        let speeches = base.appendingPathComponent("Speeches")
        try FileManager.default.createDirectory(at: speeches, withIntermediateDirectories: true)
        let source = speeches.appendingPathComponent("good.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        pcm.frameLength = 16_000; pcm.floatChannelData![0].initialize(repeating: 0, count: 16_000)
        let wav = try AVAudioFile(forWriting: source, settings: format.settings)
        try wav.write(from: pcm); wav.close()
        try Data("broken audio".utf8).write(to: speeches.appendingPathComponent("broken.wav"))
        try FileManager.default.createSymbolicLink(at: speeches.appendingPathComponent("link.wav"), withDestinationURL: source)
        let badBundle = speeches.appendingPathComponent("bad.dama-audio")
        try FileManager.default.createDirectory(at: badBundle, withIntermediateDirectories: true)
        try Data("bad manifest".utf8).write(to: badBundle.appendingPathComponent("capture-manifest.json"))
        let scan = try await store.scanSpeeches(in: speeches)
        XCTAssertEqual(scan.items.count, 1); XCTAssertEqual(scan.issues.count, 3)
        _ = try await store.scanSpeeches(in: speeches)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent("internal/Sessions").path).count, 1,
                       "Repeated malformed audio scans must not accumulate failed import sessions")
        let speech = try XCTUnwrap(scan.items.first)
        let record = try await AudioLibrary(root: base.appendingPathComponent("internal")).prepareAnalysis(speech.id)
        let bundles = base.appendingPathComponent("Bundles")
        try FileManager.default.createDirectory(at: bundles, withIntermediateDirectories: true)
        try await store.publishRecording(record, to: bundles)
        let bundle = bundles.appendingPathComponent(record.id + ".dama-audio")
        try FileManager.default.copyItem(at: bundle, to: bundles.appendingPathComponent("copy.dama-audio"))
        let duplicate = try await store.scanSpeeches(in: bundles)
        XCTAssertTrue(duplicate.items.isEmpty)
        XCTAssertEqual(duplicate.issues.filter { $0.reason == .duplicateIdentity }.count, 2)
        try Data("broken index".utf8).write(to: base.appendingPathComponent("internal/library-index.json"))
        do { _ = try await store.scanSpeeches(in: speeches); XCTFail("index must remain a folder-level failure") } catch is DecodingError {}
        let stillReadable = try await store.scanScripts(in: scripts)
        XCTAssertEqual(stillReadable.items.map(\.id), [script.id])
        XCTAssertTrue(stillReadable.issues.isEmpty)
    }
}
