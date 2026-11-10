import Testing
import Foundation
import SophamtningKit

@Test func preferensernaHarRattStandard() {
    let preferences = HouseholdPreferences()
    #expect(preferences.silenceWhenOthersPlaceOut == true)
    #expect(preferences.notifyWhenOthersPlaceOut == false)
    #expect(preferences.receivedKeys.isEmpty)
    #expect(preferences.notifiedMarks.isEmpty)
}

@Test func preferenserUtanNyaFaltGarAttLasa() throws {
    let decoded = try JSONDecoder().decode(HouseholdPreferences.self, from: Data("{}".utf8))
    #expect(decoded == HouseholdPreferences())
}
