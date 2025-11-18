import Foundation
import Combine

@MainActor
final class AppUpdateChecker: ObservableObject {
    struct AppUpdate: Identifiable, Equatable {
        let latestVersion: String
        let releaseURL: URL
        let downloadURL: URL?
        let publishedAt: Date?
        let notes: String?

        var id: String { latestVersion }
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(latestVersion: String)
        case updateAvailable(AppUpdate)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheckedAt: Date?

    let currentVersion: String

    private let service: GitHubReleaseService
    private let currentSemanticVersion: SemanticVersion?
    private var hasLoadedOnce = false

    init(currentVersion: String = Bundle.main.releaseVersionNumber,
         service: GitHubReleaseService = GitHubReleaseService()) {
        self.currentVersion = currentVersion
        self.service = service
        self.currentSemanticVersion = SemanticVersion(string: currentVersion)
    }

    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        await performCheck()
    }

    func refresh() {
        Task { await performCheck() }
    }

    private func performCheck() async {
        state = .checking
        do {
            let release = try await service.fetchLatestRelease()
            let normalizedLatestVersion = Self.normalizedVersion(from: release.tagName)
            lastCheckedAt = Date()

            if isLatestNewerThanCurrent(tagName: release.tagName) {
                let update = AppUpdate(latestVersion: normalizedLatestVersion,
                                       releaseURL: release.htmlURL,
                                       downloadURL: preferredDownloadURL(from: release),
                                       publishedAt: release.publishedAt,
                                       notes: release.body)
                state = .updateAvailable(update)
            } else {
                state = .upToDate(latestVersion: normalizedLatestVersion)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func isLatestNewerThanCurrent(tagName: String) -> Bool {
        guard let latestSemantic = SemanticVersion(string: tagName) else {
            let normalizedLatest = Self.normalizedVersion(from: tagName)
            let normalizedCurrent = Self.normalizedVersion(from: currentVersion)
            return normalizedLatest.compare(normalizedCurrent, options: .numeric) == .orderedDescending
        }

        guard let currentSemanticVersion else {
            return true
        }

        return latestSemantic > currentSemanticVersion
    }

    private func preferredDownloadURL(from release: GitHubRelease) -> URL? {
        if let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            return dmgAsset.browserDownloadURL
        }
        return release.assets.first?.browserDownloadURL
    }

    private static func normalizedVersion(from string: String) -> String {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        return cleaned.isEmpty ? string : cleaned
    }
}

extension AppUpdateChecker {
    var availableUpdate: AppUpdate? {
        if case .updateAvailable(let update) = state {
            return update
        }
        return nil
    }

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = state {
            return message
        }
        return nil
    }

    var latestRemoteVersion: String? {
        switch state {
        case .upToDate(let version):
            return version
        case .updateAvailable(let update):
            return update.latestVersion
        default:
            return nil
        }
    }
}
