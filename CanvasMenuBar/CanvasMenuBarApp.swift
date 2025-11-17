import SwiftUI

@main
struct CanvasMenuBarApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var assignmentsViewModel: AssignmentsViewModel

    init() {
        let settings = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settings)
        _assignmentsViewModel = StateObject(wrappedValue: AssignmentsViewModel(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            AssignmentsMenuView(viewModel: assignmentsViewModel, settings: settingsStore)
                .environmentObject(settingsStore)
        } label: {
            Label {
                Text("Canvas Assignments")
            } icon: {
                CalendarIconBadge(count: settingsStore.showMenuBarCount ? assignmentsViewModel.remainingAssignmentsCount : nil)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settingsStore)
        }
    }
}

private struct CalendarIconBadge: View {
    let count: Int?

    var body: some View {
        Group {
            if let count {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .offset(x: -5, y: 7)
                        .foregroundColor(.accentColor)
                    Text(badgeText(for: count))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .systemRed))
                        )
                        .foregroundColor(.white)
                        .offset(x: 8, y: -6)
                }
                .fixedSize()
            } else {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
    }

    private func badgeText(for value: Int) -> String {
        switch value {
        case ..<0:
            return "0"
        case 0...99:
            return "\(value)"
        default:
            return "99+"
        }
    }
}
