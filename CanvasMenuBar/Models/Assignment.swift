import Foundation

struct Assignment: Identifiable, Equatable {
    enum Kind: String, Codable {
        case assignment
        case calendarEvent

        var badgeLabel: String {
            switch self {
            case .assignment:
                return "Assignment"
            case .calendarEvent:
                return "Event"
            }
        }
    }

    struct SubmissionInfo: Equatable {
        let submittedAt: Date?
        let gradedAt: Date?
        let state: String?
        let score: Double?
    }

    let id: String
    let title: String
    let courseName: String?
    let courseCode: String?
    let dueAt: Date?
    let allDayDate: Date?
    let isAllDay: Bool
    let htmlURL: URL?
    let pointsPossible: Double?
    let description: String?
    let richDescription: AttributedString?
    let location: String?
    let kind: Kind
    let tags: [String]
    let hasSubmittedSubmissions: Bool?
    let submission: SubmissionInfo?

    var normalizedDueDate: Date? {
        dueAt ?? allDayDate
    }

    var displayCourse: String {
        if let courseName, !courseName.isEmpty { return courseName }
        if let courseCode, !courseCode.isEmpty {
            if courseCode.hasPrefix("course_"), let identifier = courseCode.split(separator: "_").last {
                return "Course #\(identifier)"
            }
            return courseCode
        }
        return "Canvas"
    }

    var relativeDueText: String {
        guard let normalizedDueDate else { return "No due date" }
        return CanvasDateFormatters.relativeFormatter.localizedString(for: normalizedDueDate, relativeTo: Date())
    }

    var dueTimeLabel: String {
        guard let normalizedDueDate else { return "No due date" }
        if isAllDay {
            return "All day"
        }
        return normalizedDueDate.formatted(date: .omitted, time: .shortened)
    }

    var locationLine: String? {
        guard let location else { return nil }
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isOverdue: Bool {
        guard let normalizedDueDate else { return false }
        let now = Date()
        if isAllDay {
            let comparison = Calendar.current.compare(normalizedDueDate.startOfDay, to: now, toGranularity: .day)
            return comparison == .orderedAscending && !isSubmitted
        }
        return normalizedDueDate < now && !isSubmitted
    }

    var isSubmitted: Bool {
        if let submission {
            if let state = submission.state?.lowercased() {
                if state == "submitted" || state == "graded" { return true }
            }
            if submission.submittedAt != nil { return true }
        }
        return hasSubmittedSubmissions ?? false
    }

    var submissionDescription: String {
        guard let submission else { return isSubmitted ? "Submitted" : "Not Submitted" }
        if let state = submission.state?.capitalized { return state }
        if submission.submittedAt != nil { return "Submitted" }
        return "Not Submitted"
    }

    var detailSnippet: String? {
        guard let description else {
            if let richDescription, !richDescription.characters.isEmpty {
                let plain = String(richDescription.characters)
                return Assignment.makeSnippet(from: plain)
            }
            return nil
        }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Assignment.makeSnippet(from: trimmed)
    }

    var metadataBadges: [String] {
        var badges: [String] = []
        if kind == .calendarEvent {
            badges.append(kind.badgeLabel)
        }
        badges.append(contentsOf: tags)
        return badges.uniquePreservingOrder()
    }

    var hasDetails: Bool {
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let richDescription, !richDescription.characters.isEmpty {
            return true
        }
        return false
    }

    var mapsURL: URL? {
        guard let locationLine,
              let encoded = locationLine.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    static func makeSnippet(from text: String) -> String? {
        let lines = text.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.prefix(3).joined(separator: " \u{2022} ")
    }
}

extension Array where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return self.filter { element in
            if seen.contains(element) { return false }
            seen.insert(element)
            return true
        }
    }
}
