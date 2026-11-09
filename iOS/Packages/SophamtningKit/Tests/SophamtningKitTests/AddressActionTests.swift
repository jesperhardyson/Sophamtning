import Testing
@testable import SophamtningKit

/// Valen i snabbmenyn och bland VoiceOver-åtgärderna på hemskärmen.
@Suite struct AddressActionTests {
    @Test func huvudadressenHarLiveActivityMenInteGorTillHuvudadress() {
        #expect(AddressAction.choices(isPrimary: true) == [.rename, .notifications, .liveActivity, .remove])
    }

    @Test func andraAdresserKanBliHuvudadressMenHarIngenLiveActivity() {
        #expect(AddressAction.choices(isPrimary: false) == [.rename, .makePrimary, .notifications, .remove])
    }
}
