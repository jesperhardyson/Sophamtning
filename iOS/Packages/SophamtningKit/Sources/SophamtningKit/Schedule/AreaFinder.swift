import Foundation
import Observation

/// Modellen bakom arket "När tömdes ditt kärl senast?". Ett ändrat datum ger ett nytt anrop efter en kort väntan,
/// och ett gammalt svar ersätter aldrig ett nyare.
@MainActor @Observable
public final class AreaFinder {
    public private(set) var state: AreaFinderState = .idle
    public private(set) var date: DayDate

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
        self.date = StockholmClock.today(now: now())
    }

    /// Senast valbara dag: i dag i Stockholm. Framtida tömningar finns inte.
    public var latestSelectable: DayDate { StockholmClock.today(now: now()) }

    /// Hämtar för standarddatumet (i dag), utan väntan.
    public func start() { load(after: .zero) }

    /// Ett nytt datum. Datum efter i dag blir i dag.
    public func choose(_ day: DayDate) {
        date = min(day, latestSelectable)
        load(after: wait)
    }

    public func retry() { load(after: .zero) }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private func load(after delay: Duration) {
        task?.cancel()
        state = .searching
        let day = date, api = api, place = place, latest = latest
        task = Task { [weak self] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            let outcome: AreaFinderState?
            do {
                outcome = try await latest.run {
                    AreaFinderState.from(try await api.areas(place: place, lastEmptied: day))
                }
            } catch is CancellationError {
                return
            } catch {
                // Alla tekniska fel är "kunde inte kontrollera", aldrig "ingen hämtning".
                outcome = .failed
            }
            // Nil: ett nyare anrop har startat. Avbruten: datumet ändrades igen.
            guard let outcome, !Task.isCancelled else { return }
            self?.state = outcome
        }
    }
}
