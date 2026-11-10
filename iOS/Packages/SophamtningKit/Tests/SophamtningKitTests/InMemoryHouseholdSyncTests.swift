import Foundation
import Testing
@testable import SophamtningKit

@Suite struct InMemoryHouseholdSyncTests {
    let key = AddressKey(source: "avesta", id: "trakt-7")
    let address: SavedAddress

    init() {
        address = SavedAddress(key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/avesta/trakt-7")!, street: "Område 7", locality: "", kommun: "Avesta kommun", detail: nil, selection: "area", displayName: "Område 7", isPrimary: true, addedAt: Date(timeIntervalSince1970: 0))
    }

    private func start(_ sync: some HouseholdSync) async -> HouseholdState {
        var iterator = sync.states().makeAsyncIterator()
        return await iterator.next() ?? .empty
    }

    private func state(marks: [HouseholdMark] = []) -> HouseholdState {
        HouseholdState(role: .member, myId: "jag", participants: [], addresses: [], marks: marks, status: .synced)
    }

    @Test func forstaBockenVinner() async throws {
        let placedOut = PlacedOut(key: key, date: DayDate("2026-11-10")!)
        let sync = InMemoryHouseholdSync(state: state())
        sync.simulateRemote {
            $0.marks.append(HouseholdMark(placedOut: placedOut, by: "kim", at: Date(timeIntervalSince1970: 5), isPending: false))
        }
        try await sync.mark(placedOut)
        let result = await start(sync)
        #expect(result.marks.count == 1)
        #expect(result.marks.first?.by == "kim")
    }

    @Test func markSatterMigSomAvsandare() async throws {
        let placedOut = PlacedOut(key: key, date: DayDate("2026-11-10")!)
        let moment = Date(timeIntervalSince1970: 100)
        let sync = InMemoryHouseholdSync(state: state(), now: { moment })
        try await sync.mark(placedOut)
        let result = await start(sync)
        #expect(result.marks == [HouseholdMark(placedOut: placedOut, by: "jag", at: moment, isPending: false)])
        try await sync.unmark(placedOut)
        #expect(await start(sync).marks.isEmpty)
    }

    @Test func unshareTarBortAdressen() async throws {
        let sync = InMemoryHouseholdSync(state: state())
        try await sync.share(address)
        try await sync.share(address)
        #expect(await start(sync).addresses == [HouseholdAddress(address: address, addedBy: "jag")])
        try await sync.unshare(key)
        #expect(await start(sync).addresses.isEmpty)
    }

    @Test func leaveGerTomtHushall() async throws {
        let sync = InMemoryHouseholdSync(state: state())
        try await sync.leave()
        #expect(await start(sync).role == .none)
    }

    @Test func removeExpiredTarBortGamla() async {
        let old = HouseholdMark(placedOut: PlacedOut(key: key, date: DayDate("2026-11-09")!), by: "kim", at: Date(timeIntervalSince1970: 0), isPending: false)
        let current = HouseholdMark(placedOut: PlacedOut(key: key, date: DayDate("2026-11-10")!), by: "kim", at: Date(timeIntervalSince1970: 0), isPending: false)
        let sync = InMemoryHouseholdSync(state: state(marks: [old, current]))
        await sync.removeExpired(today: DayDate("2026-11-10")!)
        #expect(await start(sync).marks == [current])
    }

    @Test func fleraPrenumeranterFarVarjeÄndring() async throws {
        let sync = InMemoryHouseholdSync(state: state())
        var a = sync.states().makeAsyncIterator()
        var b = sync.states().makeAsyncIterator()
        _ = await a.next()
        _ = await b.next()
        sync.simulateRemote { $0.role = .owner }
        #expect(await a.next()?.role == .owner)
        #expect(await b.next()?.role == .owner)
    }

    @Test func avstangtHushallGerBaraTomtLage() async throws {
        let sync = DisabledHousehold()
        try await sync.share(address)
        try await sync.mark(PlacedOut(key: key, date: DayDate("2026-11-10")!))
        await sync.fetchChanges()
        #expect(await start(sync) == .empty)
    }
}
