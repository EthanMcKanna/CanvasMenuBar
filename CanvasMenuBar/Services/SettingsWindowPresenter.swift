import SwiftUI
import AppKit

final class SettingsWindowPresenter: NSObject {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?

    func present(settings: SettingsStore) {
        if let window {
            if let hosting = window.contentViewController as? NSHostingController<SettingsContainerView> {
                hosting.rootView = SettingsContainerView(settings: settings)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsContainerView(settings: settings))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Canvas Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 460, height: 480))
        window.level = .floating
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidClose(_:)),
                                               name: NSWindow.willCloseNotification,
                                               object: window)
        self.window = window
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
              closedWindow == window else { return }
        NotificationCenter.default.removeObserver(self,
                                                  name: NSWindow.willCloseNotification,
                                                  object: closedWindow)
        window = nil
    }
}

private struct SettingsContainerView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsView(settings: settings)
            .frame(minWidth: 420, idealWidth: 460, minHeight: 420)
    }
}
