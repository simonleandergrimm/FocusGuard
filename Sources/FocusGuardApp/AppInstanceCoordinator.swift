import AppKit
import Darwin
import Foundation

@MainActor
enum AppInstanceCoordinator {
    private static let bundleIdentifier = "com.local.FocusGuard"
    private static let canonicalAppURL = URL(fileURLWithPath: "/Applications/FocusGuard.app", isDirectory: true)
    private static var lockDescriptor: Int32 = -1

    static func shouldContinueLaunching() -> Bool {
        let currentAppURL = Bundle.main.bundleURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let installedAppURL = canonicalAppURL
            .standardizedFileURL
            .resolvingSymlinksInPath()

        if currentAppURL.pathExtension.lowercased() == "app",
           currentAppURL != installedAppURL,
           FileManager.default.fileExists(atPath: installedAppURL.path),
           routeToInstalledCopy(at: installedAppURL)
        {
            return false
        }

        return acquireProcessLock()
    }

    private static func routeToInstalledCopy(at installedAppURL: URL) -> Bool {
        if let running = runningApplications(excludingCurrentProcess: true).first(where: {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == installedAppURL
        }) {
            running.activate(options: [.activateAllWindows])
            return true
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", installedAppURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func acquireProcessLock() -> Bool {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusGuard", isDirectory: true)
        do {
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        } catch {
            return allowOnlyWhenNoOtherAppIsVisible()
        }

        let lockURL = supportDirectory.appendingPathComponent("app-instance.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else {
            return allowOnlyWhenNoOtherAppIsVisible()
        }

        guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
            Darwin.close(descriptor)
            activateExistingApplication()
            return false
        }

        _ = Darwin.fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        lockDescriptor = descriptor
        return true
    }

    private static func allowOnlyWhenNoOtherAppIsVisible() -> Bool {
        let others = runningApplications(excludingCurrentProcess: true)
        if let existing = others.first {
            existing.activate(options: [.activateAllWindows])
            return false
        }
        return true
    }

    private static func activateExistingApplication() {
        // The lock can be acquired slightly before Launch Services publishes the
        // first process, so give that process a brief chance to become visible.
        for _ in 0..<10 {
            if let existing = runningApplications(excludingCurrentProcess: true).first {
                existing.activate(options: [.activateAllWindows])
                return
            }
            usleep(50_000)
        }
    }

    private static func runningApplications(
        excludingCurrentProcess: Bool
    ) -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !excludingCurrentProcess || $0.processIdentifier != currentPID }
            .sorted { lhs, rhs in
                let lhsCanonical = lhs.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == canonicalAppURL
                let rhsCanonical = rhs.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == canonicalAppURL
                return lhsCanonical && !rhsCanonical
            }
    }
}
