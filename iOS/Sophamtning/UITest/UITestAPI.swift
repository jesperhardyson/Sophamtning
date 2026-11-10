#if DEBUG
import Foundation
import SophamtningKit

/// Stubben som UI-testerna startar appen med (`-uitest` eller `-uitest-intrade`). Den svarar med kopior av testdata ur `UITestData/`
/// och gör aldrig något nätanrop. Filerna och den här koden ingår bara i Debug-bygget.
struct UITestAPI: SoporAPI {
    /// Dagen då testdatat skrevs. Alla datum flyttas så att schemat alltid ligger framåt från i dag.
    private static let recordedDay = DayDate("2026-11-06")!

    func search(query: String, source: String?) async throws -> SearchResponse {
        // Bara "testgatan" ger träffar. Allt annat ger inga träffar och inga fel.
        if query.lowercased().contains("testgatan") { return try Self.load("uitest-sok") }
        return SearchResponse(addresses: [], failed: [])
    }

    func areas(place: String) async throws -> SearchResponse {
        // Områdesval finns bara i Avesta.
        if place.lowercased() == "avesta" { return try Self.load("uitest-omraden") }
        return SearchResponse(addresses: [], failed: [])
    }

    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse {
        try await areas(place: place)
    }

    func address(url: URL) async throws -> AddressResponse {
        // Avesta har ett schema som gäller till ett visst datum. Testgatan är en live-källa utan sådant.
        if url.path.contains("/adress/avesta/") {
            let response: AddressResponse = try Self.load("uitest-adress-avesta")
            return UITestSupport.endsSoon ? Self.endingSoon(response) : response
        }
        // Testgatan 4 har ett schema utan kommande hämtningar.
        if url.path.contains("/testgatan-4_") { return try Self.load("uitest-adress-tom") }
        return try Self.load("uitest-adress")
    }

    func sources() async throws -> SourcesResponse {
        let all: SourcesResponse = try Self.load("uitest-kallor")
        return SourcesResponse(sources: all.sources.filter { !$0.testData }, fractions: all.fractions)
    }

    /// Samma schema, men med sista dagen 10 dagar fram, så att rutan och raden om att schemat slutar syns.
    private static func endingSoon(_ response: AddressResponse) -> AddressResponse {
        let until = StockholmClock.today(now: Date()).adding(days: 10)
        return AddressResponse(
            today: response.today, address: response.address, next: response.next, summary: response.summary,
            events: response.events, bins: response.bins, fractions: response.fractions, links: response.links,
            updatedAt: response.updatedAt, schedule: SchedulePeriod(until: until, reason: response.schedule?.reason)
        )
    }

    /// Testgatans första tömning i testdatat, flyttad som alla datum. Med hushåll är det i morgon.
    static func testgatanFirstPickup() -> DayDate {
        DayDate("2026-11-11")!.adding(days: recordedDay.days(until: StockholmClock.today(now: Date())) + UITestSupport.extraDays)
    }

    /// Sökträffen för Testgatan 1, så att hushållets delade adress byggs som när adressen sparas från sökningen.
    static func testgatanHit() -> SearchHit? {
        let response: SearchResponse? = try? load("uitest-sok")
        return response?.addresses.first { $0.street == "Testgatan 1" }
    }

    private static func load<Response: Decodable>(_ name: String) throws -> Response {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { throw APIError.unexpected(0) }
        let shift = recordedDay.days(until: StockholmClock.today(now: Date())) + UITestSupport.extraDays
        let shifted = try JSONSerialization.data(withJSONObject: shiftDates(json, by: shift))
        return try JSONDecoder().decode(Response.self, from: shifted)
    }

    private static func shiftDates(_ value: Any, by days: Int) -> Any {
        switch value {
        case let text as String:
            return DayDate(text).map { $0.adding(days: days).iso } ?? text
        case let list as [Any]:
            return list.map { shiftDates($0, by: days) }
        case let object as [String: Any]:
            return object.mapValues { shiftDates($0, by: days) }
        default:
            return value
        }
    }
}

enum UITestSupport {
    /// Som `-uitest`, men inträdet körs och lagringen från förra starten ligger kvar. Paketet känner inte till argumentet,
    /// så i ett Release-bygge gör det ingenting.
    private static let entranceArgument = "-uitest-intrade"

    private static var runsEntrance: Bool { ProcessInfo.processInfo.arguments.contains(entranceArgument) }

    /// `-uitest-schemat-slutar`: Avestas schema gäller bara 10 dagar till.
    static var endsSoon: Bool { ProcessInfo.processInfo.arguments.contains("-uitest-schemat-slutar") }

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-uitest") || runsEntrance }

    // MARK: Notiser

    /// `-uitest-notiser`: iOS tillåter notiser, och de läggs in i minnet. `-uitest-notiser-nekade`: iOS nekar dem. Utan
    /// argumenten finns inga notiser, som förut.
    static func notifications() -> any NotificationScheduling {
        if has("-uitest-notiser-nekade") { return UITestNotifications(authorization: .denied) }
        if has("-uitest-notiser") { return UITestNotifications(authorization: .authorized) }
        return DisabledNotifications()
    }

    // MARK: Hushåll

    /// `-uitest-hushall`: jag är medlem, Kim är ägare och Testgatan 1 delas. `-uitest-hushall-agare` gör mig till ägare, och
    /// `-uitest-hushall-synkar-inte` ger läget "Synkar inte just nu" strax efter starten, och `-uitest-hushall-vantar` ger min
    /// bock för testgatans nästa tömning som ännu inte har skickats, med klockan. `-uitest-hushall-tomt` ger en synk
    /// utan hushåll. `-uitest-hushall-ny-deltagare` låter Sofie gå med strax efter starten.
    private static func has(_ argument: String) -> Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    private static var withHousehold: Bool { has("-uitest-hushall") }

    /// Med hushåll flyttas schemat så att nästa tömning är i morgon, och knappen Ställ ut kärlen visas.
    static var extraDays: Int { withHousehold ? -4 : 0 }

    /// Hushållets synk i minnet, eller ett avstängt hushåll utan något av argumenten.
    static func household() -> any HouseholdSync {
        if has("-uitest-hushall-tomt") { return InMemoryHouseholdSync(state: .empty) }
        guard withHousehold, let hit = UITestAPI.testgatanHit() else { return DisabledHousehold() }
        let owner = has("-uitest-hushall-agare")
        let address = SavedAddress(
            key: AddressKey(source: hit.source, id: hit.id),
            url: hit.url,
            street: hit.street,
            locality: hit.locality,
            kommun: hit.kommun,
            detail: hit.detail,
            selection: hit.selection,
            displayName: "Hemma",
            isPrimary: true,
            addedAt: Date()
        )
        let state = HouseholdState(
            role: owner ? .owner : .member,
            myId: "jag",
            participants: [
                HouseholdParticipant(id: "kim", name: "Kim", isOwner: !owner),
                HouseholdParticipant(id: "jag", name: "Alex", isOwner: owner),
            ],
            addresses: [HouseholdAddress(address: address, addedBy: "kim")],
            marks: has("-uitest-hushall-vantar")
                ? [HouseholdMark(placedOut: PlacedOut(key: address.key, date: UITestAPI.testgatanFirstPickup()), by: "jag", at: Date(), isPending: true)]
                : [],
            status: .synced
        )
        let sync = InMemoryHouseholdSync(state: state)
        if has("-uitest-hushall-ny-deltagare") {
            Task {
                try? await Task.sleep(for: .seconds(2))
                sync.simulateRemote { $0.participants.append(HouseholdParticipant(id: "sofie", name: "Sofie", isOwner: false)) }
            }
        }
        if has("-uitest-hushall-synkar-inte") {
            // Först ett synkat läge, så att adressen finns, och sedan iCloud utloggat.
            Task {
                try? await Task.sleep(for: .seconds(2))
                sync.simulateRemote { $0.status = .notSignedIn }
            }
        }
        return sync
    }

    /// En lagring i en egen katalog, där inget delas med riktig data. Varje testkörning börjar från noll, utom med
    /// `-uitest-intrade`, som startar om appen med det som förra starten sparade.
    static func store() -> LocalStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-store", isDirectory: true)
        if !runsEntrance { try? FileManager.default.removeItem(at: directory) }
        return LocalStore(directory: directory)
    }
}
/// Notiser i minnet för UI-testerna, med ett fast svar om tillstånd.
actor UITestNotifications: NotificationScheduling {
    private let state: NotificationAuthorization
    private var planned: [PendingNotification] = []

    init(authorization: NotificationAuthorization) {
        state = authorization
    }

    func authorization() async -> NotificationAuthorization { state }
    func requestAuthorization() async -> Bool { state == .authorized }
    func pending() async -> [PendingNotification] { planned }

    func schedule(_ notifications: [PlannedNotification]) async -> [String] {
        for notification in notifications {
            planned.removeAll { $0.identifier == notification.identifier }
            planned.append(PendingNotification(identifier: notification.identifier, fireDate: notification.fireDate, body: notification.body))
        }
        return []
    }

    func cancel(identifiers: [String]) async {
        planned.removeAll { identifiers.contains($0.identifier) }
    }

    func deliverNow(identifier: String, title: String, body: String) async {}
}
#endif
