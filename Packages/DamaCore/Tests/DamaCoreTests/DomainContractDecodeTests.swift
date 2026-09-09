import Foundation
import XCTest
@testable import DamaCore

final class DomainContractDecodeTests: XCTestCase {
    func testNormalizedFixtureDecodesThroughCoreModule() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("normalized-transcript.json")

        let document = try JSONDecoder().decode(
            TranscriptDocument.self,
            from: Data(contentsOf: fixtureURL)
        )

        XCTAssertEqual(document.schemaVersion, "1.0")
        XCTAssertEqual(document.words.count, 5)
        XCTAssertNil(document.words.last?.speakerId)
        XCTAssertEqual(document.diarization[3].confidence?["SPEAKER_01"], 65)
        XCTAssertEqual(document.diarization[3].confidence?["SPEAKER_02"], 60)
        XCTAssertNil(document.diarization[4].confidence)
    }
}
