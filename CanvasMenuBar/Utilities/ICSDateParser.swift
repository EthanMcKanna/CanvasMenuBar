import Foundation

enum ICSDateParser {
    static func parse(_ rawValue: String, tzid: String?, isDateOnly: Bool) -> Date? {
        if isDateOnly {
            return Self.dayFormatter.date(from: rawValue)
        }

        if rawValue.hasSuffix("Z") {
            return Self.utcDateTimeFormatter.date(from: rawValue)
        }

        return Self.localDateTimeFormatter(timeZone: tzid.flatMap(TimeZone.init(identifier:))).date(from: rawValue)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let utcDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func localDateTimeFormatter(timeZone: TimeZone?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = timeZone ?? TimeZone.current
        return formatter
    }
}
