import Foundation

/// usage-bundle1 제목 저장 시점 (T2a-5). 녹음·스크립트 제목칸이 같은 규칙을 쓴다.
/// 저장 계기는 Enter·입력칸 이탈(·입력창 «저장»)뿐이고 0.5초 자동 저장은 없다. 조합 중에는 저장하지 않는다.
/// 저장 값은 입력 그대로다(앞뒤 공백을 다듬지 않는다). 빈값·공백뿐이면 거부하고 입력을 유지한다.
public struct TitleDraft: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// 입력 변경. `composing` = 한글 등 입력기 조합 중.
        case edit(String, composing: Bool)
        case enter
        case leave
        case escape
    }
    public enum Action: Equatable, Sendable {
        case none
        /// 이 값을 저장한다. 성공하면 `didSave(_:)`를 부른다.
        case save(String)
        /// 입력을 마지막 저장값으로 되돌렸다.
        case revert(String)
        /// 저장하지 않고 입력을 유지한다. 값 = 표시 문구.
        case reject(String)
    }
    public static let emptyMessage = "제목을 입력해 주세요."

    public private(set) var saved: String
    public private(set) var text: String
    public private(set) var composing = false

    public init(saved: String) { self.saved = saved; text = saved }

    public var isDirty: Bool { text != saved }

    public mutating func handle(_ event: Event) -> Action {
        switch event {
        case .edit(let value, let isComposing):
            text = value; composing = isComposing
            return .none
        case .enter, .leave:
            guard !composing, isDirty else { return .none }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .reject(Self.emptyMessage) }
            return .save(text)
        case .escape:
            guard !composing else { return .none }
            text = saved
            return .revert(saved)
        }
    }

    /// 저장 성공 뒤 마지막 저장값을 갱신한다. 저장 중에 입력이 더 바뀌었으면 그 입력은 남는다.
    public mutating func didSave(_ value: String) { saved = value }

    /// 바깥(다른 창·목록)에서 저장값이 바뀌었을 때. 고치는 중이 아니면 입력도 따라간다.
    public mutating func receive(saved value: String) {
        let following = !isDirty
        saved = value
        if following { text = value }
    }
}

/// usage-bundle1 녹음 직후 제목 입력창 줄 서기.
/// 끝난 순서로 줄 서고 한 번에 하나만 보인다. 인덱스에서 확인된 id만 표시하고, 닫으면 다음으로 넘어가며, 종료 시 전부 버린다.
/// 끝난 순서를 지키려고 줄 맨 앞(가장 먼저 끝난 것)이 확인될 때까지 뒤의 것은 보이지 않는다.
/// 줄 맨 앞이 Speeches 저장에 실패하거나 인덱스에 오르지 못하면 `drop`으로 빼서 뒤가 막히지 않게 한다.
public struct TitlePromptQueue: Equatable, Sendable {
    /// 끝난 순서대로 선 녹음. 첫 항목이 확인되었으면 그것이 보이는 입력창이다.
    private var line: [String] = []
    private var confirmedIDs: Set<String> = []

    public init() {}

    /// 지금 보이는 입력창의 녹음 id. 줄 맨 앞이 아직 확인되지 않았으면 nil.
    public var current: String? { line.first.flatMap { confirmedIDs.contains($0) ? $0 : nil } }
    /// 줄에 선 녹음 수 (보이는 것 포함).
    public var count: Int { line.count }
    /// 아직 인덱스에서 확인하지 못한 녹음.
    public var awaiting: [String] { line.filter { !confirmedIDs.contains($0) } }

    /// 녹음이 끝나 Speeches 저장을 시작했다. 아직 보이지 않는다.
    public mutating func finished(_ id: String) {
        guard !line.contains(id) else { return }
        line.append(id)
    }

    /// 목록 새로고침에서 인덱스에 있는 id 집합을 받았다. 줄에 선 녹음 중 확인된 것을 표시 가능으로 바꾼다.
    public mutating func confirmed(_ indexIDs: Set<String>) {
        confirmedIDs.formUnion(line.filter { indexIDs.contains($0) })
    }

    /// Speeches 저장 실패·인덱스 누락으로 건너뛴다. 보이는 입력창이면 닫는 것과 같다.
    public mutating func drop(_ id: String) {
        line.removeAll { $0 == id }; confirmedIDs.remove(id)
    }

    /// 보이는 입력창을 닫았다(저장 성공·나중에·Esc·창 닫기). `id`가 지금 보이는 것과 다르면 아무것도 하지 않는다.
    public mutating func dismiss(_ id: String) {
        guard current == id else { return }
        drop(id)
    }

    /// 앱 종료: 열린 입력창과 줄 선 것을 저장 없이 전부 버린다.
    public mutating func terminate() { line = []; confirmedIDs = [] }
}
