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
public struct TitlePromptQueue: Equatable, Sendable {
    private var sequence = 0
    /// 끝났지만 아직 인덱스에서 확인하지 못한 녹음 (id → 끝난 순번).
    private var awaiting: [String: Int] = [:]
    /// 확인되어 표시를 기다리는 녹음 (끝난 순번 오름차순). 첫 항목이 보이는 입력창이다.
    private var ready: [(id: String, order: Int)] = []

    public init() {}

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sequence == rhs.sequence && lhs.awaiting == rhs.awaiting
            && lhs.ready.map(\.id) == rhs.ready.map(\.id) && lhs.ready.map(\.order) == rhs.ready.map(\.order)
    }

    /// 지금 보이는 입력창의 녹음 id. 없으면 nil.
    public var current: String? { ready.first?.id }
    /// 확인을 기다리거나 줄 선 녹음 수 (보이는 것 포함).
    public var count: Int { awaiting.count + ready.count }

    /// 녹음이 끝나 Speeches 저장을 시작했다. 아직 보이지 않는다.
    public mutating func finished(_ id: String) {
        guard awaiting[id] == nil, !ready.contains(where: { $0.id == id }) else { return }
        sequence += 1
        awaiting[id] = sequence
    }

    /// 목록 새로고침에서 인덱스에 있는 id 집합을 받았다. 기다리던 녹음 중 확인된 것만 줄에 올린다.
    /// 보이는 입력창은 바꾸지 않고, 뒤에 선 것은 끝난 순서로 정렬한다.
    public mutating func confirmed(_ indexIDs: Set<String>) {
        let found = awaiting.filter { indexIDs.contains($0.key) }
        guard !found.isEmpty else { return }
        for id in found.keys { awaiting[id] = nil }
        let incoming = found.map { (id: $0.key, order: $0.value) }
        if let head = ready.first {
            ready = [head] + (Array(ready.dropFirst()) + incoming).sorted { $0.order < $1.order }
        } else {
            ready = incoming.sorted { $0.order < $1.order }
        }
    }

    /// 기다리던 녹음이 Speeches 저장에 실패했거나 건너뛴다. 줄에서 뺀다.
    public mutating func drop(_ id: String) {
        awaiting[id] = nil
        if ready.first?.id != id { ready.removeAll { $0.id == id } }
    }

    /// 보이는 입력창을 닫았다(저장 성공·나중에·Esc·창 닫기). 다음 것이 보인다.
    public mutating func dismissCurrent() { if !ready.isEmpty { ready.removeFirst() } }

    /// 앱 종료: 열린 입력창과 줄 선 것을 저장 없이 전부 버린다.
    public mutating func terminate() { awaiting = [:]; ready = [] }
}
