import Foundation
import Synchronization

/// Väljer mellan brevlådan och hushållet i iCloud, under tiden som hushållen flyttas.
///
/// Brevlådan gäller när telefonen har ett hushåll där. Annars gäller iCloud, så länge det finns eller kan finnas ett hushåll
/// där. Så länge iCloud inte har svarat räknas ett sparat hushåll aldrig som borta.
public final class RoutingHouseholdSync: HouseholdSync, HouseholdMembership {
    private enum Source { case relay, legacy }

    private struct Inner {
        var relayState: HouseholdState?
        var legacyState: HouseholdState?
        /// Den som gällde senast. Vyerna läser den, så den räknas inte om varje gång.
        var source: Source?
        var lastEmitted: HouseholdState?
        var continuations: [UUID: AsyncStream<HouseholdState>.Continuation] = [:]
        var tasks: [Task<Void, Never>] = []
    }

    private let relay: RelayHouseholdSync
    private let legacy: (any LegacyHousehold)?
    private let migration: HouseholdMigrationStore
    private let store: LocalStore
    private let inner = Mutex(Inner())

    public init(relay: RelayHouseholdSync, legacy: (any LegacyHousehold)?, migration: HouseholdMigrationStore, store: LocalStore) {
        self.relay = relay
        self.legacy = legacy
        self.migration = migration
        self.store = store
        listen(to: relay.states()) { $0.relayState = $1 }
        if let legacy { listen(to: legacy.states()) { $0.legacyState = $1 } }
    }

    deinit {
        for task in inner.withLock({ $0.tasks }) { task.cancel() }
    }

    private func listen(to stream: AsyncStream<HouseholdState>, _ store: @escaping @Sendable (inout Inner, HouseholdState) -> Void) {
        let task = Task { [weak self] in
            for await state in stream {
                guard let self else { return }
                self.inner.withLock { store(&$0, state) }
                self.emit()
            }
        }
        inner.withLock { $0.tasks.append(task) }
    }

    var lastState: HouseholdState? { inner.withLock { $0.lastEmitted } }

    /// Flytten har kommit längre, och det kan vara en annan synk som gäller.
    public func migrationDidChange() { emit() }

    /// Jag har gått med i ett hushåll i iCloud, hos någon med en gammal version. Då gäller iCloud igen.
    public func legacyInvitationAccepted() {
        migration.reset()
        emit()
    }

    // MARK: Valet

    private var source: Source {
        let current = currentSource
        inner.withLock { $0.source = current }
        return current
    }

    private var currentSource: Source {
        guard legacy != nil else { return .relay }
        // Går filen inte att läsa vet appen inte var flytten är. Brevlådan gäller om den har ett hushåll.
        let progress = migration.current ?? HouseholdMigration()
        if progress.inProgress { return .legacy }
        if relay.hasHousehold || progress.moved { return .relay }
        let state = inner.withLock { $0.legacyState }
        if let state, state.role != .none { return .legacy }
        // iCloud har inget hushåll att visa. Var jag med i ett är det iCloud som vet vad som har hänt.
        return savedAsMember ? .legacy : .relay
    }

    /// Om appen senast visade ett hushåll. En fil som inte går att läsa kan vara det.
    private var savedAsMember: Bool {
        switch store.householdState() {
        case .value(let saved): AppModel.isMember(saved)
        case .missing: false
        case .unavailable, .unreadable: true
        }
    }

    private var active: any HouseholdSync {
        if source == .legacy, let legacy { return legacy }
        return relay
    }

    private func emit() {
        let source = source
        inner.withLock { inner in
            guard let state = source == .relay ? inner.relayState : inner.legacyState, state != inner.lastEmitted else { return }
            inner.lastEmitted = state
            for continuation in inner.continuations.values { continuation.yield(state) }
        }
    }

    // MARK: HouseholdSync

    public func states() -> AsyncStream<HouseholdState> {
        let id = UUID()
        return AsyncStream { continuation in
            inner.withLock { inner in
                inner.continuations[id] = continuation
                if let state = inner.lastEmitted { continuation.yield(state) }
            }
            continuation.onTermination = { [weak self] _ in
                self?.inner.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    public func share(_ address: SavedAddress) async throws { try await active.share(address) }
    public func unshare(_ key: AddressKey) async throws { try await active.unshare(key) }
    public func mark(_ placedOut: PlacedOut) async throws { try await active.mark(placedOut) }
    public func unmark(_ placedOut: PlacedOut) async throws { try await active.unmark(placedOut) }
    public func leave() async throws { try await active.leave() }
    public func removeExpired(today: DayDate) async { await active.removeExpired(today: today) }
    public func setMyName(_ name: String) async throws { try await active.setMyName(name) }

    public func fetchChanges() async {
        if source == .legacy { await legacy?.fetchChanges() }
        // Brevlådan hämtas alltid, eftersom nycklarna kan ha kommit från en annan av mina enheter. Utan hushåll görs inget anrop.
        await relay.fetchChanges()
        emit()
    }

    // MARK: HouseholdMembership

    public var managesMembers: Bool { (inner.withLock { $0.source } ?? source) == .relay }

    private func requireRelay() throws -> RelayHouseholdSync {
        guard source == .relay else { throw HouseholdMembershipError.unsupported }
        return relay
    }

    public func create(myName: String) async throws { try await requireRelay().create(myName: myName) }
    public func invite() async throws -> URL { try await requireRelay().invite() }
    public func revokeInvites() async throws { try await requireRelay().revokeInvites() }
    public func remove(participantId: String) async throws { try await requireRelay().remove(participantId: participantId) }
    public func end() async throws { try await requireRelay().end() }
    public func join(_ link: HouseholdInviteLink, myName: String?) async throws { try await requireRelay().join(link, myName: myName) }
    public func registerDevice(token: String, environment: String) async { await relay.registerDevice(token: token, environment: environment) }
    public func isCurrent(_ link: HouseholdInviteLink) -> Bool { source == .relay && relay.isCurrent(link) }

    /// Signalerna gäller bara brevlådan. iCloud har sin egen push.
    public func startSignals() { relay.startSignals() }
    public func stopSignals() { relay.stopSignals() }
}
