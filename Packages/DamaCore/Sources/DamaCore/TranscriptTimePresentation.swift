import Foundation

public enum TranscriptTimePresentation {
    public static let unavailable = "시간 미확인"

    public static func milliseconds(fromMicroseconds value: Microseconds?) -> Int64? {
        guard let value, value >= 0 else { return nil }
        let whole = value / 1_000
        return value % 1_000 >= 500 ? whole + 1 : whole
    }

    public static func timestamp(_ microseconds: Microseconds?) -> String {
        guard let milliseconds = milliseconds(fromMicroseconds: microseconds) else {
            return unavailable
        }
        let hours = milliseconds / 3_600_000
        let minutes = milliseconds / 60_000 % 60
        let seconds = milliseconds / 1_000 % 60
        let remainder = milliseconds % 1_000
        return String(format: "%02lld:%02lld:%02lld.%03lld", hours, minutes, seconds, remainder)
    }

    public static func durationMilliseconds(startUs: Microseconds?, endUs: Microseconds?) -> Int64? {
        guard let startUs, let endUs, startUs >= 0, endUs >= startUs else { return nil }
        return milliseconds(fromMicroseconds: endUs - startUs)
    }

    public static func duration(startUs: Microseconds?, endUs: Microseconds?) -> String {
        guard let value = durationMilliseconds(startUs: startUs, endUs: endUs) else {
            return unavailable
        }
        return "\(value)ms"
    }
}
