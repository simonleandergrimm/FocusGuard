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
    private let statisticsRecorder: StatisticsRecorder
    private var lastDomains: Set<String>?
    private var lastTargets = Set<ProcessMatchTarget>()
    private var lastDisplayNames: [String: String] = [:]
    private var cyclesSinceLogSizeCheck = 0
    private var cyclesSinceStatisticsFlush = 0

    init(configuration: HelperConfiguration) {
        self.configuration = configuration
        let statisticsStore = BlockStatisticsStore(
            fileURL: configuration.policyURL
                .deletingLastPathComponent()
                .appendingPathComponent("stats.json")
        )
        let recorder = StatisticsRecorder(store: statisticsStore)
        self.statisticsRecorder = recorder
        self.landingPageServer = LandingPageServer(
            helperVersion: configuration.helperVersion,
            onWebsiteHit: { domain in
                recorder.recordWebsiteHit(domain: domain)
            }
        )
    }

    func runForever() -> Never {
        log("started for uid \(configuration.ownerUID)")
        landingPageServer.start()
        while true {
            autoreleasepool {
                runCycle()
            }
            flushStatisticsIfNeeded()
            capLogIfNeeded()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func flushStatisticsIfNeeded() {
        cyclesSinceStatisticsFlush += 1
        guard cyclesSinceStatisticsFlush >= 30 else { return }
        cyclesSinceStatisticsFlush = 0
        do {
            try statisticsRecorder.flushIfDirty()
        } catch {
            log("could not write statistics: \(error.localizedDescription)")
        }
    }

    /// launchd opens StandardOutPath without rotation, so an unattended
    /// helper would grow /var/log/focusguard-helper.log forever. Once an
    /// hour, truncate it back to zero when it exceeds the cap; the log fd is
    /// append-mode, so the next write simply restarts at the top.
    private func capLogIfNeeded() {
        cyclesSinceLogSizeCheck += 1
        guard cyclesSinceLogSizeCheck >= 3_600 else { return }
        cyclesSinceLogSizeCheck = 0

        var status = stat()
        let logSizeLimit: off_t = 5 * 1_024 * 1_024
        guard fstat(fileno(stdout), &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_size > logSizeLimit
        else { return }

        if ftruncate(fileno(stdout), 0) == 0 {
            log("log exceeded \(logSizeLimit) bytes; truncated")
        }
    }

    private func runCycle() {
        do {
            let document = try loadDocument()
            let activePlans = document.activePlans()
            landingPageServer.update(activePlans: activePlans)
            let domains = Set(activePlans.flatMap(\.domains))
            let targets = Set(activePlans.flatMap(\.applications).map {
                ProcessMatchTarget(executableName: $0.executableName, bundleName: $0.bundleName)
            })

            if lastDomains != domains {
                try updateHosts(blockedDomains: domains)
                lastDomains = domains
                log("updated hosts for \(domains.count) domain targets")
            }

            lastTargets = targets
            lastDisplayNames = Dictionary(
                activePlans.flatMap(\.applications).map { ($0.executableName, $0.displayName) },
                uniquingKeysWith: { first, _ in first }
            )
            terminateBlockedApplications(targets: targets)
        } catch {
            // Keep enforcing the last valid state if the policy is briefly unreadable.
            terminateBlockedApplications(targets: lastTargets)
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

        try HostsFileEditor.write(updated, toPath: path)
        Self.runAndWait("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        Self.runAndWait("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
    }

    private func terminateBlockedApplications(targets: Set<ProcessMatchTarget>) {
        let matchingProcesses = ProcessScanner.matching(
            targets: targets,
            ownerUID: configuration.ownerUID
        ).filter { $0.pid != getpid() }

        for process in matchingProcesses {
            guard process.pid != getpid() else { continue }
            if Darwin.kill(process.pid, SIGKILL) == 0 {
                statisticsRecorder.recordApplicationTermination(
                    displayName: lastDisplayNames[process.executableName] ?? process.executableName
                )
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
                try HostsFileEditor.write(cleaned, toPath: path)
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
