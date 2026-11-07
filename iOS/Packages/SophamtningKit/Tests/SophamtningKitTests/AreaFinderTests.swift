import Foundation
import Synchronization
import Testing
@testable import SophamtningKit

private func day(_ iso: String) -> DayDate { DayDate(iso)! }

private func hit(_ id: String = "trakt-7", pickups: Pickups? = nil) -> SearchHit {
    SearchHit(id: id, street: "Område \(id)", locality: "", kommun: "Avesta kommun", source: "avesta",
              detail: "Tisdag, jämn vecka · \(id)", selection: "area", notice: "Du väljer själv", areasUrl: nil,
              url: URL(string: "https://sopor.hardyson.se/api/v1/adress/avesta/\(id)")!, pickups: pickups)
}

private func response(_ hits: [SearchHit], covered: Bool?, failed: [String] = []) -> SearchResponse {
    SearchResponse(addresses: hits, failed: failed, dateCovered: covered)
}

@Suite struct AreaFinderStateTests {
    @Test func enTraffGerMatch() {
        let h = hit()
        #expect(AreaFinderState.from(response([h], covered: true)) == .match(h))
    }

    @Test func fleraTraffarGerLista() {
        let a = hit("a"), b = hit("b")
        #expect(AreaFinderState.from(response([a, b], covered: true)) == .multiple([a, b]))
    }

    @Test func tomListaInomSchematGerIngenHamtning() {
        #expect(AreaFinderState.from(response([], covered: true)) == .noPickup)
    }

    @Test func tomListaUtanforSchematGerUtanforSchemat() {
        #expect(AreaFinderState.from(response([], covered: false)) == .outsideSchedule)
    }

    @Test func tomListaUtanBedomningGerFelAldrigIngenHamtning() {
        #expect(AreaFinderState.from(response([], covered: nil)) == .failed)
    }

    @Test func tomListaMedFailedGerFelAvenOmSchematTacker() {
        #expect(AreaFinderState.from(response([], covered: true, failed: ["avesta"])) == .failed)
        #expect(AreaFinderState.from(response([], covered: false, failed: ["avesta"])) == .failed)
        #expect(AreaFinderState.from(response([], covered: nil, failed: ["avesta"])) == .failed)
    }

    @Test func traffVisasAvenOmEnKallaInteSvarade() {
        let h = hit()
        #expect(AreaFinderState.from(response([h], covered: nil, failed: ["skogsbo"])) == .match(h))
    }
}

@Suite struct AreaFinderDecodingTests {
    @Test func tomningsSvaretAvkodas() async throws {
        let (client, store) = try client(fixture: "omraden-tomning")
        let r = try await client.areas(place: "Avesta", lastEmptied: day("2026-10-27"))
        #expect(r.dateCovered == true)
        let pickups = try #require(r.addresses.first?.pickups)
        #expect(pickups.previous == [day("2026-10-13"), day("2026-10-27")])
        #expect(pickups.next == day("2026-11-10"))
        #expect(store.requests.first?.url?.absoluteString
                == "https://sopor.hardyson.se/api/v1/omraden?plats=Avesta&tomning=2026-10-27")
    }

    @Test func svarUtanNyaFaltAvkodasFortfarande() async throws {
        let (client, store) = try client(fixture: "omraden")
        let r = try await client.areas(place: "Avesta")
        #expect(r.dateCovered == nil)
        #expect(r.addresses.allSatisfy { $0.pickups == nil })
        #expect(store.requests.first?.url?.query == "plats=Avesta")
    }

    @Test func nastaKanVaraNullOchTidigareTom() async throws {
        let body = Data("""
        {"apiVersion":"1","failed":[],"dateCovered":true,"addresses":[{"id":"a","street":"A","locality":"","kommun":"C","source":"s",
        "detail":null,"url":"https://sopor.hardyson.se/api/v1/adress/s/a","pickups":{"previous":[],"next":null}}]}
        """.utf8)
        let (client, _) = makeClient(body: body)
        let p = try #require(try await client.areas(place: "x", lastEmptied: day("2026-10-27")).addresses.first?.pickups)
        #expect(p.previous.isEmpty)
        #expect(p.next == nil)
    }

    @Test func trasigaPickupsFallerInteTraffen() async throws {
        let body = Data("""
        {"apiVersion":"1","failed":[],"addresses":[{"id":"a","street":"A","locality":"","kommun":"C","source":"s",
        "detail":null,"url":"https://sopor.hardyson.se/api/v1/adress/s/a","pickups":{"previous":["fel"],"next":5}}]}
        """.utf8)
        let (client, _) = makeClient(body: body)
        let r = try await client.areas(place: "x", lastEmptied: day("2026-10-27"))
        #expect(r.addresses.count == 1)
        #expect(r.addresses[0].pickups == nil)
    }

    @Test func tomningsanropMedBadRequestKastas() async throws {
        let (client, _) = makeClient(status: 400, body: Data("{}".utf8))
        await #expect(throws: APIError.badRequest) {
            try await client.areas(place: "Avesta", lastEmptied: day("2026-10-27"))
        }
    }
}

@Suite struct AreaFinderTextTests {
    let today = day("2026-11-06")

    @Test func tvaTidigareOchNasta() {
        let p = Pickups(previous: [day("2026-10-13"), day("2026-10-27")], next: day("2026-11-10"))
        #expect(AreaFinderText.check(p, today: today)
                == "Tömningar 13 okt och 27 okt. Nästa är 10 nov. Stämmer det? En försenad tömning kan ge fel område.")
        #expect(AreaFinderText.summary(p, today: today) == "Tömningar 13 okt och 27 okt. Nästa 10 nov.")
    }

    @Test func enTidigare() {
        let p = Pickups(previous: [day("2026-11-03")], next: day("2026-11-17"))
        #expect(AreaFinderText.check(p, today: today)
                == "Tömning 3 nov. Nästa är 17 nov. Stämmer det? En försenad tömning kan ge fel område.")
    }

    @Test func nastaSomPasseratVisasSomVar() {
        let p = Pickups(previous: [day("2026-10-13"), day("2026-10-27")], next: day("2026-11-05"))
        #expect(AreaFinderText.check(p, today: today).contains("Nästa var 5 nov."))
        #expect(AreaFinderText.summary(p, today: today)?.hasSuffix("Nästa var 5 nov.") == true)
    }

    @Test func nastaDagensDatumArEjPasserat() {
        let p = Pickups(previous: [day("2026-10-27")], next: day("2026-11-06"))
        #expect(AreaFinderText.check(p, today: today).contains("Nästa är 6 nov."))
    }

    @Test func utanNastaUtelamnasMeningen() {
        let p = Pickups(previous: [day("2026-10-13"), day("2026-10-27")], next: nil)
        #expect(AreaFinderText.check(p, today: today)
                == "Tömningar 13 okt och 27 okt. Stämmer det? En försenad tömning kan ge fel område.")
        #expect(AreaFinderText.summary(p, today: today) == "Tömningar 13 okt och 27 okt.")
    }

    @Test func utanVeckodagOchUtanPickups() {
        #expect(AreaFinderText.check(nil, today: today) == "Stämmer det? En försenad tömning kan ge fel område.")
        #expect(AreaFinderText.summary(nil, today: today) == nil)
    }

    @Test func datumFaltetHarVeckodagOchAr() {
        #expect(SwedishFormat.longDateWithYear(day("2026-10-27")) == "Tisdag 27 oktober 2026")
        #expect(SwedishFormat.dayMonth(day("2026-10-13")) == "13 okt")
    }
}

// MARK: - AreaFinder (modellen bakom arket)

private final class FinderAPI: SoporAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _days: [DayDate] = []
    var handler: @Sendable (DayDate) async throws -> SearchResponse = { _ in SearchResponse(addresses: [], failed: [], dateCovered: true) }

    var days: [DayDate] { lock.withLock { _days } }

    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse {
        lock.withLock { _days.append(lastEmptied) }
        return try await handler(lastEmptied)
    }
    func search(query: String, source: String?) async throws -> SearchResponse { fatalError() }
    func areas(place: String) async throws -> SearchResponse { fatalError() }
    func address(url: URL) async throws -> AddressResponse { fatalError() }
    func sources() async throws -> SourcesResponse { fatalError() }
}

/// Stockholm: 2026-11-06 12:00.
private let nowDate = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 12 * 60)

@MainActor private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<400 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@MainActor @Suite struct AreaFinderModelTests {
    @Test func oppningenHarInteDatumOchGerInteAnrop() async {
        let api = FinderAPI()
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        #expect(finder.date == nil)
        #expect(finder.state == .idle)
        #expect(finder.latestSelectable == day("2026-11-06"))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(api.days.isEmpty)
        #expect(finder.state == .idle)
    }

    @Test func forsokIgenUtanValtDatumGerInteAnrop() async {
        let api = FinderAPI()
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.retry()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(api.days.isEmpty)
        #expect(finder.state == .idle)
    }

    @Test func idagRaknasISvenskTidOavsettTidpunktetPaDygnet() {
        // 23:30 UTC den 5 november är redan den 6 november i Stockholm.
        let late = Date(timeIntervalSince1970: 1_793_921_400)
        let finder = AreaFinder(api: FinderAPI(), place: "Avesta", now: { late })
        #expect(finder.latestSelectable == day("2026-11-06"))
    }

    @Test func framtidaDatumBegransasTillIDag() async {
        let finder = AreaFinder(api: FinderAPI(), place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-11-20"))
        #expect(finder.date == day("2026-11-06"))
    }

    @Test func senastValbaraRaknasOmVidValetEfterMidnatt() {
        let clock = Mutex(nowDate)
        let finder = AreaFinder(api: FinderAPI(), place: "Avesta", now: { clock.withLock { $0 } })
        finder.find(on: day("2026-11-07"))
        #expect(finder.date == day("2026-11-06"))
        // Midnatt har passerat medan arket låg öppet.
        clock.withLock { $0 = StockholmClock.date(on: day("2026-11-07"), minutes: 5) }
        #expect(finder.latestSelectable == day("2026-11-07"))
        finder.find(on: day("2026-11-07"))
        #expect(finder.date == day("2026-11-07"))
        finder.find(on: day("2026-11-08"))
        #expect(finder.date == day("2026-11-07"))
    }

    @Test func lyckatSvarGerMatchOchEttAnrop() async {
        let api = FinderAPI()
        let h = hit()
        api.handler = { _ in SearchResponse(addresses: [h], failed: [], dateCovered: true) }
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-10-27"))
        #expect(finder.state == .searching)
        #expect(await eventually { finder.state == .match(h) })
        #expect(api.days == [day("2026-10-27")])
        #expect(!finder.partial)
    }

    @Test func tekniskFelGerFelAldrigIngenHamtning() async {
        let api = FinderAPI()
        api.handler = { _ in throw APIError.network }
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-10-27"))
        #expect(await eventually { finder.state == .failed })
        #expect(finder.retryable)
    }

    @Test func badRequestGerFelUtanForsokIgen() async {
        let api = FinderAPI()
        api.handler = { _ in throw APIError.badRequest }
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-10-27"))
        #expect(await eventually { finder.state == .failed })
        #expect(!finder.retryable)
        // Ett nytt datum nollställer.
        api.handler = { _ in SearchResponse(addresses: [], failed: [], dateCovered: true) }
        finder.find(on: day("2026-10-26"))
        #expect(finder.retryable)
        #expect(await eventually { finder.state == .noPickup })
    }

    @Test func traffMedFailedMarkerasSomDelvis() async {
        let api = FinderAPI()
        let h = hit()
        api.handler = { _ in SearchResponse(addresses: [h], failed: ["skogsbo"], dateCovered: nil) }
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-10-27"))
        #expect(await eventually { finder.state == .match(h) })
        #expect(finder.partial)
        #expect(AreaFinderText.partialNotice == "En källa svarade inte, så fler områden kan finnas.")
    }

    @Test func gammaltSvarErsatterAldrigNyare() async {
        let api = FinderAPI()
        let gate = AsyncStream<Void>.makeStream()
        let slow = hit("gammal"), fresh = hit("ny")
        api.handler = { @Sendable day in
            if day == DayDate("2026-10-27")! {
                for await _ in gate.stream { break }
                return SearchResponse(addresses: [slow], failed: [], dateCovered: true)
            }
            return SearchResponse(addresses: [fresh], failed: [], dateCovered: true)
        }
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-10-27"))
        #expect(await eventually { api.days.count == 1 })
        finder.find(on: day("2026-10-13"))
        #expect(await eventually { finder.state == .match(fresh) })
        gate.continuation.yield()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(finder.state == .match(fresh))
        #expect(finder.date == day("2026-10-13"))
    }

    @Test func gammaltFelErsatterInteNyttSvar() async {
        let api = FinderAPI()
        let gate = AsyncStream<Void>.makeStream()
        let fresh = hit("ny")
        api.handler = { @Sendable day in
            if day == DayDate("2026-10-27")! {
                for await _ in gate.stream { break }
                throw APIError.badRequest
            }
            return SearchResponse(addresses: [fresh], failed: [], dateCovered: true)
        }
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-10-27"))
        #expect(await eventually { api.days.count == 1 })
        finder.find(on: day("2026-10-13"))
        #expect(await eventually { finder.state == .match(fresh) })
        gate.continuation.yield()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(finder.state == .match(fresh))
        #expect(finder.retryable)
    }

    @Test func andratUtkastGerInteAnropOchTarBortGammaltResultat() async {
        let api = FinderAPI()
        let h = hit()
        api.handler = { _ in SearchResponse(addresses: [h], failed: [], dateCovered: true) }
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        #expect(finder.draft == day("2026-11-06"))
        finder.setDraft(day("2026-10-27"))
        finder.setDraft(day("2026-10-26"))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(api.days.isEmpty)
        #expect(finder.state == .idle)
        #expect(finder.date == nil)

        finder.find()
        #expect(await eventually { finder.state == .match(h) })
        #expect(api.days == [day("2026-10-26")])
        #expect(finder.date == day("2026-10-26"))

        // Nytt utkast: resultatet för förra datumet försvinner och inget frågas förrän knappen trycks.
        finder.setDraft(day("2026-10-24"))
        #expect(finder.state == .idle)
        #expect(finder.date == nil)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(api.days == [day("2026-10-26")])
        finder.find()
        #expect(await eventually { api.days.count == 2 })
        #expect(api.days.last == day("2026-10-24"))
    }

    @Test func sammaUtkastBehallerResultatet() async {
        let api = FinderAPI()
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-10-27"))
        #expect(await eventually { finder.state == .noPickup })
        finder.setDraft(day("2026-10-27"))
        #expect(finder.state == .noPickup)
        #expect(finder.date == day("2026-10-27"))
    }

    @Test func gammaltSvarErsatterInteEttNyttUtkast() async {
        let api = FinderAPI()
        let gate = AsyncStream<Void>.makeStream()
        api.handler = { @Sendable _ in
            for await _ in gate.stream { break }
            return SearchResponse(addresses: [hit()], failed: [], dateCovered: true)
        }
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        finder.find(on: day("2026-10-27"))
        #expect(await eventually { api.days.count == 1 })
        finder.setDraft(day("2026-10-24"))
        gate.continuation.yield()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(finder.state == .idle)
    }

    @Test func utkastetBegransasTillIDag() {
        let finder = AreaFinder(api: FinderAPI(), place: "Avesta", now: { nowDate })
        finder.setDraft(day("2026-11-20"))
        #expect(finder.draft == day("2026-11-06"))
    }

    @Test func forsokIgenAnroparMedSammaDatum() async {
        let api = FinderAPI()
        let finder = AreaFinder(api: api, place: "Avesta", now: { nowDate })
        api.handler = { _ in throw APIError.network }
        finder.find(on: day("2026-10-27"))
        #expect(await eventually { finder.state == .failed })
        api.handler = { _ in SearchResponse(addresses: [], failed: [], dateCovered: false) }
        finder.retry()
        #expect(await eventually { finder.state == .outsideSchedule })
        #expect(api.days == [day("2026-10-27"), day("2026-10-27")])
    }
}

@Suite struct DayDatePickerTests {
    @Test(arguments: ["America/New_York", "Asia/Tokyo", "Europe/Stockholm", "Pacific/Kiritimati"])
    func valdDagBlirRattIValfriTidszon(_ id: String) throws {
        let zone = try #require(TimeZone(identifier: id))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        for (hour, minute) in [(0, 0), (0, 1), (12, 0), (23, 59)] {
            let picked = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: hour, minute: minute)))
            #expect(DayDate.from(picked: picked, in: zone) == day("2026-10-27"), "\(id) \(hour):\(minute)")
        }
    }

    @Test(arguments: ["America/New_York", "Asia/Tokyo", "Europe/Stockholm"])
    func dagenBlirEttDatumSomVisarSammaDagIZonen(_ id: String) throws {
        let zone = try #require(TimeZone(identifier: id))
        let picked = day("2026-10-27").pickerDate(in: zone)
        #expect(DayDate.from(picked: picked, in: zone) == day("2026-10-27"))
    }

    @Test func kommunNamnVisasBaraNarTraffarnaGallerFlera() {
        func h(_ k: String) -> SearchHit {
            SearchHit(id: k, street: "S", locality: "", kommun: k, source: "s", detail: nil, selection: "area", notice: nil, areasUrl: nil,
                      url: URL(string: "https://sopor.hardyson.se/api/v1/adress/s/\(k)")!)
        }
        #expect(!AreaFinderText.showsKommun([h("Avesta kommun"), h("Avesta kommun")]))
        #expect(AreaFinderText.showsKommun([h("Avesta kommun"), h("Hedemora kommun")]))
    }
}

@Suite struct AreaFinderFoundTests {
    @Test func barTraffarRaknasSomFunna() {
        let h = hit()
        #expect(AreaFinderState.match(h).foundAreas)
        #expect(AreaFinderState.multiple([h, hit("b")]).foundAreas)
        for state in [AreaFinderState.idle, .searching, .noPickup, .outsideSchedule, .failed] {
            #expect(!state.foundAreas)
        }
    }
}
