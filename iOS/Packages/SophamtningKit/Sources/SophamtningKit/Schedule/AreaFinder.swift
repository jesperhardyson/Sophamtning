import Foundation
import Observation

/// Modellen bakom arket "När tömdes ditt kärl senast?". Ett ändrat datum ger ett nytt anrop efter en kort väntan,
/// och ett gammalt svar ersätter aldrig ett nyare.
@MainActor @Observable
public final class AreaFinder {
    public private(set) var state: AreaFinderState = .idle
    /// Valt datum. `nil` tills användaren valt, så ingen fråga ställs och inget område gissas.
    public private(set) var date: DayDate?
    /// Falskt efter `400`: samma datum ger samma svar, så det finns inget att försöka igen.
    public private(set) var retryable = true
    /// Sant när en källa inte svarade men träffar ändå visas. Fler områden kan finnas.
    public private(set) var partial = false

    @ObservationIgnored private let api: any SoporAPI
    @ObservationIgnored private let place: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let wait: Duration
    @ObservationIgnored private let latest = LatestOnly()
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(api: any SoporAPI, place: String, now: @escaping @Sendable () -> Date = { Date() }, wait: Duration = .milliseconds(400)) {
        self.api = api
        self.place = place
        self.now = now
        self.wait = wait
    }

    /// Senast valbara dag: i dag i Stockholm. Framtida tömningar finns inte.
    public var latestSelectable: DayDate { StockholmClock.today(now: now()) }

    /// Ett nytt datum. Datum efter i dag blir i dag, räknat vid valet.
    public func choose(_ day: DayDate) {
        date = min(day, latestSelectable)
        load(after: wait)
    }

    /// Frågar igen med samma datum. Utan valt datum görs ingenting.
    public func retry() { load(after: .zero) }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private struct Outcome: Sendable {
        var state: AreaFinderState
        var retryable = true
        var partial = false
    }

    private func load(after delay: Duration) {
        guard let day = date else { return }
        task?.cancel()
        state = .searching
        retryable = true
        partial = false
        let api = api, place = place, latest = latest
        task = Task { [weak self] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            let outcome: Outcome?
            do {
                outcome = try await latest.run {
                    let response = try await api.areas(place: place, lastEmptied: day)
                    return Outcome(state: AreaFinderState.from(response),
                                   partial: !response.addresses.isEmpty && !response.failed.isEmpty)
                }
            } catch is CancellationError {
                return
            } catch {
                // Alla tekniska fel är "kunde inte kontrollera", aldrig "ingen hämtning".
                outcome = Outcome(state: .failed, retryable: (error as? APIError) != .badRequest)
            }
            // Nil: ett nyare anrop har startat. Avbruten: datumet ändrades igen.
            guard let outcome, !Task.isCancelled else { return }
            self?.state = outcome.state
            self?.retryable = outcome.retryable
            self?.partial = outcome.partial
        }
    }
}
