import DamaCore
import Foundation

/// usage-bundle1 녹음 표시 제목 해석 (계약 library-script.md «녹음 표시 제목»).
/// 녹음 제목은 인덱스 `displayTitle`에만 쓰고, 연결 스크립트는 읽을 때 그 제목을 쓴다. 스크립트 파일 `title`은 고쳐 쓰지 않는다.
public enum LibraryTitles {
    /// 녹음 제목 = displayTitle, 없으면 기존 title(자동 제목 또는 가져온 파일 이름).
    public static func speech(_ speech: LibrarySpeech) -> String { speech.displayTitle ?? speech.title }

    /// 스크립트 제목 = 연결 녹음(인덱스 id == sessionId)의 displayTitle, 없으면 파일 title.
    /// `displayTitles`는 인덱스 전체(찾지 못한 파일 항목 포함)에서 만든다.
    public static func script(fileTitle: String, sessionID: String, displayTitles: [String: String]) -> String {
        displayTitles[sessionID] ?? fileTitle
    }

    /// AI 버전 보기(읽기 전용 스냅숏)는 그 파일에 저장된 당시 제목을 그대로 쓴다.
    public static func script(_ script: LibraryScript, displayTitles: [String: String]) -> String {
        script.snapshotTitle != nil ? script.title
            : Self.script(fileTitle: script.title, sessionID: script.transcript.sessionId, displayTitles: displayTitles)
    }
}
