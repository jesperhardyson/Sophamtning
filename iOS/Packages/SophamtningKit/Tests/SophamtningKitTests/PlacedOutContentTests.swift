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
}
