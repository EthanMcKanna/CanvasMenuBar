import Foundation

final class CompletionStore {
    private let defaults: UserDefaults
    private let key = "AssignmentCompletions"
    private let calendar = Calendar.current
    private var cache: [String: Set<String>]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.dictionary(forKey: key) as? [String: [String]] {
            var parsed: [String: Set<String>] = [:]
            for (dateKey, ids) in stored {
                parsed[dateKey] = Set(ids)
            }
            cache = parsed
        } else {
            cache = [:]
        }
    }

    func completions(for date: Date) -> Set<String> {
        cache[dayKey(for: date)] ?? []
    }

    func toggle(id: String, on date: Date) -> Set<String> {
        let key = dayKey(for: date)
        var set = cache[key] ?? []
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
        cache[key] = set
        persist()
        return set
    }

    private func persist() {
        var output: [String: [String]] = [:]
        for (day, ids) in cache {
            output[day] = Array(ids)
        }
        defaults.set(output, forKey: key)
    }

    private func dayKey(for date: Date) -> String {
        let start = calendar.startOfDay(for: date)
        return ISO8601DayFormatter.shared.string(from: start)
    }
}

private enum ISO8601DayFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
