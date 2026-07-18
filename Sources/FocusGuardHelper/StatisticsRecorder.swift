import FocusGuardCore
import Foundation

/// Accumulates enforcement counters from the landing-page queue and the main
/// kill loop, and persists them at most once per flush call. Counts survive
/// helper restarts because the existing stats file seeds the initial state.
final class StatisticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let store: BlockStatisticsStore
    private var statistics: BlockStatistics
    private var dirty = false

    init(store: BlockStatisticsStore) {
        self.store = store
        let now = Date()
        statistics = (try? store.load()) ?? BlockStatistics(since: now, updatedAt: now)
    }

    func recordWebsiteHit(domain: String) {
        lock.lock()
        statistics.websiteHits[domain, default: 0] += 1
        dirty = true
        lock.unlock()
    }

    func recordApplicationTermination(displayName: String) {
        lock.lock()
        statistics.applicationTerminations[displayName, default: 0] += 1
        dirty = true
        lock.unlock()
    }

    func flushIfDirty() throws {
        lock.lock()
        guard dirty else {
            lock.unlock()
            return
        }
        statistics.updatedAt = Date()
        let snapshot = statistics
        dirty = false
        lock.unlock()

        try store.save(snapshot)
    }
}
