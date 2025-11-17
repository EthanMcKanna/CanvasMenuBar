import Foundation

struct CanvasCredentials: Equatable {
    let baseURL: URL
    let token: String
}

enum CanvasAPIError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case unauthorized
    case statusCode(Int)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Canvas settings are incomplete."
        case .invalidResponse:
            return "Canvas returned an unexpected response."
        case .unauthorized:
            return "Canvas rejected the API token. Double-check it in Settings."
        case .statusCode(let code):
            return "Canvas responded with status code \(code)."
        case .decoding:
            return "Unable to decode Canvas data."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

final class CanvasAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = CanvasAPI.makeSession()) {
        self.session = session
        self.decoder = CanvasAPI.makeDecoder()
    }

    func fetchAssignments(credentials: CanvasCredentials, bounds: DayBounds, contextCodes: [String] = []) async throws -> [Assignment] {
        var events: [CanvasCalendarEvent] = []
        var nextPageURL: URL? = try makeAssignmentsURL(baseURL: credentials.baseURL, bounds: bounds, contextCodes: contextCodes)

        while let pageURL = nextPageURL {
            var request = URLRequest(url: pageURL)
            request.httpMethod = "GET"
            request.addValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CanvasAPIError.invalidResponse
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    let decoded = try decoder.decode([CanvasCalendarEvent].self, from: data)
                    events.append(contentsOf: decoded)
                    nextPageURL = CanvasAPI.nextPageURL(from: httpResponse)
                case 401:
                    throw CanvasAPIError.unauthorized
                default:
                    throw CanvasAPIError.statusCode(httpResponse.statusCode)
                }
            } catch let error as CanvasAPIError {
                throw error
            } catch {
                if error is DecodingError {
                    throw CanvasAPIError.decoding(error)
                }
                throw CanvasAPIError.network(error)
            }
        }

        return events.compactMap { $0.toAssignment(filteredBy: bounds) }
    }
}

private extension CanvasAPI {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = CanvasDateFormatters.iso8601WithFractional.date(from: value) {
                return date
            }
            if let date = CanvasDateFormatters.iso8601.date(from: value) {
                return date
            }
            if let date = CanvasDateFormatters.dayFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unexpected date format: \(value)")
        }
        return decoder
    }

    func makeAssignmentsURL(baseURL: URL, bounds: DayBounds, contextCodes: [String]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw CanvasAPIError.invalidConfiguration
        }

        var path = components.path
        if !path.hasSuffix("/") {
            path.append("/")
        }
        path.append("api/v1/calendar_events")
        components.path = path

        var items = [
            URLQueryItem(name: "type", value: "assignment"),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "start_date", value: CanvasAPI.isoString(bounds.start)),
            URLQueryItem(name: "end_date", value: CanvasAPI.isoString(bounds.end))
        ]

        for code in contextCodes {
            items.append(URLQueryItem(name: "context_codes[]", value: code))
        }

        components.queryItems = items

        guard let url = components.url else {
            throw CanvasAPIError.invalidConfiguration
        }
        return url
    }

    static func isoString(_ date: Date) -> String {
        CanvasDateFormatters.iso8601WithFractional.string(from: date)
    }

    static func nextPageURL(from response: HTTPURLResponse) -> URL? {
        guard let header = response.value(forHTTPHeaderField: "Link") else { return nil }
        let parts = header.split(separator: ",")
        for part in parts {
            let components = part.split(separator: ";")
            guard components.count >= 2 else { continue }
            let urlPart = components[0].trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
            let relPart = components[1].trimmingCharacters(in: .whitespaces)
            if relPart.contains("rel=\"next\"") {
                return URL(string: urlPart)
            }
        }
        return nil
    }
}

private struct CanvasCalendarEvent: Decodable {
    struct AssignmentPayload: Decodable {
        struct Submission: Decodable {
            let submittedAt: Date?
            let gradedAt: Date?
            let workflowState: String?
            let score: Double?

            enum CodingKeys: String, CodingKey {
                case submittedAt = "submitted_at"
                case gradedAt = "graded_at"
                case workflowState = "workflow_state"
                case score
            }
        }

        let id: Int
        let dueAt: Date?
        let htmlURL: URL?
        let pointsPossible: Double?
        let hasSubmittedSubmissions: Bool?
        let submission: Submission?
        let courseID: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case dueAt = "due_at"
            case htmlURL = "html_url"
            case pointsPossible = "points_possible"
            case hasSubmittedSubmissions = "has_submitted_submissions"
            case submission
            case courseID = "course_id"
        }
    }

    let id: String
    let title: String
    let startAt: Date?
    let endAt: Date?
    let allDay: Bool?
    let allDayDate: Date?
    let htmlURL: URL?
    let contextName: String?
    let contextCode: String?
    let assignment: AssignmentPayload?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case allDayDate = "all_day_date"
        case htmlURL = "html_url"
        case contextName = "context_name"
        case contextCode = "context_code"
        case assignment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            let numericID = try container.decode(Int.self, forKey: .id)
            id = String(numericID)
        }
        title = try container.decode(String.self, forKey: .title)
        startAt = try container.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try container.decodeIfPresent(Date.self, forKey: .endAt)
        allDay = try container.decodeIfPresent(Bool.self, forKey: .allDay)
        if let dayString = try container.decodeIfPresent(String.self, forKey: .allDayDate) {
            allDayDate = CanvasDateFormatters.dayFormatter.date(from: dayString)
        } else {
            allDayDate = nil
        }
        htmlURL = try container.decodeIfPresent(URL.self, forKey: .htmlURL)
        contextName = try container.decodeIfPresent(String.self, forKey: .contextName)
        contextCode = try container.decodeIfPresent(String.self, forKey: .contextCode)
        assignment = try container.decodeIfPresent(AssignmentPayload.self, forKey: .assignment)
    }

    func toAssignment(filteredBy bounds: DayBounds) -> Assignment? {
        let dueDate = assignment?.dueAt ?? endAt ?? startAt ?? allDayDate
        if let dueDate, !dueDate.isWithin(bounds) {
            return nil
        }

        let submission = assignment?.submission.map { payload in
            Assignment.SubmissionInfo(
                submittedAt: payload.submittedAt,
                gradedAt: payload.gradedAt,
                state: payload.workflowState,
                score: payload.score
            )
        }

        return Assignment(
            id: id,
            title: title,
            courseName: contextName,
            courseCode: contextCode,
            dueAt: assignment?.dueAt ?? endAt ?? startAt,
            allDayDate: allDayDate,
            isAllDay: allDay ?? false,
            htmlURL: assignment?.htmlURL ?? htmlURL,
            pointsPossible: assignment?.pointsPossible,
            description: nil,
            location: nil,
            kind: .assignment,
            tags: [],
            hasSubmittedSubmissions: assignment?.hasSubmittedSubmissions,
            submission: submission
        )
    }
}
