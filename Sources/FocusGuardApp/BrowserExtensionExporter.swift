import Foundation

enum BrowserExtensionExporterError: LocalizedError {
    case bundledExtensionMissing

    var errorDescription: String? {
        switch self {
        case .bundledExtensionMissing:
            "The bundled browser extension is missing. Rebuild the packaged app."
        }
    }
}

enum BrowserExtensionExporter {
    static func export() throws -> URL {
        let fileManager = FileManager.default
        guard let resourcesURL = Bundle.main.resourceURL else {
            throw BrowserExtensionExporterError.bundledExtensionMissing
        }

        let sourceURL = resourcesURL.appendingPathComponent("BrowserExtension", isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw BrowserExtensionExporterError.bundledExtensionMissing
        }

        let supportURL = supportURL(fileManager: fileManager)
        let destinationURL = destinationURL(fileManager: fileManager)
        try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    /// Keep an already loaded unpacked extension in sync when the app is upgraded.
    /// The folder is left untouched until the person has explicitly exported it once.
    static func refreshIfPreviouslyExported() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destinationURL(fileManager: fileManager).path) else { return }
        _ = try export()
    }

    private static func supportURL(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusGuard", isDirectory: true)
    }

    private static func destinationURL(fileManager: FileManager) -> URL {
        supportURL(fileManager: fileManager)
            .appendingPathComponent("BrowserExtension", isDirectory: true)
    }
}
