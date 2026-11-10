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

@Test func hushallUtanInbjudnaGarAttLasa() throws {
    let state = HouseholdState(role: .owner, myId: "a", participants: [], addresses: [], marks: [], status: .synced)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
    json.removeValue(forKey: "invited")
    let decoded = try JSONDecoder().decode(HouseholdState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.invited.isEmpty)
    #expect(decoded == state)
}

@Test func inbjudenSomVantarPaSvar() {
    #expect(HouseholdTexts.invitedName(HouseholdInvitee(name: "Sofie")) == "Sofie")
    #expect(HouseholdTexts.invitedName(HouseholdInvitee(name: nil)) == "Inbjuden")
    #expect(HouseholdTexts.invitedName(HouseholdInvitee(name: "  ")) == "Inbjuden")
    #expect(HouseholdTexts.waitingForAnswer == "Väntar på svar")
}

@Test func hushalletHamtasVar15eSekundMedanAppenArOppen() {
    #expect(HouseholdLogic.liveFetchInterval == .seconds(15))
}
