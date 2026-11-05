import Foundation

/// usage-bundle1 의미 보호 분류 (context-correction-6, 스펙 §02-4). 표시 순서 = 숫자·단위·부정·조건.
public enum MeaningClass: String, CaseIterable, Sendable, Equatable {
    case number, unit, negation, condition
    public var title: String {
        switch self { case .number: "숫자"; case .unit: "단위"; case .negation: "부정"; case .condition: "조건" }
    }
}

/// 인용(quote)과 대체(replacement)의 보호 표식을 글자로 대조한다. `notes/usage-bundle1/measure-b1.py`의
/// `num_sig`·`unit_sig`·`neg_sig`·`cond_sig`를 옮겼다. 표식 목록은 신규 후보이며 한국어 실측 전이다.
/// 잡지 못하는 것: 고유어 수사(하나·둘), 낱자 한자어 수사(일·이·삼), 숫자 없는 단위, 표식 글자 없는 의미 변경.
public enum MeaningGuard {
    static let digitsAndMagnitudes: Set<Character> = Set("0123456789십백천만억조")
    /// 길이 내림차순(같은 길이는 원래 순서) 최장 일치. Python `UNITS.sort(key=len, reverse=True)`와 같은 순서.
    static let units: [[String]] = {
        let list = ["%", "퍼센트", "프로", "원", "달러", "불", "엔", "유로", "위안", "배",
                    "kwh", "kw", "mwh", "mw", "gwh", "gw", "kg", "mg", "km", "cm", "mm", "톤",
                    "명", "개월", "개", "건", "년", "시간", "분기"]
        return list.enumerated().sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map { $0.element.map { String($0) } }
    }()
    static let negationMarks = ["않", "없", "아니", "아닌", "아냐", "아님", "말고", "마세요", "마라", "말아", "못"]
    static let englishNegations: Set<String> = ["not", "no", "never"]
    static let conditionMarks = ["면", "거든", "경우", "만약", "만일", "조건", "한해", "한하여", "한정", "이상", "이하", "미만", "초과", "까지", "부터", "전제"]
    static let englishConditions: Set<String> = ["if", "unless"]
    static let tokenTrim = CharacterSet(charactersIn: ".,?!~\"'()[]")

    /// 바뀐 분류(숫자·단위·부정·조건 순). 비어 있으면 표식상 의미 변경 없음.
    public static func changedClasses(quote: String, replacement: String) -> [MeaningClass] {
        var result: [MeaningClass] = []
        if numberSignature(quote) != numberSignature(replacement) { result.append(.number) }
        if unitSignature(quote) != unitSignature(replacement) { result.append(.unit) }
        if negationSignature(quote) != negationSignature(replacement) { result.append(.negation) }
        if conditionSignature(quote) != conditionSignature(replacement) { result.append(.condition) }
        return result
    }

    /// 보류 근거 문구 (tone usage-bundle1 문구 20).
    public static func basis(_ classes: [MeaningClass]) -> String {
        "\(classes.map(\.title).joined(separator: "·")) 표현이 바뀌는 수정이라 자동 반영하지 않았습니다. 원음으로 확인해 주세요."
    }

    /// 공백·쉼표를 지운 뒤 차례대로 뽑은 0–9, 십 백 천 만 억 조, 숫자 사이의 «.».
    static func numberSignature(_ text: String) -> String {
        let t = Array(text.filter { !$0.isWhitespace && $0 != "," })
        var out = ""
        for (i, c) in t.enumerated() {
            if digitsAndMagnitudes.contains(c) { out.append(c) }
            else if c == ".", i > 0, i < t.count - 1, isDigit(t[i - 1]), isDigit(t[i + 1]) { out.append(c) }
        }
        return out
    }

    /// 숫자 묶음마다 바로 뒤(일반 공백 0–1칸)의 단위 최장 일치, 대소문자 무시. 없으면 빈 문자열.
    static func unitSignature(_ text: String) -> [String] {
        let t = Array(text.filter { $0 != "," })
        let low = t.map { $0.lowercased() }
        var out: [String] = []
        var i = 0
        while i < t.count {
            guard digitsAndMagnitudes.contains(t[i]) else { i += 1; continue }
            var j = i
            while j < t.count, digitsAndMagnitudes.contains(t[j]) || t[j] == "." { j += 1 }
            var k = j
            if k < t.count, t[k] == " " { k += 1 }
            let unit = units.first { unit in k + unit.count <= low.count && Array(low[k..<(k + unit.count)]) == unit }
            out.append(unit?.joined() ?? "")
            i = j
        }
        return out
    }

    /// 공백을 지운 뒤 센 부정 표식 개수 + 낱말 첫머리 «안» 개수 + 영어 not·no·never·~n't.
    static func negationSignature(_ text: String) -> [String: Int] {
        let t = text.filter { !$0.isWhitespace }
        var counts: [String: Int] = [:]
        for mark in negationMarks { counts[mark] = occurrences(of: mark, in: t) }
        let chars = Array(text)
        counts["word-start-an"] = chars.indices.filter { chars[$0] == "안" && ($0 == 0 || !isWordCharacter(chars[$0 - 1])) }.count
        for token in englishTokens(text) where englishNegations.contains(token) || token.hasSuffix("n't") {
            counts["en:" + token, default: 0] += 1
        }
        return counts.filter { $0.value != 0 }
    }

    /// 공백을 지운 뒤 센 조건 표식 개수 + 영어 if·unless.
    static func conditionSignature(_ text: String) -> [String: Int] {
        let t = text.filter { !$0.isWhitespace }
        var counts: [String: Int] = [:]
        for mark in conditionMarks { counts[mark] = occurrences(of: mark, in: t) }
        for token in englishTokens(text) where englishConditions.contains(token) { counts["en:" + token, default: 0] += 1 }
        return counts.filter { $0.value != 0 }
    }

    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
    /// Python `\w`(유니코드 문자·숫자·밑줄)에 맞춘 판정.
    private static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
    /// 겹치지 않게 센 부분 문자열 개수 (Python `str.count`).
    private static func occurrences(of mark: String, in text: String) -> Int {
        var count = 0, start = text.startIndex
        while let range = text.range(of: mark, range: start..<text.endIndex) { count += 1; start = range.upperBound }
        return count
    }
    private static func englishTokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: tokenTrim).lowercased() }
    }
}
