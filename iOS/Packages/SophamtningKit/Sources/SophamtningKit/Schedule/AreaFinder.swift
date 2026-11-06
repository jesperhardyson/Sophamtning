import Foundation
import Observation

/// Modellen bakom arket "När tömdes ditt kärl senast?". Kalendern ändrar bara ett utkast. Först
/// `find()` frågar API:t, och ett gammalt svar ersätter aldrig ett nyare.
@MainActor @Observable
public final class AreaFinder {
    public private(set) var state: AreaFinderState = .idle
    /// Datumet som senast frågades efter. `nil` tills användaren tryckt Hitta område, så ingen fråga ställs
    /// och inget område gissas.
    public private(set) var date: DayDate?
    /// Utkastet i kalendern. Börjar på i dag, men ändrar inget och frågar inget.
    public private(set) var draft: DayDate
    /// Falskt efter `400`: samma datum ger samma svar, så det finns inget att försöka igen.
    public private(set) var retryable = true
    /// Sant när en källa inte svarade men träffar ändå visas. Fler områden kan finnas.
    public private(set) var partial = false

    @ObservationIgnored private let api: any SoporAPI
    @ObservationIgnored private let place: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let latest = LatestOnly()
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(api: any SoporAPI, place: String, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.place = place
        self.now = now
        self.draft = StockholmClock.today(now: now())
    }

    /// Senast valbara dag: i dag i Stockholm. Framtida tömningar finns inte.
    public var latestSelectable: DayDate { StockholmClock.today(now: now()) }

    /// Ändrar utkastet. Resultatet för förra datumet tas bort, och inget frågas förrän `find()`.
    public func setDraft(_ day: DayDate) {
        let day = min(day, latestSelectable)
        guard day != draft else { return }
        draft = day
        guard date != nil, date != day else { return }
        task?.cancel()
        task = nil
        date = nil
        state = .idle
        retryable = true
        partial = false
    }

    /// Hitta område: frågar efter utkastets dag. Dagen begränsas till i dag, räknat nu.
    public func find() {
        let day = min(draft, latestSelectable)
        draft = day
        date = day
        load()
    }

    /// Sätter utkastet och frågar direkt.
    public func find(on day: DayDate) {
        setDraft(day)
        find()
    }

    /// Frågar igen med samma datum. Utan valt datum görs ingenting.
    public func retry() { load() }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private struct Outcome: Sendable {
        var state: AreaFinderState
        var retryable = true
        var partial = false
    }

    private func load() {
        guard let day = date else { return }
        task?.cancel()
        state = .searching
        retryable = true
        partial = false
        let api = api, place = place, latest = latest
        task = Task { [weak self] in
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
