import Foundation
import Testing
import SophamtningKit

@Suite struct PlacedOutContentTests {
    private func content(placedOut: Bool = false) -> PickupActivityContent {
        PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: [ActivityFraction(id: "rest", name: "Restavfall", short: "Rest", color: "#111111", icon: "trash")], estimated: false, warning: nil, placedOut: placedOut)
    }

    @Test func standardarFalse() {
        #expect(content().placedOut == false)
    }

    @Test func aldreJsonUtanFaltetGerFalse() throws {
        // Innehåll som en schemalagd aktivitet från en äldre version kan ha sparat.
        let old = """
        {"addressName":"Hemma","dateText":"Måndag 9 november","shortDateText":"Mån 9 nov","fractions":[],"estimated":false}
        """
        let decoded = try JSONDecoder().decode(PickupActivityContent.self, from: Data(old.utf8))
        #expect(decoded.placedOut == false)
        #expect(decoded.addressName == "Hemma")
    }

    @Test func kodningBehallerVardet() throws {
        for value in [true, false] {
            let data = try JSONEncoder().encode(content(placedOut: value))
            let decoded = try JSONDecoder().decode(PickupActivityContent.self, from: data)
            #expect(decoded.placedOut == value)
            #expect(decoded == content(placedOut: value))
        }
    }

    @Test func markeratSomUtstalltAndrarBaraFaltet() {
        let marked = content().markedPlacedOut()
        #expect(marked.placedOut)
        #expect(marked == content(placedOut: true))
        #expect(marked != content())
    }

    // MARK: Hushåll

    private let homeKey = AddressKey(source: "kallor", id: "hem")
    private let monday = DayDate("2026-11-09")!

    private func input() -> PlannerInput {
        let address = SavedAddress(key: homeKey, url: URL(string: "https://example.com/hem")!, street: "Gatan 1", locality: "Orten", kommun: "Kommunen", detail: nil, selection: "address", displayName: "Hemma", isPrimary: true, addedAt: Date(timeIntervalSince1970: 0))
        let response = AddressResponse(
            today: DayDate("2026-11-06")!,
            address: Address(id: "hem", street: "Gatan 1", locality: "Orten", kommun: "Kommunen", source: "kallor", detail: nil, selection: "address", notice: nil),
            next: [], summary: "",
            events: [PickupEvent(date: monday, fractions: ["rest"], estimated: false, deviation: nil, warning: nil, labels: [:])],
            bins: [], fractions: ["rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#111111", icon: "trash")],
            links: Links(ics: URL(string: "https://example.com/a.ics")!, web: URL(string: "https://example.com/a")!),
            updatedAt: DayDate("2026-11-06")!
        )
        let schedule = CachedSchedule(response: response, fetchedAt: Date(timeIntervalSince1970: 0))
        return PlannerInput(addresses: [PlannerAddress(address: address, schedule: schedule)], settings: ReminderSettings(liveActivityOn: true), placedOut: [], now: StockholmClock.date(on: monday, minutes: 7 * 60), liveActivitiesAllowed: true, existingActivities: [], shownActivities: [])
    }

    private func household(markDate: DayDate, by: String = "kim") -> HouseholdState {
        let mark = HouseholdMark(placedOut: PlacedOut(key: homeKey, date: markDate), by: by, at: Date(timeIntervalSince1970: 0), isPending: false)
        return HouseholdState(role: .member, myId: "jag", participants: [], addresses: [], marks: [mark], status: .synced)
    }

    @Test func liveActivityVisarAndrasBock() {
        let content = ReminderPlanner.activityContent(on: monday, input: input(), household: household(markDate: monday))
        #expect(content?.placedOut == true)
    }

    @Test func liveActivityUtanBockEllerMedAnnatDatumVisarInteBocken() {
        #expect(ReminderPlanner.activityContent(on: monday, input: input())?.placedOut == false)
        #expect(ReminderPlanner.activityContent(on: monday, input: input(), household: household(markDate: monday.adding(days: 7)))?.placedOut == false)
    }
}
