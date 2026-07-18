import Darwin
import Foundation
import FocusGuardCore

enum HelperInstallerError: LocalizedError {
    case helperMissing
    case authorizationCancelled
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            "FocusGuardHelper is missing. Build the app with Scripts/build-app.sh first."
        case .authorizationCancelled:
            "macOS administrator approval was cancelled. FocusGuard will keep offering a Repair action."
        case .authorizationFailed(let message):
            message.isEmpty ? "The helper could not be installed." : message
        }
    }
}

enum HelperInstallationState: Equatable, Sendable {
    case missing
    case outdated(installedVersion: Int?)
    case stopped
    case healthy

    var isOperational: Bool {
        self == .healthy
    }

    var needsRepair: Bool {
        self != .healthy
    }

    var description: String {
        switch self {
        case .missing: "Helper setup required"
        case .outdated: "Helper update required"
        case .stopped: "Helper needs repair"
        case .healthy: "Helper healthy"
        }
    }

    var actionTitle: String {
        switch self {
        case .missing: "Set up"
        case .outdated: "Update"
        case .stopped: "Repair"
        case .healthy: ""
        }
    }
}

struct HelperInstaller: Sendable {
    static let label = "com.local.FocusGuard.helper"
    static let installedExecutablePath = "/Library/PrivilegedHelperTools/FocusGuardHelper"
    static let installedPlistPath = "/Library/LaunchDaemons/\(label).plist"
    static let requiredVersion = FocusGuardHelperProtocol.currentVersion

    let policyURL: URL

    func install() throws {
        guard let sourceHelperURL = Self.bundledHelperURL(), FileManager.default.isExecutableFile(atPath: sourceHelperURL.path) else {
            throw HelperInstallerError.helperMissing
        }

        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FocusGuard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let plistURL = temporaryDirectory.appendingPathComponent("\(Self.label).plist")
        let scriptURL = temporaryDirectory.appendingPathComponent("install-helper.sh")
        try Self.plist(policyURL: policyURL).write(to: plistURL, atomically: true, encoding: .utf8)
        try Self.installScript(sourceHelperURL: sourceHelperURL, sourcePlistURL: plistURL)
            .write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let appleScript = "do shell script \"/bin/sh \" & quoted form of \"\(Self.appleScriptEscaped(scriptURL.path))\" with administrator privileges"
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            if message.localizedCaseInsensitiveContains("user canceled") || message.contains("(-128)") {
                throw HelperInstallerError.authorizationCancelled
            }
            throw HelperInstallerError.authorizationFailed(message)
        }
    }

    static func status() -> HelperInstallationState {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: installedExecutablePath),
              fileManager.fileExists(atPath: installedPlistPath)
        else { return .missing }

        let installedVersion = versionInInstalledPlist()
        guard let installedVersion, installedVersion >= requiredVersion else {
            return .outdated(installedVersion: installedVersion)
        }
        return isRunning() ? .healthy : .stopped
    }

    private static func isRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(label)"]
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

    private static func versionInInstalledPlist() -> Int? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: installedPlistPath)),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any],
              let arguments = dictionary["ProgramArguments"] as? [String],
              let versionIndex = arguments.firstIndex(of: "--helper-version"),
              arguments.indices.contains(versionIndex + 1)
        else { return nil }
        return Int(arguments[versionIndex + 1])
    }

    private static func bundledHelperURL() -> URL? {
        let bundleCandidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/FocusGuardHelper")
        if FileManager.default.fileExists(atPath: bundleCandidate.path) {
            return bundleCandidate
        }

        guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let siblingCandidate = executableDirectory.appendingPathComponent("FocusGuardHelper")
        return FileManager.default.fileExists(atPath: siblingCandidate.path) ? siblingCandidate : nil
    }

    private static func plist(policyURL: URL) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(installedExecutablePath)</string>
                <string>--policy</string>
                <string>\(xmlEscaped(policyURL.path))</string>
                <string>--owner-uid</string>
                <string>\(getuid())</string>
                <string>--helper-version</string>
                <string>\(requiredVersion)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ThrottleInterval</key>
            <integer>2</integer>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>StandardOutPath</key>
            <string>/var/log/focusguard-helper.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/focusguard-helper.log</string>
        </dict>
        </plist>
        """
    }

    private static func installScript(sourceHelperURL: URL, sourcePlistURL: URL) -> String {
        """
        #!/bin/sh
        set -eu

        if /bin/launchctl print system/\(label) >/dev/null 2>&1; then
            /bin/launchctl bootout system/\(label)
        fi

        /usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
        /usr/bin/install -o root -g wheel -m 755 \(shellQuoted(sourceHelperURL.path)) \(shellQuoted(installedExecutablePath))
        /usr/bin/install -o root -g wheel -m 644 \(shellQuoted(sourcePlistURL.path)) \(shellQuoted(installedPlistPath))
        /bin/launchctl bootstrap system \(shellQuoted(installedPlistPath))
        /bin/launchctl enable system/\(label)
        /bin/launchctl kickstart -k system/\(label)
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
