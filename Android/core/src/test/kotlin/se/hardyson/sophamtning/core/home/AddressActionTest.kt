package se.hardyson.sophamtning.core.home

import kotlin.test.Test
import kotlin.test.assertEquals

/** Valen i menyn och bland TalkBacks åtgärder på hemskärmen. AddressActionTests på iOS. */
class AddressActionTest {
    @Test
    fun huvudadressenHarLiveActivityMenInteGorTillHuvudadress() {
        assertEquals(listOf(AddressAction.Rename, AddressAction.Notifications, AddressAction.LiveActivity, AddressAction.Remove), AddressAction.choices(isPrimary = true))
    }

    @Test
    fun andraAdresserKanBliHuvudadressMenHarIngenLiveActivity() {
        assertEquals(listOf(AddressAction.Rename, AddressAction.MakePrimary, AddressAction.Notifications, AddressAction.Remove), AddressAction.choices(isPrimary = false))
    }
}
