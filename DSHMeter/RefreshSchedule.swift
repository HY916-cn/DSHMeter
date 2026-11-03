import Foundation

/// Shared timing for normal polling, manual refresh, source changes, and retries.
struct RefreshSchedule {
    private(set) var lastAttempt: Date?
    private(set) var retryAt: Date?
    private var failures = 0

    func mayRefresh(at date: Date) -> Bool {
        (lastAttempt.map { date.timeIntervalSince($0) >= 10 } ?? true)
            && (retryAt.map { date >= $0 } ?? true)
    }

    mutating func started(at date: Date) { lastAttempt = date }
    mutating func succeeded() { failures = 0; retryAt = nil }
    mutating func failed(rateLimited: Bool, at date: Date) {
        failures += 1
        let delay = rateLimited ? 300 : [30.0, 60.0, 120.0, 300.0][min(failures - 1, 3)]
        retryAt = date.addingTimeInterval(delay)
    }

    func nextRefresh(popoverVisible: Bool) -> Date {
        let attempted = lastAttempt ?? .distantPast
        let normal = attempted.addingTimeInterval(popoverVisible ? 10 : 60)
        return max(retryAt ?? normal, attempted.addingTimeInterval(10))
    }
}
