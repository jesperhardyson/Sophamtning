import Foundation

public enum RefreshOutcome: Equatable, Sendable {
    /// Nytt svar hämtat och sparat.
    case fetched
    /// Ingen hämtning gjordes: för tidigt enligt `RefreshPolicy`, eller anropet avbröts.
    case skipped
    /// API-anropet misslyckades. Försöket är sparat, och det tidigare svaret är kvar.
    case failed(APIError)
    /// Svaret hämtades men gick inte att spara.
    case storageFailed
}

/// Samtidiga anrop för samma adress hanteras inte här. `AppModel` serialiserar dem (uppgift 10).
public final class ScheduleRefresher: Sendable {
    private let api: any SoporAPI
    private let store: LocalStore

    public init(api: any SoporAPI, store: LocalStore) {
        self.api = api
        self.store = store
    }

    public func refresh(_ address: SavedAddress, now: Date, manual: Bool) async -> RefreshOutcome {
        let existing = store.schedule(for: address.key)
        guard RefreshPolicy.canFetch(schedule: existing, now: now, manual: manual) else { return .skipped }

        let failure: APIError
        do {
            let response = try await api.address(url: address.url)
            let schedule = CachedSchedule(response: response, fetchedAt: now, lastAttemptAt: now, lastError: nil)
            do {
                try store.setSchedule(schedule, for: address.key)
                return .fetched
            } catch {
                return .storageFailed
            }
        } catch is CancellationError {
            // Ett avbrutet anrop är inget misslyckat försök.
            return .skipped
        } catch let apiError as APIError {
            failure = apiError
        } catch {
            // Klienten kastar bara APIError och CancellationError. Något annat är oväntat och har ingen statuskod.
            failure = .unexpected(0)
        }

        // Sparat svar och `fetchedAt` lämnas orörda. Bara försöket noteras.
        var schedule = existing ?? CachedSchedule()
        schedule.lastAttemptAt = now
        schedule.lastError = failure
        do {
            try store.setSchedule(schedule, for: address.key)
        } catch {
            return .storageFailed
        }
        return .failed(failure)
    }
}
