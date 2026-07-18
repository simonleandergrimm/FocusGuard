import Foundation

/// Replaces a file by writing a temporary sibling (same directory, so
/// rename(2) stays on one filesystem) and renaming it over the destination.
/// Readers never observe truncated or partially written content, and the
/// explicit POSIX mode keeps root-written files readable by the user app.
public enum AtomicFile {
    public static func write(_ data: Data, toPath path: String, mode: Int16 = 0o644) throws {
        let destination = URL(fileURLWithPath: path)
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).focusguard.tmp")

        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: NSNumber(value: mode)]
        ) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        guard rename(temporary.path, destination.path) == 0 else {
            let renameError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(at: temporary)
            throw renameError
        }
    }
}
