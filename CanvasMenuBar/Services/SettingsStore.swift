import Foundation
import Combine

enum AssignmentsSourceConfiguration {
    case canvasAPI(CanvasCredentials)
    case calendarFeed(URL)
}

@MainActor
final class SettingsStore: ObservableObject {
    enum DataSource: String, CaseIterable, Identifiable {
        case apiToken
        case calendarFeed

        var id: String { rawValue }
        var title: String {
            switch self {
            case .apiToken:
                return "API Token"
            case .calendarFeed:
                return "Calendar Feed"
            }
        }
    }

    @Published var dataSource: DataSource {
        didSet {
            if dataSource != oldValue {
                defaults.set(dataSource.rawValue, forKey: Keys.dataSource)
                bumpConfigurationVersion()
            }
        }
    }

    @Published var baseURLInput: String {
        didSet {
            if baseURLInput != oldValue {
                defaults.set(baseURLInput, forKey: Keys.baseURL)
                bumpConfigurationVersion()
            }
        }
    }

    @Published var refreshMinutes: Int {
        didSet {
            if refreshMinutes < 5 {
                refreshMinutes = 5
                return
            }
            if refreshMinutes != oldValue {
                defaults.set(refreshMinutes, forKey: Keys.refreshMinutes)
                bumpConfigurationVersion()
            }
        }
    }

    @Published var icsFeedURLInput: String {
        didSet {
            if icsFeedURLInput != oldValue {
                defaults.set(icsFeedURLInput, forKey: Keys.icsFeedURL)
                bumpConfigurationVersion()
            }
        }
    }

    @Published var showAssignmentTracker: Bool {
        didSet {
            if showAssignmentTracker != oldValue {
                defaults.set(showAssignmentTracker, forKey: Keys.showAssignmentTracker)
                bumpConfigurationVersion()
            }
        }
    }

    @Published var showMenuBarCount: Bool {
        didSet {
            if showMenuBarCount != oldValue {
                defaults.set(showMenuBarCount, forKey: Keys.showMenuBarCount)
                bumpConfigurationVersion()
            }
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                try launchController.setEnabled(launchAtLogin)
                defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
                loginItemError = nil
            } catch {
                launchAtLogin = oldValue
                loginItemError = error.localizedDescription
            }
        }
    }

    @Published private(set) var configurationVersion: UUID = .init()
    @Published private(set) var lastTokenUpdate: Date?
    @Published private(set) var loginItemError: String?

    private let defaults: UserDefaults
    private let keychain: KeychainService
    private let launchController = LaunchAtLoginController()
    private let tokenAccount = "CanvasAPIToken"

    init(defaults: UserDefaults = .standard,
         keychain: KeychainService = KeychainService(service: "com.ethanmckanna.CanvasMenuBar")) {
        self.defaults = defaults
        self.keychain = keychain
        if let sourceRaw = defaults.string(forKey: Keys.dataSource),
           let storedSource = DataSource(rawValue: sourceRaw) {
            self.dataSource = storedSource
        } else {
            self.dataSource = .apiToken
        }
        self.baseURLInput = defaults.string(forKey: Keys.baseURL) ?? ""
        let storedMinutes = defaults.integer(forKey: Keys.refreshMinutes)
        self.refreshMinutes = storedMinutes == 0 ? 30 : storedMinutes
        self.icsFeedURLInput = defaults.string(forKey: Keys.icsFeedURL) ?? ""
        self.showAssignmentTracker = defaults.object(forKey: Keys.showAssignmentTracker) as? Bool ?? true
        self.showMenuBarCount = defaults.bool(forKey: Keys.showMenuBarCount)
        if defaults.object(forKey: Keys.launchAtLogin) != nil {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        } else {
            self.launchAtLogin = launchController.isEnabled
        }
        self.lastTokenUpdate = defaults.object(forKey: Keys.tokenTimestamp) as? Date
    }

    func saveToken(_ token: String) throws {
        try keychain.save(token, account: tokenAccount)
        let timestamp = Date()
        defaults.set(timestamp, forKey: Keys.tokenTimestamp)
        lastTokenUpdate = timestamp
        bumpConfigurationVersion()
    }

    func removeToken() throws {
        try keychain.delete(account: tokenAccount)
        lastTokenUpdate = nil
        defaults.removeObject(forKey: Keys.tokenTimestamp)
        bumpConfigurationVersion()
    }

    func isConfigured() -> Bool {
        sourceConfiguration() != nil
    }

    func sourceConfiguration() -> AssignmentsSourceConfiguration? {
        switch dataSource {
        case .apiToken:
            guard let baseURL = normalizedBaseURL(),
                  let token = keychain.read(account: tokenAccount),
                  !token.isEmpty else {
                return nil
            }
            return .canvasAPI(CanvasCredentials(baseURL: baseURL, token: token))
        case .calendarFeed:
            guard let url = normalizedICSURL() else {
                return nil
            }
            return .calendarFeed(url)
        }
    }

    var refreshInterval: TimeInterval {
        TimeInterval(refreshMinutes * 60)
    }

    private func normalizedBaseURL() -> URL? {
        var trimmed = baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        return URL(string: trimmed)
    }

    private func normalizedICSURL() -> URL? {
        let trimmed = icsFeedURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) {
            return url
        }
        return nil
    }

    private func bumpConfigurationVersion() {
        configurationVersion = UUID()
    }
}

private enum Keys {
    static let dataSource = "CanvasDataSource"
    static let baseURL = "CanvasBaseURL"
    static let refreshMinutes = "CanvasRefreshMinutes"
    static let tokenTimestamp = "CanvasTokenTimestamp"
    static let icsFeedURL = "CanvasICSFeedURL"
    static let showAssignmentTracker = "CanvasShowAssignmentTracker"
    static let showMenuBarCount = "CanvasShowMenuBarCount"
    static let launchAtLogin = "CanvasLaunchAtLogin"
}
