import Testing
import Foundation
@testable import SophamtningKit

private func addressResponse(area: Any?, omit: Bool = false) throws -> AddressResponse {
    var json = try #require(try JSONSerialization.jsonObject(with: fixtureData("adress-avesta")) as? [String: Any])
    var address = try #require(json["address"] as? [String: Any])
    if omit { address.removeValue(forKey: "area") } else { address["area"] = area ?? NSNull() }
    json["address"] = address
    return try JSONDecoder().decode(AddressResponse.self, from: JSONSerialization.data(withJSONObject: json))
}

private func area(_ otherDays: Any?) -> [String: Any] {
    ["day": "Måndag, udda vecka", "label": "Område 7", "places": ["Rosse"], "otherDays": otherDays ?? NSNull(), "searchTerms": []]
}

@Suite struct AddressAreaDecodingTests {
    @Test func omradetAvkodasIAdressvaret() throws {
        let response = try addressResponse(area: area(["Grängesbergsgatan har hämtning på tisdagar."]))
        #expect(response.address.area?.otherDays == ["Grängesbergsgatan har hämtning på tisdagar."])
        #expect(response.address.area?.label == "Område 7")
    }

    @Test func faltetSaknasEllerArNull() throws {
        #expect(try addressResponse(area: nil, omit: true).address.area == nil)
        #expect(try addressResponse(area: nil).address.area == nil)
    }

    @Test func trasigtFaltFallerInteAdressvaret() throws {
        #expect(try addressResponse(area: "trasig").address.area == nil)
        let partial = try addressResponse(area: ["day": 3, "otherDays": "fel"])
        #expect(partial.address.area == AreaDetails(day: "", label: nil, places: []))
    }

    @Test func sparadDataUtanFaltetAvkodasOchKodasOm() throws {
        let old = try addressResponse(area: nil, omit: true)
        let again = try JSONDecoder().decode(AddressResponse.self, from: JSONEncoder().encode(old))
        #expect(again == old)
        let withArea = try addressResponse(area: area(["En rad."]))
        #expect(try JSONDecoder().decode(AddressResponse.self, from: JSONEncoder().encode(withArea)) == withArea)
    }
}

@Suite struct OtherDaysNoteTests {
    @Test func radernVisasUnderRubriken() throws {
        let note = try #require(OtherDaysNote.make(AreaDetails(day: "x", label: nil, places: [], otherDays: ["Rad ett.", "Rad två."])))
        #expect(note.heading == "Vissa gator har en annan hämtdag")
        #expect(note.rows == ["Rad ett.", "Rad två."])
        #expect(note.accessibilityLabel == "Vissa gator har en annan hämtdag. Rad ett. Rad två.")
    }

    @Test func blankaRaderRensasBort() throws {
        let note = try #require(OtherDaysNote.make(AreaDetails(day: "x", label: nil, places: [], otherDays: ["  ", "", " Rad ett.\n", "\t"])))
        #expect(note.rows == ["Rad ett."])
    }

    @Test func tomListaNullOchSaknatGerIngenRuta() {
        #expect(OtherDaysNote.make(AreaDetails(day: "x", label: nil, places: [], otherDays: [])) == nil)
        #expect(OtherDaysNote.make(AreaDetails(day: "x", label: nil, places: [], otherDays: [" ", ""])) == nil)
        #expect(OtherDaysNote.make(nil) == nil)
    }

    @Test func adressvynHarRutanFranSparatSchema() throws {
        let key = AddressKey(source: "avesta", id: "trakt-7")
        let saved = SavedAddress(key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/avesta/trakt-7")!, street: "Område 7", locality: "", kommun: "Avesta kommun", detail: nil, selection: "area", displayName: "Område 7", isPrimary: true, addedAt: Date(timeIntervalSince1970: 0))
        let now = StockholmClock.date(on: DayDate("2026-11-06")!, minutes: 12 * 60)
        func make(_ response: AddressResponse?) -> AddressDetail {
            let cached = response.map { CachedSchedule(response: $0, fetchedAt: now, lastAttemptAt: now, lastError: nil) }
            return AddressDetail.make(address: saved, schedule: cached, settings: ReminderSettings(), sourceName: "Avesta", now: now)
        }
        #expect(try make(addressResponse(area: area(["En rad."]))).otherDays?.rows == ["En rad."])
        #expect(try make(addressResponse(area: area([]))).otherDays == nil)
        #expect(try make(addressResponse(area: nil)).otherDays == nil)
        #expect(try make(addressResponse(area: nil, omit: true)).otherDays == nil)
        #expect(make(nil).otherDays == nil)
    }
}
