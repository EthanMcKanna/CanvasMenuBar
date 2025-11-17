import Foundation
import ServiceManagement

struct LaunchAtLoginController {
    enum LaunchError: LocalizedError {
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "Launch at login requires macOS 13 or newer."
            }
        }
    }

    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LaunchError.unsupported
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
