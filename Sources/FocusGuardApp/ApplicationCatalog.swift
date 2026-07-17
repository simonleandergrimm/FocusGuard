import Foundation
import FocusGuardCore

struct InstalledApplication: Hashable, Sendable {
    let displayName: String
    let bundleIdentifier: String
    let executableName: String
}

struct ApplicationResolution: Sendable {
    let applications: [BlockedApplication]
    let unresolvedNames: [String]
}

struct ApplicationCatalog: Sendable {
    let applications: [InstalledApplication]

    static func load(fileManager: FileManager = .default) -> ApplicationCatalog {
        var found = Set<InstalledApplication>()
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier,
                      !bundleIdentifier.hasPrefix("com.local.FocusGuard"),
                      let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
                else { continue }

                let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                found.insert(
                    InstalledApplication(
                        displayName: displayName,
                        bundleIdentifier: bundleIdentifier,
                        executableName: executableName
                    )
                )
            }
        }

        return ApplicationCatalog(applications: found.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending })
    }

    func resolve(names: [String]) -> ApplicationResolution {
        var resolved = Set<BlockedApplication>()
        var unresolved: [String] = []

        for name in names {
            let target = Self.normalized(name)
            let exactMatches = applications.filter {
                Self.normalized($0.displayName) == target || Self.normalized($0.executableName) == target
            }
            let candidates = exactMatches.isEmpty
                ? applications.filter {
                    Self.normalized($0.displayName).contains(target) || target.contains(Self.normalized($0.displayName))
                }
                : exactMatches

            guard candidates.count == 1, let application = candidates.first else {
                unresolved.append(name)
                continue
            }

            resolved.insert(
                BlockedApplication(
                    displayName: application.displayName,
                    bundleIdentifier: application.bundleIdentifier,
                    executableName: application.executableName
                )
            )
        }

        return ApplicationResolution(
            applications: resolved.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            unresolvedNames: unresolved
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
