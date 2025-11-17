import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    @State private var apiTokenInput: String = ""
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green

    private var isAPIMode: Bool { settings.dataSource == .apiToken }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                SectionCard(title: "Data Source",
                            systemImage: "slider.horizontal.3",
                            description: "Choose how CanvasMenuBar pulls assignments for the day.") {
                    Picker("Data Source", selection: $settings.dataSource) {
                        ForEach(SettingsStore.DataSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(helpTextForCurrentSource)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isAPIMode {
                    SectionCard(title: "Canvas URL",
                                systemImage: "globe",
                                description: "Use the root Canvas domain you normally visit (no paths).") {
                        TextField("your-school.instructure.com", text: $settings.baseURLInput)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled(true)
                    }

                    SectionCard(title: "API Token",
                                systemImage: "key.fill",
                                description: "Generate from Canvas → Account → Settings → New Access Token.") {
                        SecureField("Paste token", text: $apiTokenInput)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Store Token", action: storeToken)
                                .buttonStyle(.borderedProminent)
                                .disabled(apiTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Remove Token", role: .destructive, action: removeToken)
                                .buttonStyle(.bordered)
                                .disabled(settings.sourceConfiguration() == nil)
                        }
                        tokenStatusView
                        Link("How do I create a Canvas token?",
                             destination: URL(string: "https://community.canvaslms.com/t5/Canvas-Basics-Guide/How-do-I-obtain-an-API-access-token-for-an-account/ta-p/386")!)
                            .font(.caption)
                    }
                } else {
                    SectionCard(title: "Calendar Feed URL",
                                systemImage: "link",
                                description: "Open Canvas Calendar → \"Calendar Feed\" button → copy the secret iCal link.") {
                        TextField("https://canvas.instructure.com/feeds/calendars/user_xxxxxxxxx.ics",
                                  text: $settings.icsFeedURLInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                    }
                }

                SectionCard(title: "Auto Refresh",
                            systemImage: "arrow.clockwise",
                            description: "Canvas assignments reload automatically while the app is running.") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frequency")
                            .font(.subheadline.weight(.semibold))
                        Picker("Frequency", selection: $settings.refreshMinutes) {
                            Text("Every 5 min").tag(5)
                            Text("Every 15 min").tag(15)
                            Text("Every 30 min").tag(30)
                            Text("Every hour").tag(60)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .accessibilityLabel("Auto refresh frequency")

                        Text("You can still refresh manually from the menu bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SectionCard(title: "Menu Bar",
                            systemImage: "menubar.rectangle",
                            description: "Customize what appears up top.") {
                    Toggle("Show remaining assignments count", isOn: $settings.showMenuBarCount)
                    Toggle("Enable assignment tracker", isOn: $settings.showAssignmentTracker)
                        .help("Hides the progress bar and completion checkmarks when off.")
                }

                SectionCard(title: "Startup",
                            systemImage: "power.circle",
                            description: "Keep CanvasMenuBar running after restart.") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .disabled(!ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)))
                    if let loginError = settings.loginItemError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("Requires macOS 13+.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SectionCard(title: "Diagnostics",
                            systemImage: "stethoscope",
                            description: nil) {
                    if let configuration = settings.sourceConfiguration() {
                        switch configuration {
                        case .canvasAPI(let creds):
                            Label("Connected via API: \(creds.baseURL.host ?? creds.baseURL.absoluteString)", systemImage: "checkmark.seal")
                        case .calendarFeed(let url):
                            Label("Using calendar feed", systemImage: "calendar")
                            Text(url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Not connected yet", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Canvas Settings")
                .font(.title2.weight(.semibold))
            Text("Configure your Canvas connection and refresh schedule. Changes apply instantly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var helpTextForCurrentSource: String {
        switch settings.dataSource {
        case .apiToken:
            return "Best experience with full assignment metadata. Requires a personal API token."
        case .calendarFeed:
            return "Uses Canvas' built-in Calendar feed (ICS). Great when API tokens are disabled."
        }
    }

    @ViewBuilder
    private var tokenStatusView: some View {
        if let statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundColor(statusColor)
        } else if let lastUpdated = settings.lastTokenUpdate {
            Text("Updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func storeToken() {
        let trimmed = apiTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try settings.saveToken(trimmed)
            apiTokenInput = ""
            statusMessage = "Token saved securely."
            statusColor = .green
        } catch {
            statusMessage = error.localizedDescription
            statusColor = .red
        }
    }

    private func removeToken() {
        do {
            try settings.removeToken()
            statusMessage = "Token removed."
            statusColor = .orange
        } catch {
            statusMessage = error.localizedDescription
            statusColor = .red
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let description: String?
    @ViewBuilder var content: Content

    init(title: String, systemImage: String, description: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05))
        )
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: SettingsStore())
            .frame(width: 480, height: 480)
    }
}
