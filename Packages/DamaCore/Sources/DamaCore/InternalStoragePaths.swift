import Foundation

/// 내부 저장소에서 스크립트 ID를 경로 성분으로 쓰는 곳의 공통 규칙 (usage-bundle2).
/// 스크립트 ID = transcript.runId이고 계약은 UUID를 요구하지 않는다(합성 fixture `run-fixture-001`).
/// 경로 안전은 문자 규칙으로 지킨다: ASCII 영숫자·`-`·`_`, 1–128자.
public enum InternalStoragePaths {
    public static let correctionAttemptsFolder = "CorrectionAttempts"

    public static func isSafeScriptID(_ id: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return !id.isEmpty && id.count <= 128 && id.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

    /// `<root>/CorrectionAttempts/<scriptID>.json` (usage-bundle1 교정 시도 기록, 스크립트당 1개).
    public static func correctionAttemptURL(root: URL, scriptID: String) throws -> URL {
        guard isSafeScriptID(scriptID) else { throw LibraryFailure.unsafePath }
        return root.appendingPathComponent(correctionAttemptsFolder, isDirectory: true).appendingPathComponent(scriptID + ".json")
    }
}
