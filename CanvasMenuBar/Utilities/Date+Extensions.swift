import Foundation

struct DayBounds {
    let start: Date
    let end: Date
}

extension Calendar {
    func dayBounds(for date: Date) -> DayBounds {
        let startOfDay = startOfDay(for: date)
        let endOfDay = self.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        return DayBounds(start: startOfDay, end: endOfDay)
    }
}

extension Date {
    func clamped(to bounds: DayBounds) -> Date {
        if self < bounds.start { return bounds.start }
        if self > bounds.end { return bounds.end }
        return self
    }

    func isWithin(_ bounds: DayBounds) -> Bool {
        self >= bounds.start && self < bounds.end
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}

enum CanvasDateFormatters {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
