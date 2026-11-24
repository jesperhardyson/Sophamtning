import Foundation

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

    private static let lifetime: TimeInterval = 90 * 86_400
    /// En vanlig inbjudan gäller i sju dagar och förnyas när den har två kvar.
    private static let renewal: TimeInterval = 2 * 86_400

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
        guard let snapshot = await legacy.legacySnapshot() else { return }
        if relay.hasHousehold, !state.inProgress {
            // Nycklarna kom från en annan av mina enheter, som redan har flyttat.
            state.moved = true
            save(state)
            return
        }
        if !state.inProgress, let url = await legacy.migrationLink() {
            await follow(url, snapshot: snapshot, state: &state)
        } else if snapshot.role == .owner, await isEnabled() {
            await move(snapshot, state: &state)
        }
    }

    /// Servern avgör när flytten får börja. Inget svar är nej.
    private func isEnabled() async -> Bool {
        guard let response = try? await transport.send(RelayRequest(method: "GET", path: "/config")), response.status == 200 else { return false }
        return (try? JSONDecoder().decode(ConfigWire.self, from: response.body))?.migration == true
    }

    // MARK: Ägaren

    private func move(_ snapshot: HouseholdState, state: inout HouseholdMigration) async {
        guard let myId = legacy.legacyMyId else { return }
        do {
            let name = snapshot.myName ?? ""
            if !state.inProgress {
                // Sparas före hushållet, så att ett avbrott aldrig gör att det halva hushållet börjar gälla.
                state.startedAt = now()
                try migration.save(state)
            }
            if !relay.hasHousehold { try await relay.create(myName: name, legacyId: myId) }
            try await relay.setMyName(name, legacyId: myId)
            try await upload(snapshot)
            if state.link == nil { try await makeLink(&state) }
            guard let link = state.link else { return }
            if !state.linkWritten {
                try await legacy.writeMigrationLink(link)
                state.linkWritten = true
                try migration.save(state)
            }
            // Det som hann ändras i iCloud under tiden.
            if let latest = await legacy.legacySnapshot() { try await upload(latest) }
            await relay.fetchChanges()
            state.moved = true
            try migration.save(state)
            onChange()
        } catch {
            // Görs om nästa gång.
            onChange()
        }
    }

    /// Alla adresser, och alla bockar som inte är förbrukade, också de som andra har skrivit.
    private func upload(_ snapshot: HouseholdState) async throws {
        let today = StockholmClock.today(now: now())
        for item in snapshot.addresses {
            try await relay.upload(address: item.address, legacyBy: item.addedBy, at: item.address.addedAt)
        }
        for mark in snapshot.marks where mark.placedOut.date >= today {
            try await relay.upload(mark: mark.placedOut, legacyBy: mark.by, at: mark.at)
        }
    }

    private func makeLink(_ state: inout HouseholdMigration) async throws {
        do {
            state.link = try await relay.inviteLink(purpose: "migration").url
            state.linkExpiresAt = now().addingTimeInterval(Self.lifetime)
        } catch HouseholdMembershipError.migrationUnavailable {
            // Svaret på en tidigare inbjudan gick förlorat. En vanlig inbjudan fungerar lika bra, men förnyas oftare.
            state.link = try await relay.inviteLink(purpose: "invite").url
            state.linkExpiresAt = now().addingTimeInterval(7 * 86_400)
        }
        try migration.save(state)
    }

    /// Efter flytten: håller länken giltig, och tar bort delningen efter 90 dagar eller när hushållet har avslutats.
    private func cleanUp(_ state: inout HouseholdMigration) async {
        guard state.linkWritten, !state.shareRemoved, let startedAt = state.startedAt else { return }
        let end = startedAt.addingTimeInterval(Self.lifetime)
        if now() >= end || !relay.hasHousehold {
            guard (try? await legacy.removeShare()) != nil else { return }
            state.shareRemoved = true
            save(state)
        } else if let expires = state.linkExpiresAt, expires < end, expires.timeIntervalSince(now()) < Self.renewal {
            guard let link = try? await relay.inviteLink(purpose: "invite").url, (try? await legacy.writeMigrationLink(link)) != nil else { return }
            state.link = link
            state.linkExpiresAt = now().addingTimeInterval(7 * 86_400)
            save(state)
        }
    }

    // MARK: Medlemmen

    /// Går med via länken i zonen, utan fråga, eftersom det är samma hushåll. Ägaren har redan laddat upp innehållet.
    private func follow(_ url: URL, snapshot: HouseholdState, state: inout HouseholdMigration) async {
        guard let link = HouseholdInviteLink(url: url), let myId = legacy.legacyMyId else { return }
        guard (try? await relay.join(link, myName: snapshot.myName ?? "", legacyId: myId)) != nil else { return }
        state.moved = true
        save(state)
    }

    private func save(_ state: HouseholdMigration) {
        try? migration.save(state)
        onChange()
    }
}
