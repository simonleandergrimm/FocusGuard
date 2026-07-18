import Foundation

/// Caches the installed-application catalog so views and previews never scan
/// /Applications synchronously on the main thread. The scan runs once at
/// startup (`warm()`), is reused by everyone who asks (`catalog()`), and can
/// be rescanned when freshness matters (`refresh()`).
@MainActor
final class ApplicationCatalogStore {
    static let shared = ApplicationCatalogStore()

    private var loadTask: Task<ApplicationCatalog, Never>?

    /// Starts the initial scan without blocking the caller.
    func warm() {
        if loadTask == nil {
            beginLoad()
        }
    }

    /// The most recently scanned catalog, waiting for the initial scan when
    /// it has not finished yet.
    func catalog() async -> ApplicationCatalog {
        if let loadTask {
            return await loadTask.value
        }
        return await beginLoad().value
    }

    /// Rescans and returns the fresh catalog.
    func refresh() async -> ApplicationCatalog {
        await beginLoad().value
    }

    @discardableResult
    private func beginLoad() -> Task<ApplicationCatalog, Never> {
        let task = Task.detached(priority: .utility) {
            ApplicationCatalog.load()
        }
        loadTask = task
        return task
    }
}
