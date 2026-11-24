import Foundation
import Synchronization

/// Flyttar ett hushåll från iCloud till brevlådan. Se Flytten från CloudKit i
/// `docs/specs/2026-11-23-hushall-mellan-plattformar.md`.
///
/// Varje steg går att göra om: postnamnen är desamma, så det som redan laddats upp hoppas över. Tills länken ligger i zonen
/// gäller hushållet i iCloud, så att ingen ser ett halvt hushåll.
public final class HouseholdMigrator: Sendable {
    private let relay: RelayHouseholdSync
    private let legacy: any LegacyHousehold
    private let transport: any RelayTransport
    private let migration: HouseholdMigrationStore
    private let now: @Sendable () -> Date
    private let onChange: @Sendable () -> Void
    private let serial = RelaySerial()

    /// Länken i minnet, mellan att inbjudan skapas och att den har skrivits i zonen.
    private let link = Mutex<URL?>(nil)

    private static let lifetime: TimeInterval = 90 * 86_400
    private static let ordinaryLifetime: TimeInterval = 7 * 86_400
    /// En vanlig inbjudan förnyas när den har två dygn kvar.
    private static let renewal: TimeInterval = 2 * 86_400
    /// Så länge väntar ägarens andra enhet på att iCloud-nyckelringen ska ge den nycklarna.
    private static let keychainWait: TimeInterval = 86_400

    public init(
        relay: RelayHouseholdSync,
        legacy: any LegacyHousehold,
        transport: any RelayTransport,
        migration: HouseholdMigrationStore,
        now: @escaping @Sendable () -> Date = { Date() },
        onChange: @escaping @Sendable () -> Void = {}
    ) {
        self.relay = relay
        self.legacy = legacy
        self.transport = transport
        self.migration = migration
        self.now = now
        self.onChange = onChange
    }

    /// Gör det som är dags att göra. Anropas vid start och när appen blir aktiv.
    public func run() async {
        await serial.run { await self.step() }
    }

    private func step() async {
        guard var state = migration.current else { return }
        if state.moved {
            await cleanUp(&state)
            return
        }
        if state.inProgress, legacy.isReliablyEmpty {
            await abandon()
            return
        }
        guard let snapshot = await legacy.legacySnapshot() else { return }
        if state.inProgress, snapshot.role != .owner {
            await abandon()
            return
        }
        let written = await legacy.migrationLink().flatMap { HouseholdInviteLink(url: $0) }
        if let written, relay.hasHousehold, written.householdId == relay.householdId {
            // Länken ligger i zonen: antingen hann flytten så långt innan den avbröts, eller så kom nycklarna från en annan
            // av mina enheter, som redan har flyttat.
            state.linkWritten = state.linkWritten || state.inProgress
            state.moved = true
            save(state)
        } else if state.inProgress {
            if await isEnabled() { await move(snapshot, state: &state) }
        } else if relay.hasHousehold {
            // Ett annat hushåll i brevlådan. Det i iCloud är inte flyttat.
            return
        } else if let written {
            await follow(written, snapshot: snapshot, state: &state)
        } else if snapshot.role == .owner, await isEnabled() {
            await move(snapshot, state: &state)
        }
    }

    /// Hushållet i iCloud försvann innan flytten var klar. Det halva hushållet i brevlådan avslutas, så att det inte är i vägen.
    private func abandon() async {
        if relay.hasHousehold { guard (try? await relay.leave()) != nil else { return } }
        link.withLock { $0 = nil }
        migration.reset()
        onChange()
    }

    /// Servern avgör när flytten får börja. Inget svar är nej.
    private func isEnabled() async -> Bool {
        guard let response = try? await transport.send(RelayRequest(method: "GET", path: "/config")), response.status == 200 else { return false }
        return (try? JSONDecoder().decode(ConfigWire.self, from: response.body))?.migration == true
    }

    // MARK: Ägaren

    private func move(_ snapshot: HouseholdState, state: inout HouseholdMigration) async {
        guard let myId = legacy.legacyMyId else { return }
        let name = snapshot.myName ?? ""
        do {
            if !state.inProgress {
                // Sparas före hushållet, så att ett avbrott aldrig gör att det halva hushållet börjar gälla.
                state.startedAt = now()
                try migration.save(state)
            }
            if !relay.hasHousehold { try await relay.create(myName: name, legacyId: myId) }
            try await relay.setMyName(name, legacyId: myId)
            try await upload(snapshot)
            // Det som har ångrats i iCloud sedan ett tidigare försök ska inte komma tillbaka.
            try await relay.removeRecords(notIn: current(snapshot))
            if link.withLock({ $0 }) == nil { try await makeLink(&state) }
            guard let url = link.withLock({ $0 }) else { return }
            try await legacy.writeMigrationLink(url)
            link.withLock { $0 = nil }
            state.linkWritten = true
            state.moved = true
            try migration.save(state)
            onChange()
        } catch {
            // Görs om nästa gång. Till dess gäller iCloud.
            onChange()
            return
        }
        // Det som hann ändras i iCloud under tiden. Nu kan andra ha gått med, så bara skillnaden skickas.
        guard let latest = await legacy.legacySnapshot() else { return }
        try? await upload(latest)
        try? await relay.removeRecords(notIn: current(latest), among: current(snapshot))
        await relay.fetchChanges()
    }

    /// Hushållet utan det som är förbrukat.
    private func current(_ snapshot: HouseholdState) -> HouseholdState {
        let today = StockholmClock.today(now: now())
        var current = snapshot
        current.marks.removeAll { $0.placedOut.date < today }
        return current
    }

    /// Alla adresser, och alla bockar som inte är förbrukade, också de som andra har skrivit.
    private func upload(_ snapshot: HouseholdState) async throws {
        let snapshot = current(snapshot)
        for item in snapshot.addresses {
            try await relay.upload(address: item.address, legacyBy: item.addedBy, at: item.address.addedAt)
        }
        for mark in snapshot.marks {
            try await relay.upload(mark: mark.placedOut, legacyBy: mark.by, at: mark.at)
        }
    }

    private func makeLink(_ state: inout HouseholdMigration) async throws {
        do {
            let url = try await relay.inviteLink(purpose: "migration").url
            link.withLock { $0 = url }
            state.linkExpiresAt = now().addingTimeInterval(Self.lifetime)
        } catch HouseholdMembershipError.migrationUnavailable {
            // Inbjudan för flytten är redan skapad. En vanlig inbjudan fungerar lika bra, men förnyas oftare.
            let url = try await relay.inviteLink(purpose: "invite").url
            link.withLock { $0 = url }
            state.linkExpiresAt = now().addingTimeInterval(Self.ordinaryLifetime)
        }
        try migration.save(state)
    }

    /// Efter flytten: håller länken giltig, och tar bort delningen efter 90 dagar eller när hushållet har avslutats.
    private func cleanUp(_ state: inout HouseholdMigration) async {
        await Self.renewLink(relay: relay, legacy: legacy, migration: migration, now: now())
        guard let current = migration.current else { return }
        state = current
        guard state.linkWritten, !state.shareRemoved, let startedAt = state.startedAt else { return }
        let end = startedAt.addingTimeInterval(Self.lifetime)
        if now() >= end || state.ended {
            guard (try? await legacy.removeShare()) != nil else { return }
            state.shareRemoved = true
            save(state)
        } else if let expires = state.linkExpiresAt, expires < end, expires.timeIntervalSince(now()) < Self.renewal {
            migration.update { $0.linkNeedsRenewal = true }
            await Self.renewLink(relay: relay, legacy: legacy, migration: migration, now: now())
        }
    }

    /// Gör om länken i zonen när någon har tagits bort eller när den snart går ut, så att de som inte har flyttat än fortfarande
    /// kan gå med, men inte den som togs bort.
    static func renewLink(relay: RelayHouseholdSync, legacy: any LegacyHousehold, migration: HouseholdMigrationStore, now: Date) async {
        guard let state = migration.current, state.moved, state.linkNeedsRenewal, !state.shareRemoved, !state.ended,
              await legacy.legacySnapshot()?.role == .owner else { return }
        do {
            if !state.removedLegacyIds.isEmpty { try await legacy.removeParticipants(state.removedLegacyIds) }
            try await legacy.writeMigrationLink(try await relay.inviteLink(purpose: "invite").url)
        } catch {
            return
        }
        migration.update {
            $0.linkNeedsRenewal = false
            $0.removedLegacyIds.removeAll { state.removedLegacyIds.contains($0) }
            $0.linkExpiresAt = now.addingTimeInterval(ordinaryLifetime)
        }
    }

    // MARK: Medlemmen

    /// Går med via länken i zonen, utan fråga, eftersom det är samma hushåll. Ägaren har redan laddat upp innehållet.
    ///
    /// Ägarens andra enheter är samma ägare och får nycklarna med iCloud-nyckelringen. Kommer de inte på ett dygn går enheten
    /// med som en egen deltagare, med nycklar som stannar på den, så att ägarens aldrig skrivs över.
    private func follow(_ link: HouseholdInviteLink, snapshot: HouseholdState, state: inout HouseholdMigration) async {
        guard let myId = legacy.legacyMyId else { return }
        let isOwner = snapshot.role == .owner
        if isOwner {
            guard let seen = state.linkSeenAt else {
                state.linkSeenAt = now()
                save(state)
                return
            }
            guard now().timeIntervalSince(seen) >= Self.keychainWait else { return }
        }
        guard (try? await relay.join(link, myName: snapshot.myName ?? "", legacyId: myId, locally: isOwner)) != nil else { return }
        state.moved = true
        save(state)
    }

    private func save(_ state: HouseholdMigration) {
        try? migration.save(state)
        onChange()
    }
}
