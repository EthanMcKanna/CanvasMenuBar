import Foundation
import AppKit

@MainActor
final class AppUpdateInstaller: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading
        case installing
        case relaunching
        case success
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let fileManager = FileManager.default
    private let applicationName = "CanvasMenuBar"

    var isBusy: Bool {
        switch state {
        case .downloading, .installing, .relaunching:
            return true
        default:
            return false
        }
    }

    func install(update: AppUpdateChecker.AppUpdate) {
        guard let downloadURL = update.downloadURL else {
            NSWorkspace.shared.open(update.releaseURL)
            return
        }

        guard !isBusy else { return }

        state = .downloading
        Task {
            do {
                let dmgURL = try await downloadDMG(from: downloadURL)
                state = .installing
                try await installFromDMG(at: dmgURL)
                state = .relaunching
                relaunchApplication()
                state = .success
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func downloadDMG(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateInstallerError.downloadFailed
        }

        let destination = temporaryDirectory().appendingPathComponent(url.lastPathComponent)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: tempURL, to: destination)
        return destination
    }

    private func installFromDMG(at url: URL) async throws {
        let mount = try attachDiskImage(at: url)
        defer { try? detachDiskImage(device: mount.device) }

        let sourceAppURL = mount.mountPoint.appendingPathComponent("\(applicationName).app")
        guard fileManager.fileExists(atPath: sourceAppURL.path) else {
            throw AppUpdateInstallerError.missingAppBundle
        }

        let workingCopyURL = temporaryDirectory().appendingPathComponent("\(applicationName)-Install.app")
        try? fileManager.removeItem(at: workingCopyURL)
        try fileManager.copyItem(at: sourceAppURL, to: workingCopyURL)

        let destinationURL = preferredInstallLocation()
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL,
                                              withItemAt: workingCopyURL,
                                              backupItemName: nil,
                                              options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
        } else {
            try fileManager.copyItem(at: workingCopyURL, to: destinationURL)
            try fileManager.removeItem(at: workingCopyURL)
        }
        try? fileManager.removeItem(at: url)
    }

    private func relaunchApplication() {
        let appURL = preferredInstallLocation()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Failed to relaunch CanvasMenuBar: %@", error.localizedDescription)
            }
            NSApp?.terminate(nil)
        }
    }

    private func preferredInstallLocation() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.path.hasPrefix("/Applications") {
            return bundleURL
        }
        return URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleURL.lastPathComponent)
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private func attachDiskImage(at url: URL) throws -> MountedImage {
        let data = try runProcessCapture(executable: "/usr/bin/hdiutil",
                                         arguments: ["attach",
                                                     url.path,
                                                     "-nobrowse",
                                                     "-noautoopen",
                                                     "-noverify",
                                                     "-plist"])
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]],
              let match = entities.first(where: { $0["mount-point"] != nil }),
              let mountPoint = match["mount-point"] as? String,
              let device = match["dev-entry"] as? String else {
            throw AppUpdateInstallerError.mountFailed
        }
        return MountedImage(mountPoint: URL(fileURLWithPath: mountPoint), device: device)
    }

    private func detachDiskImage(device: String) throws {
        _ = try? runProcessCapture(executable: "/usr/bin/hdiutil", arguments: ["detach", device, "-quiet"])
    }

    private func runProcessCapture(executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppUpdateInstallerError.processFailed(message)
        }
        return data
    }
}

private struct MountedImage {
    let mountPoint: URL
    let device: String
}

enum AppUpdateInstallerError: LocalizedError {
    case downloadFailed
    case mountFailed
    case missingAppBundle
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Unable to download the latest release."
        case .mountFailed:
            return "Failed to mount the downloaded disk image."
        case .missingAppBundle:
            return "Could not find CanvasMenuBar.app in the downloaded disk image."
        case .processFailed(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
