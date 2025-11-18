import Foundation

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let id: Int
        let name: String
        let contentType: String?
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case contentType = "content_type"
            case browserDownloadURL = "browser_download_url"
        }
    }

    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

enum GitHubReleaseServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case statusCode(Int)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Unable to build GitHub releases URL."
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        case .statusCode(let code):
            return "GitHub responded with status code \(code)."
        case .decoding:
            return "Unable to decode release details."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

final class GitHubReleaseService {
    private let owner: String
    private let repository: String
    private let session: URLSession

    init(owner: String = "EthanMcKanna",
         repository: String = "CanvasMenuBar",
         session: URLSession = GitHubReleaseService.makeSession()) {
        self.owner = owner
        self.repository = repository
        self.session = session
    }

    func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest") else {
            throw GitHubReleaseServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CanvasMenuBar/\(Bundle.main.releaseVersionNumber)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubReleaseServiceError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw GitHubReleaseServiceError.statusCode(httpResponse.statusCode)
            }

            let decoder = GitHubReleaseService.makeDecoder()
            do {
                return try decoder.decode(GitHubRelease.self, from: data)
            } catch {
                if let decodingError = error as? DecodingError {
                    throw GitHubReleaseServiceError.decoding(decodingError)
                }
                throw GitHubReleaseServiceError.decoding(error)
            }
        } catch let error as GitHubReleaseServiceError {
            throw error
        } catch {
            throw GitHubReleaseServiceError.network(error)
        }
    }
}

private extension GitHubReleaseService {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
