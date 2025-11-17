import Foundation

struct ICSAssignmentsService {
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

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAssignments(feedURL: URL, bounds: DayBounds) async throws -> [Assignment] {
        var request = URLRequest(url: feedURL)
        request.httpMethod = "GET"
        request.addValue("text/calendar", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Error.statusCode(httpResponse.statusCode)
        }

        guard let fileContents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw Error.decodingFailed
        }

        let events = ICSParser().parseEvents(from: fileContents)
        let assignments = events.compactMap { event -> Assignment? in
            guard let dueDate = event.dueDate else { return nil }
            guard dueDate.isWithin(bounds) else { return nil }
            return event.asAssignment()
        }
        return assignments
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
        let rawLines = contents.components(separatedBy: CharacterSet.newlines)
        var unfolded: [String] = []
        for line in rawLines {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                let trimmed = line.dropFirst()
                if var last = unfolded.popLast() {
                    last.append(String(trimmed))
                    unfolded.append(last)
                }
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
    var dueDate: Date? { startDate ?? endDate }

    func asAssignment() -> Assignment {
        let normalizedSummary = (summary ?? "Canvas Event").trimmingCharacters(in: .whitespacesAndNewlines)
        let extracted = SummarySplitter.split(normalizedSummary)
        let detailText = sanitizedDescription()

        return Assignment(
            id: uid ?? UUID().uuidString,
            title: extracted.title,
            courseName: extracted.course,
            courseCode: nil,
            dueAt: startDate,
            allDayDate: startDate?.startOfDay,
            isAllDay: isAllDay,
            htmlURL: url,
            pointsPossible: nil,
            description: detailText,
            location: location,
            kind: inferredKind(),
            tags: categories,
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

    func sanitizedDescription() -> String? {
        if let htmlDescription,
           let plain = ICSTextDecoder.htmlToPlainText(htmlDescription)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            return plain
        }
        if let description,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }
        return nil
    }
}

private enum SummarySplitter {
    static func split(_ summary: String) -> (title: String, course: String?) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let closingIndex = trimmed.lastIndex(of: "]"),
              trimmed.index(after: closingIndex) == trimmed.endIndex,
              let openingIndex = trimmed[..<closingIndex].lastIndex(of: "[") else {
            return (title: trimmed, course: nil)
        }

        let course = String(trimmed[trimmed.index(after: openingIndex)..<closingIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        var title = String(trimmed[..<openingIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = course.isEmpty ? trimmed : "Canvas Event"
        }
        return (title: title, course: course.isEmpty ? nil : course)
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

    static func htmlToPlainText(_ html: String) -> String? {
        guard let data = html.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }
}
