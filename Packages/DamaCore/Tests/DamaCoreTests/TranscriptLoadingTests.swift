import Foundation
import XCTest
@testable import DamaCore

final class TranscriptLoadingTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var normalizedURL: URL {
        repositoryRoot.appendingPathComponent("fixtures/normalized-transcript.json")
    }

    private var vendorURL: URL {
        repositoryRoot.appendingPathComponent("fixtures/pyannote-job-succeeded.synthetic.json")
    }

    private var schemaURL: URL {
        repositoryRoot.appendingPathComponent("ssot/contracts/transcript.v1.schema.json")
    }

    private func normalizedData() throws -> Data { try Data(contentsOf: normalizedURL) }
    private func document() throws -> TranscriptDocument {
        try SyntheticTranscriptFixtureLoader.load(from: normalizedURL)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encoded(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func error(from body: () throws -> Void) -> TranscriptContractError? {
        do {
            try body()
            XCTFail("Expected a structured contract error")
            return nil
        } catch let error as TranscriptContractError {
            return error
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
            return nil
        }
    }

    func testValidFixtureIsPreservedAndRoundTrips() throws {
        let source = try normalizedData()
        let value = try SyntheticTranscriptFixtureLoader.load(data: source)
        XCTAssertEqual(value.schemaVersion, "1.0")
        XCTAssertEqual(value.words.count, 5)
        XCTAssertEqual(value.turns.count, 4)
        XCTAssertEqual(value.reviewIssues.count, 2)
        XCTAssertEqual(value.turns[1].startUs, 850_000)
        XCTAssertEqual(value.turns[1].endUs, 990_000)
        XCTAssertEqual(value.turns[1].wordIds, [])
        XCTAssertEqual(value.words[4].modelSpeakerId, "speaker-b")
        XCTAssertNil(value.words[4].speakerId)
        XCTAssertEqual(value.diarization[3].confidence?.values.reduce(0, +), 125)
        XCTAssertEqual(value.diarization[3].confidence?["SPEAKER_01"], 65)
        XCTAssertEqual(value.diarization[3].confidence?["SPEAKER_02"], 60)
        XCTAssertNil(value.diarization[4].confidence)

        let output = try NormalizedTranscriptCodec.encode(value)
        let before = try JSONSerialization.jsonObject(with: source) as? NSDictionary
        let after = try JSONSerialization.jsonObject(with: output) as? NSDictionary
        XCTAssertTrue(try XCTUnwrap(before).isEqual(try XCTUnwrap(after)))
    }

    func testEncodedDocumentContainsEverySchemaRequiredKeyRecursively() throws {
        let output = try NormalizedTranscriptCodec.encode(document())
        let instance = try JSONSerialization.jsonObject(with: output)
        let schema = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any]
        )
        try assertRequiredKeys(instance: instance, schema: schema, rootSchema: schema, path: "$")
    }

    func testMissingRequiredNullableKeyIsRejectedBeforeDecode() throws {
        var root = try jsonObject(normalizedData())
        var words = try XCTUnwrap(root["words"] as? [[String: Any]])
        words[0].removeValue(forKey: "editedText")
        root["words"] = words
        let result = error { _ = try NormalizedTranscriptCodec.decode(encoded(root)) }
        XCTAssertEqual(result?.code, .missingRequiredKey)
        XCTAssertEqual(result?.path, "$.words[0].editedText")
    }

    func testUnknownNormalizedObjectKeyIsRejected() throws {
        var root = try jsonObject(normalizedData())
        var provenance = try XCTUnwrap(root["provenance"] as? [String: Any])
        provenance["secret"] = "must not be reflected"
        root["provenance"] = provenance
        let result = error { _ = try NormalizedTranscriptCodec.decode(encoded(root)) }
        XCTAssertEqual(result?.code, .unknownKey)
        XCTAssertFalse(result?.description.contains("must not be reflected") ?? true)
    }

    func testWrongJSONTypeReturnsStructuredError() throws {
        var root = try jsonObject(normalizedData())
        root["durationUs"] = "3000000"
        let result = error { _ = try NormalizedTranscriptCodec.decode(encoded(root)) }
        XCTAssertEqual(result?.code, .decodingFailed)
    }

    func testSyntheticLoaderRejectsNonSyntheticWithoutChangingIt() throws {
        var root = try jsonObject(normalizedData())
        var provenance = try XCTUnwrap(root["provenance"] as? [String: Any])
        provenance["isSynthetic"] = false
        root["provenance"] = provenance
        let data = try encoded(root)
        let result = error { _ = try SyntheticTranscriptFixtureLoader.load(data: data) }
        XCTAssertEqual(result?.code, .notSynthetic)
        let decoded = try NormalizedTranscriptCodec.decode(data)
        XCTAssertFalse(decoded.provenance.isSynthetic)
    }

    func testVendorDecoderIsSeparateAndPreservesUnknownStatusAndMap() throws {
        var root = try jsonObject(Data(contentsOf: vendorURL))
        root["status"] = "future_provider_state"
        let value = try PyannoteJobDecoder.decode(encoded(root))
        XCTAssertEqual(value.status, "future_provider_state")
        XCTAssertEqual(value.output?.diarization[0].confidence?["SPEAKER_00"], 94)
        XCTAssertEqual(value.output?.diarization[0].confidence?.values.reduce(0, +), 107)
    }

    func testDuplicateIdentifierAndReferenceAreRejectedWithoutTrap() throws {
        var value = try document()
        value.words[1].id = value.words[0].id
        let duplicateID = error { try TranscriptValidator().validate(value) }
        XCTAssertEqual(duplicateID?.code, .duplicateIdentifier)

        value = try document()
        value.turns[0].wordIds.append("w1")
        let duplicateReference = error { try TranscriptValidator().validate(value) }
        XCTAssertEqual(duplicateReference?.code, .duplicateReference)
    }

    func testDanglingReferencesAreRejected() throws {
        var value = try document()
        value.words[0].reviewIssueIds = ["not-present"]
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .danglingReference)
    }

    func testNegativePartialAndReversedTimestampsAreRejected() throws {
        var value = try document()
        value.words[0].startUs = -1
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidTimestamp)

        value = try document()
        value.words[0].startUs = nil
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidTimestamp)

        value = try document()
        value.words[0].startUs = 350_000
        value.words[0].endUs = 300_000
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidTimestamp)
    }

    func testMissingAndDoubleSpeechMembershipAreRejected() throws {
        var value = try document()
        value.turns[0].wordIds.removeFirst()
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidTurnMembership)

        value = try document()
        value.turns.remove(at: 1)
        value.words[1].modelSpeakerId = nil
        value.turns[1].startUs = 400_000
        value.turns[1].wordIds.insert("w2", at: 0)
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidTurnMembership)
    }

    func testInvalidMarkerAndMixedSpeechTurnAreRejected() throws {
        var value = try document()
        value.turns[1].wordIds = ["w1"]
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidTurnMembership)

        value = try document()
        value.words[0].speakerId = "speaker-b"
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidTurnMembership)
    }

    func testExclusiveDifferentSpeakerOverlapIsRejected() throws {
        var value = try document()
        value.exclusiveDiarization[1].startUs = 700_000
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidValue)
    }

    func testMultiwordUserReassignmentDoesNotTreatModelIntervalsAsBarrier() throws {
        var value = try document()
        value.words[0].speakerId = "speaker-c"
        value.words[0].assignmentSource = .user
        value.words[1].speakerId = "speaker-c"
        value.words[1].assignmentSource = .user
        value.turns[0].speakerId = "speaker-c"
        XCTAssertNoThrow(try TranscriptValidator().validate(value))
        XCTAssertEqual(value.words[0].modelSpeakerId, "speaker-a")
        XCTAssertEqual(value.words[1].modelSpeakerId, "speaker-a")
    }

    func testExistingDifferentSpeakerMarkerCannotBeSwallowedByATurn() throws {
        var value = try document()
        value.turns[0].endUs = 1_400_000
        value.turns[0].wordIds.append("w3")
        value.turns[2].wordIds.removeFirst()
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidBarrier)
    }

    func testConfidenceAlignmentDatesAndRevisionRules() throws {
        var value = try document()
        value.diarization[0].confidence?["SPEAKER_00"] = .infinity
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidValue)

        value = try document()
        value.words[0].alignmentScore = 1.01
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidValue)

        value = try document()
        value.provenance.createdAt = "not-a-date"
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidValue)

        value = try document()
        value.revision.sourceRunId = "another-run"
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidValue)
    }

    func testEditedTextCannotClaimModelAlignedTiming() throws {
        var value = try document()
        value.words[0].editedText = "수정한 단어"
        XCTAssertEqual(error { try TranscriptValidator().validate(value) }?.code, .invalidValue)
        value.words[0].timingOrigin = .inheritedUnaligned
        XCTAssertNoThrow(try TranscriptValidator().validate(value))
        XCTAssertEqual(value.words[0].text, "저희가")
        XCTAssertEqual(value.words[0].prefix, "")
    }

    private func assertRequiredKeys(
        instance: Any,
        schema: [String: Any],
        rootSchema: [String: Any],
        path: String
    ) throws {
        var resolved = schema
        if let reference = schema["$ref"] as? String {
            let name = String(reference.split(separator: "/").last ?? "")
            let definitions = try XCTUnwrap(rootSchema["$defs"] as? [String: Any])
            resolved = try XCTUnwrap(definitions[name] as? [String: Any])
        }
        if let object = instance as? [String: Any] {
            let required = resolved["required"] as? [String] ?? []
            for key in required {
                XCTAssertNotNil(object[key], "Missing required key \(path).\(key)")
            }
            let properties = resolved["properties"] as? [String: Any] ?? [:]
            for (key, child) in properties {
                guard let childSchema = child as? [String: Any], let childValue = object[key] else { continue }
                try assertRequiredKeys(instance: childValue, schema: childSchema,
                                       rootSchema: rootSchema, path: "\(path).\(key)")
            }
        } else if let array = instance as? [Any], let items = resolved["items"] as? [String: Any] {
            for (index, value) in array.enumerated() {
                try assertRequiredKeys(instance: value, schema: items,
                                       rootSchema: rootSchema, path: "\(path)[\(index)]")
            }
        }
    }
}

final class TranscriptTimePresentationTests: XCTestCase {
    func testFixedTimestampAndDurationConversionsDoNotMutateModelTimes() throws {
        let start: Microseconds = 850_000
        let end: Microseconds = 990_000
        XCTAssertEqual(TranscriptTimePresentation.timestamp(start), "00:00:00.850")
        XCTAssertEqual(TranscriptTimePresentation.timestamp(end), "00:00:00.990")
        XCTAssertEqual(TranscriptTimePresentation.durationMilliseconds(startUs: start, endUs: end), 140)
        XCTAssertEqual(TranscriptTimePresentation.duration(startUs: start, endUs: end), "140ms")
        XCTAssertEqual(start, 850_000)
        XCTAssertEqual(end, 990_000)
    }

    func testNearestMillisecondUsesHalfUpIntegerRounding() {
        XCTAssertEqual(TranscriptTimePresentation.timestamp(849_499), "00:00:00.849")
        XCTAssertEqual(TranscriptTimePresentation.timestamp(849_500), "00:00:00.850")
    }

    func testLargeInt64AndUnavailableInputsDoNotOverflow() {
        XCTAssertEqual(
            TranscriptTimePresentation.milliseconds(fromMicroseconds: Int64.max),
            9_223_372_036_854_776
        )
        XCTAssertTrue(TranscriptTimePresentation.timestamp(Int64.max).hasPrefix("2562047788:"))
        XCTAssertEqual(TranscriptTimePresentation.timestamp(nil), "시간 미확인")
        XCTAssertEqual(TranscriptTimePresentation.timestamp(-1), "시간 미확인")
        XCTAssertEqual(TranscriptTimePresentation.duration(startUs: 2, endUs: 1), "시간 미확인")
        XCTAssertEqual(TranscriptTimePresentation.duration(startUs: nil, endUs: 1), "시간 미확인")
    }
}
