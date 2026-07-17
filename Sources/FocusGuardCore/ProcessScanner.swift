import Darwin
import Foundation

public struct RunningProcess: Equatable, Sendable {
    public let pid: pid_t
    public let executableName: String

    public init(pid: pid_t, executableName: String) {
        self.pid = pid
        self.executableName = executableName
    }
}

public enum ProcessScanner {
    public static func matching(
        executableNames: Set<String>,
        ownerUID: uid_t
    ) -> [RunningProcess] {
        guard !executableNames.isEmpty else { return [] }

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
            let executableName = URL(fileURLWithPath: path).lastPathComponent
            guard executableNames.contains(executableName) else { return nil }
            return RunningProcess(pid: pid, executableName: executableName)
        }
    }
}
