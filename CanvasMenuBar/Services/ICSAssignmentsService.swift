import Foundation
import AppKit

actor ICSAssignmentsService {
    enum Error: LocalizedError {
        case invalidResponse
        case statusCode(Int)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Canvas calendar feed returned an unexpected response."
            case .statusCode(let code):
                return "Calendar feed responded with status code \(code)."
            case .decodingFailed:
                return "Unable to parse the Canvas calendar feed."
            }
        }
    }

    static let shared = ICSAssignmentsService()

    private struct FeedCache {
        var etag: String?
        var assignments: [Assignment]
        var assignmentsByDay: [String: [Assignment]]
        var lastValidated: Date
    }

    private let session: URLSession
    private var cache: [URL: FeedCache] = [:]
    private let dayFormatter: DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        self.dayFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            return formatter
        }()
    }

    func fetchAssignments(feedURL: URL, bounds: DayBounds, forceReload: Bool) async throws -> [Assignment] {
        var state = cache[feedURL]
        if forceReload || state == nil {
            let updated = try await downloadFeed(from: feedURL, existing: state)
            state = updated
            cache[feedURL] = updated
        }
        guard let finalState = state else {
            throw Error.decodingFailed
        }
        return assignments(in: finalState, bounds: bounds)
    }

    func invalidateCache(for url: URL? = nil) {
        if let url {
            cache[url] = nil
        } else {
            cache.removeAll()
        }
    }

    private func downloadFeed(from url: URL, existing: FeedCache?) async throws -> FeedCache {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("text/calendar", forHTTPHeaderField: "Accept")
        if let etag = existing?.etag {
            request.addValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        if httpResponse.statusCode == 304, let existing {
            var refreshed = existing
            refreshed.lastValidated = Date()
            refreshed.etag = httpResponse.value(forHTTPHeaderField: "Etag") ?? httpResponse.value(forHTTPHeaderField: "ETag") ?? existing.etag
            return refreshed
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Error.statusCode(httpResponse.statusCode)
        }

        guard let fileContents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw Error.decodingFailed
        }

        let events = ICSParser().parseEvents(from: fileContents)
        let assignments = events.compactMap { $0.asAssignment() }
        let grouped = buildDayIndex(for: assignments)
        let etag = httpResponse.value(forHTTPHeaderField: "Etag") ?? httpResponse.value(forHTTPHeaderField: "ETag")
        return FeedCache(etag: etag, assignments: assignments, assignmentsByDay: grouped, lastValidated: Date())
    }

    private func assignments(in cache: FeedCache, bounds: DayBounds) -> [Assignment] {
        let key = dayFormatter.string(from: Calendar.current.startOfDay(for: bounds.start))
        if let cached = cache.assignmentsByDay[key] {
            return cached.filter { assignment in
                guard let date = assignment.normalizedDueDate else { return false }
                return date.isWithin(bounds)
            }
        }
        return cache.assignments.filter { assignment in
            guard let date = assignment.normalizedDueDate else { return false }
            return date.isWithin(bounds)
        }
    }

    private func buildDayIndex(for assignments: [Assignment]) -> [String: [Assignment]] {
        var map: [String: [Assignment]] = [:]
        for assignment in assignments {
            guard let date = assignment.normalizedDueDate else { continue }
            let key = dayFormatter.string(from: Calendar.current.startOfDay(for: date))
            map[key, default: []].append(assignment)
        }
        return map
    }
}

private struct ICSParser {
    struct Event {
        var uid: String?
        var summary: String?
        var description: String?
        var htmlDescription: String?
        var startDate: Date?
        var endDate: Date?
        var isAllDay = false
        var url: URL?
        var location: String?
        var categories: [String] = []
    }

    func parseEvents(from contents: String) -> [Event] {
        let unfolded = unfoldLines(contents)
        var events: [Event] = []
        var currentLines: [String] = []

        func flushCurrent() {
            guard !currentLines.isEmpty else { return }
            if let event = parseEvent(from: currentLines) {
                events.append(event)
            }
            currentLines.removeAll()
        }

        for line in unfolded {
            if line == "BEGIN:VEVENT" {
                currentLines.removeAll()
            } else if line == "END:VEVENT" {
                flushCurrent()
            } else {
                currentLines.append(line)
            }
        }

        return events
    }

    private func parseEvent(from lines: [String]) -> Event? {
        var event = Event()

        for line in lines {
            guard let (key, params, value) = splitLine(line) else { continue }
            let decodedValue = ICSTextDecoder.unescape(value)
            switch key {
            case "UID":
                event.uid = decodedValue
            case "SUMMARY":
                event.summary = decodedValue
            case "DESCRIPTION":
                event.description = decodedValue
            case "DTSTART":
                let date = ICSDateParser.parse(value, tzid: params["TZID"], isDateOnly: params["VALUE"]?.uppercased() == "DATE")
                event.startDate = date
                if params["VALUE"]?.uppercased() == "DATE" {
                    event.isAllDay = true
                }
            case "DTEND":
                let date = ICSDateParser.parse(value, tzid: params["TZID"], isDateOnly: params["VALUE"]?.uppercased() == "DATE")
                event.endDate = date
            case "URL":
                event.url = URL(string: decodedValue)
            case "LOCATION":
                event.location = decodedValue
            case "X-ALT-DESC":
                event.htmlDescription = decodedValue
            case "CATEGORIES":
                let tokens = decodedValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                event.categories.append(contentsOf: tokens.filter { !$0.isEmpty })
            default:
                continue
            }
        }

        if event.startDate == nil {
            event.startDate = event.endDate
        }

        return event
    }

    private func unfoldLines(_ contents: String) -> [String] {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")
        var unfolded: [String] = []
        for line in rawLines {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard !unfolded.isEmpty else { continue }
                let trimmed = line.dropFirst()
                unfolded[unfolded.count - 1].append(String(trimmed))
            } else {
                unfolded.append(line)
            }
        }
        return unfolded
    }

    private func splitLine(_ line: String) -> (String, [String: String], String)? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let header = String(line[..<colonIndex])
        let value = String(line[line.index(after: colonIndex)...])
        let headerParts = header.split(separator: ";")
        guard let key = headerParts.first else { return nil }
        var params: [String: String] = [:]
        if headerParts.count > 1 {
            for param in headerParts.dropFirst() {
                let pieces = param.split(separator: "=", maxSplits: 1)
                if pieces.count == 2 {
                    params[String(pieces[0]).uppercased()] = String(pieces[1])
                }
            }
        }
        return (String(key), params, value)
    }
}

private extension ICSParser.Event {
    struct DescriptionContent {
        let plain: String?
        let rich: AttributedString?
    }

    var dueDate: Date? { startDate ?? endDate }

    func asAssignment() -> Assignment? {
        guard dueDate != nil else { return nil }
        let normalizedSummary = (summary ?? "Canvas Event").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = SummarySplitter.split(normalizedSummary)
        let description = descriptionContent()

        return Assignment(
            id: uid ?? UUID().uuidString,
            title: parts.title,
            courseName: parts.course,
            courseCode: nil,
            dueAt: startDate,
            allDayDate: startDate?.startOfDay,
            isAllDay: isAllDay,
            htmlURL: url,
            pointsPossible: nil,
            description: description.plain,
            richDescription: description.rich,
            location: location,
            kind: inferredKind(),
            tags: (categories + parts.tags).uniquePreservingOrder(),
            hasSubmittedSubmissions: nil,
            submission: nil
        )
    }

    func inferredKind() -> Assignment.Kind {
        guard let uid else { return .calendarEvent }
        let lower = uid.lowercased()
        if lower.contains("assignment") {
            return .assignment
        }
        return .calendarEvent
    }

    func descriptionContent() -> DescriptionContent {
        if let htmlDescription,
           let attributed = ICSTextDecoder.htmlToAttributedString(htmlDescription) {
            let plain = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                return DescriptionContent(plain: plain, rich: attributed)
            }
        }
        if let description,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DescriptionContent(plain: description, rich: nil)
        }
        return DescriptionContent(plain: nil, rich: nil)
    }
}

private struct SummaryParts {
    let title: String
    let course: String?
    let tags: [String]
}

private enum SummarySplitter {
    static func split(_ summary: String) -> SummaryParts {
        var remaining = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        var trailingTokens: [String] = []

        while remaining.hasSuffix("]") {
            guard let closingIndex = remaining.lastIndex(of: "]") else { break }
            guard let openingIndex = remaining[..<closingIndex].lastIndex(of: "[") else { break }
            let token = String(remaining[remaining.index(after: openingIndex)..<closingIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            trailingTokens.append(token)
            remaining = String(remaining[..<openingIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if remaining.isEmpty {
            remaining = "Canvas Event"
        }

        let course = trailingTokens.first?.nilIfEmpty
        let tags = Array(trailingTokens.dropFirst()).reversed().compactMap { $0.nilIfEmpty }

        return SummaryParts(title: remaining, course: course, tags: tags)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum ICSTextDecoder {
    static func unescape(_ text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            if character == "\\" {
                guard let next = iterator.next() else { break }
                switch next {
                case "n", "N":
                    result.append("\n")
                case ",":
                    result.append(",")
                case ";":
                    result.append(";")
                case "\\":
                    result.append("\\")
                default:
                    result.append(next)
                }
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func htmlToAttributedString(_ html: String) -> AttributedString? {
        let sanitized = stripDangerousTags(from: html)
        guard let data = sanitized.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        return AttributedString(attributed)
    }

    private static func stripDangerousTags(from html: String) -> String {
        let patterns = ["(?is)<script.*?>.*?</script>", "(?is)<style.*?>.*?</style>"]
        var sanitized = html
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
                sanitized = regex.stringByReplacingMatches(in: sanitized, options: [], range: range, withTemplate: "")
            }
        }
        return sanitized
    }
}
