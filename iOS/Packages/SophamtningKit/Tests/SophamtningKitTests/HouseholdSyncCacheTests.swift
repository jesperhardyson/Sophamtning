import Testing
import Foundation
import SophamtningKit

private final class TempDir {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sophamtning-synk-\(UUID().uuidString)", isDirectory: true)
    deinit { try? FileManager.default.removeItem(at: url) }
}

private let member = HouseholdState(
    role: .member,
    myId: "jag",
    participants: [HouseholdParticipant(id: "kim", name: "Kim", isOwner: true)],
    addresses: [],
    marks: [],
    status: .synced
)

@Test func ettSynkatLageSkickasInteInnanKopianArKomplett() {
    let trust = HouseholdSyncTrust()
    #expect(trust.gate(member) == nil)
    var none = member
    none.role = .none
    #expect(trust.gate(none) == nil, "Inget hushåll får aldrig skickas som synkat innan kopian är komplett")
}

@Test func ettLageMedFelSkickasUtanInnehallInnanKopianArKomplett() {
    var failed = member
    failed.status = .notSignedIn
    let gated = HouseholdSyncTrust().gate(failed)
    #expect(gated?.status == .notSignedIn)
    #expect(gated?.role == HouseholdRole.none)
    #expect(gated?.participants.isEmpty == true)
}

@Test func enLyckadHamtningGorKopianKomplett() {
    var trust = HouseholdSyncTrust()
    trust.fetchCompleted()
    #expect(trust.gate(member) == member)
}

@Test func utloggningOchInloggningTommerKopian() {
    var trust = HouseholdSyncTrust(complete: true)
    trust.signedOut()
    #expect(trust.complete, "Utloggad visas cachen med Synkar inte")
    let cleared = trust.signedIn()
    #expect(cleared)
    #expect(!trust.complete, "Efter inloggningen gäller kopian först efter en ny hämtning")
    #expect(trust.gate(member) == nil)
    let clearedAgain = trust.signedIn()
    #expect(!clearedAgain, "Bara första inloggningen tömmer kopian")
}

@Test func hamtningForeInloggningenGorInteKopianKomplett() {
    // Hämtningen hinner klart innan händelsen om inloggningen har tömt kopian. Den gamla kopian får inte bli pålitlig.
    var trust = HouseholdSyncTrust()
    trust.signedOut()
    trust.fetchCompleted()
    #expect(!trust.complete)
    _ = trust.signedIn()
    trust.fetchCompleted()
    #expect(trust.complete)
}

@Test func inloggningUtanUtloggningTommerInget() {
    var trust = HouseholdSyncTrust(complete: true)
    let cleared = trust.signedIn()
    #expect(!cleared)
    #expect(trust.complete)
}

@Test func nyttKontoOchOmstartGorKopianOkomplett() {
    var trust = HouseholdSyncTrust(complete: true, resetOnSignIn: true)
    trust.switchedAccount()
    #expect(trust == HouseholdSyncTrust())
    var restarted = HouseholdSyncTrust(complete: true)
    restarted.restarted()
    #expect(!restarted.complete)
}

@Test func kopianSparasOchLasesMedTillit() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    guard case .missing = HouseholdSyncCache.load(from: store) else {
        Issue.record("En kopia som saknas ska läsas som saknad")
        return
    }
    var trust = HouseholdSyncTrust()
    trust.fetchCompleted()
    trust.signedOut()
    let cache = HouseholdSyncCache(myId: "jag", hasPrivateZone: true, sharedZoneName: "Hushall", sharedZoneOwner: "_kim", privateRecords: [Data([1])], sharedRecords: [Data([2, 3])], trust: trust)
    try cache.save(to: store)
    guard case .value(let loaded) = HouseholdSyncCache.load(from: store) else {
        Issue.record("Kopian ska gå att läsa")
        return
    }
    #expect(loaded == cache)
    #expect(loaded.trust.complete && loaded.trust.resetOnSignIn)
}

@Test func enKopiaUtanTillitArInteKomplett() throws {
    struct Old: Encodable {
        var myId = "jag"
        var hasPrivateZone = false
        var privateRecords: [Data] = []
        var sharedRecords: [Data] = []
    }
    let data = try PropertyListEncoder().encode(Old())
    let cache = try PropertyListDecoder().decode(HouseholdSyncCache.self, from: data)
    #expect(cache.myId == "jag")
    #expect(!cache.trust.complete)
}

@Test func enSkadadKopiaArOlasbar() throws {
    let temp = TempDir()
    let store = LocalStore(directory: temp.url)
    try store.setRawData(Data("inte en plist".utf8), named: HouseholdSyncCache.fileName)
    guard case .unreadable = HouseholdSyncCache.load(from: store) else {
        Issue.record("En skadad kopia ska läsas som oläsbar")
        return
    }
}
