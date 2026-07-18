import Darwin
import Foundation

public struct RunningProcess: Equatable, Sendable {
    public let pid: pid_t
    public let matchTarget: ProcessMatchTarget

    public var executableName: String { matchTarget.executableName }

    public init(pid: pid_t, executableName: String) {
        self.pid = pid
        self.matchTarget = ProcessMatchTarget(executableName: executableName)
    }

    public init(pid: pid_t, matchTarget: ProcessMatchTarget) {
        self.pid = pid
        self.matchTarget = matchTarget
    }
}

/// Identifies a process to terminate. Matching on the executable basename
/// alone is unsafe for generic names (an `Electron` executable could belong
/// to anything), so when `bundleName` is known the process's full path must
/// also run through that `.app` directory.
public struct ProcessMatchTarget: Hashable, Sendable {
    public let executableName: String
    public let bundleName: String?

    public init(executableName: String, bundleName: String? = nil) {
        self.executableName = executableName
        self.bundleName = bundleName
    }
}

public enum ProcessScanner {
    public static func matching(
        targets: Set<ProcessMatchTarget>,
        ownerUID: uid_t
    ) -> [RunningProcess] {
        guard !targets.isEmpty else { return [] }

        let capacity = 8_192
        var pids = [pid_t](repeating: 0, count: capacity)
        let pidCount = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard pidCount > 0 else { return [] }

        let count = min(Int(pidCount), pids.count)
        return pids.prefix(count).compactMap { pid in
            guard pid > 0 else { return nil }

            var info = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let copiedInfoSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize)
            guard copiedInfoSize == infoSize, info.pbi_uid == ownerUID else { return nil }

            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let pathLength = pathBuffer.withUnsafeMutableBufferPointer { buffer in
                proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
            }
            guard pathLength > 0 else { return nil }

            let path = pathBuffer.withUnsafeBufferPointer { buffer in
                String(cString: buffer.baseAddress!)
            }
            guard let target = target(matching: path, in: targets) else { return nil }
            return RunningProcess(pid: pid, matchTarget: target)
        }
    }

    public static func target(
        matching path: String,
        in targets: Set<ProcessMatchTarget>
    ) -> ProcessMatchTarget? {
        let executableName = URL(fileURLWithPath: path).lastPathComponent
        let executableTargets = targets.filter { $0.executableName == executableName }
        if let bundleMatch = executableTargets.first(where: { target in
            guard let bundleName = target.bundleName else { return false }
            return path.contains("/\(bundleName)/")
        }) {
            return bundleMatch
        }
        return executableTargets.first { $0.bundleName == nil }
    }
}
