import Foundation
import Synchronization

/// Hushållets synk. Appen talar bara med det här gränssnittet, så att CloudKit kan bytas mot något annat i tester.
public protocol HouseholdSync: AnyObject, Sendable {
    /// Senast kända läget, och sedan varje ändring, lokal som från andra.
    func states() -> AsyncStream<HouseholdState>
    func share(_ address: SavedAddress) async throws
    func unshare(_ key: AddressKey) async throws
    func mark(_ placedOut: PlacedOut) async throws
    func unmark(_ placedOut: PlacedOut) async throws
    func leave() async throws
    func removeExpired(today: DayDate) async
    /// Hämtar ändringar nu, vid start, när appen blir aktiv och i bakgrundsuppdateringen.
    func fetchChanges() async
}

/// Hushållet är avstängt: läget är alltid tomt och inget görs.
public final class DisabledHousehold: HouseholdSync {
    public init() {}

    public func states() -> AsyncStream<HouseholdState> {
        AsyncStream { continuation in
            continuation.yield(.empty)
            continuation.finish()
        }
    }

    public func share(_ address: SavedAddress) async throws {}
    public func unshare(_ key: AddressKey) async throws {}
    public func mark(_ placedOut: PlacedOut) async throws {}
    public func unmark(_ placedOut: PlacedOut) async throws {}
    public func leave() async throws {}
    public func removeExpired(today: DayDate) async {}
    public func fetchChanges() async {}
}

/// Hushållet i minnet, för tester och UI-tester.
public final class InMemoryHouseholdSync: HouseholdSync {
    private struct Inner {
        var state: HouseholdState
        var continuations: [UUID: AsyncStream<HouseholdState>.Continuation] = [:]
    }

    private let inner: Mutex<Inner>
    private let now: @Sendable () -> Date
    /// Falskt: ett oförändrat läge skickas inte igen, som i CloudKit-synken. Sant: varje ändring och hämtning ger ett läge.
    private let resendsUnchanged: Bool

    public init(state: HouseholdState, now: @escaping @Sendable () -> Date = { Date() }, resendsUnchanged: Bool = true) {
        inner = Mutex(Inner(state: state))
        self.now = now
        self.resendsUnchanged = resendsUnchanged
    }

    public func states() -> AsyncStream<HouseholdState> {
        let id = UUID()
        return AsyncStream { continuation in
            inner.withLock { inner in
                inner.continuations[id] = continuation
                continuation.yield(inner.state)
            }
            continuation.onTermination = { [weak self] _ in
                self?.inner.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    /// Låter tester och UI-tester låtsas att en annan deltagare ändrat något.
    public func simulateRemote(_ change: (inout HouseholdState) -> Void) {
        update(change)
    }

    public func share(_ address: SavedAddress) async throws {
        update { state in
            guard !state.addresses.contains(where: { $0.address.key == address.key }) else { return }
            state.addresses.append(HouseholdAddress(address: address, addedBy: state.myId ?? ""))
        }
    }

    public func unshare(_ key: AddressKey) async throws {
        update { $0.addresses.removeAll { $0.address.key == key } }
    }

    /// Finns redan en bock för samma hämtning behålls den med sin avsändare och sin tid: den första vinner.
    public func mark(_ placedOut: PlacedOut) async throws {
        let moment = now()
        update { state in
            guard !state.marks.contains(where: { $0.placedOut == placedOut }) else { return }
            state.marks.append(HouseholdMark(placedOut: placedOut, by: state.myId ?? "", at: moment, isPending: false))
        }
    }

    public func unmark(_ placedOut: PlacedOut) async throws {
        update { $0.marks.removeAll { $0.placedOut == placedOut } }
    }

    public func leave() async throws {
        update { $0 = .empty }
    }

    public func removeExpired(today: DayDate) async {
        update { state in
            let expired = Set(HouseholdLogic.expired(state.marks, today: today).map(\.placedOut))
            state.marks.removeAll { expired.contains($0.placedOut) }
        }
    }

    /// Inget att hämta i minnet, men prenumeranterna får läget igen, om inte `resendsUnchanged` är falskt.
    public func fetchChanges() async {
        update { _ in }
    }

    private func update(_ change: (inout HouseholdState) -> Void) {
        inner.withLock { inner in
            let before = inner.state
            change(&inner.state)
            guard resendsUnchanged || inner.state != before else { return }
            for continuation in inner.continuations.values {
                continuation.yield(inner.state)
            }
        }
    }
}
