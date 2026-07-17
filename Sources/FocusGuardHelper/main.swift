import Darwin
import FocusGuardCore
import Foundation

private struct HelperConfiguration {
    let policyURL: URL
    let ownerUID: uid_t
    let helperVersion: Int

    static func parse(arguments: [String]) -> HelperConfiguration? {
        guard let policyIndex = arguments.firstIndex(of: "--policy"),
              arguments.indices.contains(policyIndex + 1),
              let uidIndex = arguments.firstIndex(of: "--owner-uid"),
              arguments.indices.contains(uidIndex + 1),
              let ownerUID = uid_t(arguments[uidIndex + 1]),
              let versionIndex = arguments.firstIndex(of: "--helper-version"),
              arguments.indices.contains(versionIndex + 1),
              let helperVersion = Int(arguments[versionIndex + 1])
        else { return nil }

        return HelperConfiguration(
            policyURL: URL(fileURLWithPath: arguments[policyIndex + 1]),
            ownerUID: ownerUID,
            helperVersion: helperVersion
        )
    }
}

private final class HelperEngine {
    private let configuration: HelperConfiguration
    private let landingPageServer: LandingPageServer
    private var lastDomains: Set<String>?
    private var lastExecutables = Set<String>()

    init(configuration: HelperConfiguration) {
        self.configuration = configuration
        self.landingPageServer = LandingPageServer(helperVersion: configuration.helperVersion)
    }

    func runForever() -> Never {
        log("started for uid \(configuration.ownerUID)")
        landingPageServer.start()
        while true {
            autoreleasepool {
                runCycle()
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func runCycle() {
        do {
            let document = try loadDocument()
            let activePlans = document.activePlans()
            landingPageServer.update(activePlans: activePlans)
            let domains = Set(activePlans.flatMap(\.domains))
            let executables = Set(activePlans.flatMap(\.applications).map(\.executableName))

            if lastDomains != domains {
                try updateHosts(blockedDomains: domains)
                lastDomains = domains
                log("updated hosts for \(domains.count) domain targets")
            }

            lastExecutables = executables
            terminateBlockedApplications(executableNames: executables)
        } catch {
            // Keep enforcing the last valid state if the policy is briefly unreadable.
            terminateBlockedApplications(executableNames: lastExecutables)
            log("policy read failed; retained prior state: \(error.localizedDescription)")
        }
    }

    private func loadDocument() throws -> BlockScheduleDocument {
        guard FileManager.default.fileExists(atPath: configuration.policyURL.path) else {
            return BlockScheduleDocument()
        }
        let data = try Data(contentsOf: configuration.policyURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BlockScheduleDocument.self, from: data)
    }

    private func updateHosts(blockedDomains: Set<String>) throws {
        let path = "/etc/hosts"
        let original = try String(contentsOfFile: path, encoding: .utf8)
        let updated = HostsFileEditor.updating(original, blockedDomains: blockedDomains)
        guard updated != original else { return }

        try updated.write(toFile: path, atomically: false, encoding: .utf8)
        Self.runAndWait("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        Self.runAndWait("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
    }

    private func terminateBlockedApplications(executableNames: Set<String>) {
        let matchingProcesses = ProcessScanner.matching(
            executableNames: executableNames,
            ownerUID: configuration.ownerUID
        ).filter { $0.pid != getpid() }

        for process in matchingProcesses {
            guard process.pid != getpid() else { continue }
            if Darwin.kill(process.pid, SIGKILL) == 0 {
                log("force-closed \(process.executableName) immediately (pid \(process.pid))")
            } else if errno != ESRCH {
                log("could not force-close \(process.executableName) (pid \(process.pid)): errno \(errno)")
            }
        }
    }

    private static func runAndWait(_ executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func log(_ message: String) {
        print("[FocusGuardHelper] \(ISO8601DateFormatter().string(from: Date())) \(message)")
        fflush(stdout)
    }
}

private enum FocusGuardHelperMain {
    static func main() {
        let arguments = CommandLine.arguments

        if arguments.contains("--clear-hosts") {
            do {
                let path = "/etc/hosts"
                let original = try String(contentsOfFile: path, encoding: .utf8)
                let cleaned = HostsFileEditor.updating(original, blockedDomains: [])
                try cleaned.write(toFile: path, atomically: false, encoding: .utf8)
                exit(EXIT_SUCCESS)
            } catch {
                fputs("FocusGuard cleanup failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        guard let configuration = HelperConfiguration.parse(arguments: arguments) else {
            fputs("usage: FocusGuardHelper --policy <path> --owner-uid <uid> --helper-version <version>\n", stderr)
            exit(EXIT_FAILURE)
        }

        HelperEngine(configuration: configuration).runForever()
    }
}

FocusGuardHelperMain.main()
