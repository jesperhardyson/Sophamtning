import Foundation

/// Reglerna för när ett schema får hämtas.
public enum RefreshPolicy {
    /// Högst en hämtning i timmen per adress.
    static let interval: TimeInterval = 3600
    /// Efter ett misslyckat försök får användaren försöka igen efter en minut.
    static let manualRetryInterval: TimeInterval = 60

    /// Efter ett misslyckat försök räknas tiden från försöket, annars från senaste lyckade hämtning.
    /// Utan tidigare försök är hämtning tillåten.
    public static func canFetch(schedule: CachedSchedule?, now: Date, manual: Bool) -> Bool {
        guard let schedule else { return true }
        let reference: Date?
        let required: TimeInterval
        if schedule.lastError != nil, let attempt = schedule.lastAttemptAt {
            reference = attempt
            required = manual ? manualRetryInterval : interval
        } else {
            reference = schedule.fetchedAt
            required = interval
        }
        guard let reference else { return true }
        return now.timeIntervalSince(reference) >= required
    }
}
