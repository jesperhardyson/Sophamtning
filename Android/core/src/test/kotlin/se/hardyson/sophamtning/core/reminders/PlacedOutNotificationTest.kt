package se.hardyson.sophamtning.core.reminders

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.PlacedOut

private val key = AddressKey(source = "avesta", id = "Kaplansgården|Jularbo m.fl.")
private val day = DayDate.parse("2026-11-11")!!

/** PlacedOutNotificationTests på iOS. */
class PlacedOutNotificationTest {
    @Test
    fun notisenBärTömningen() {
        val info = PlacedOutNotification.userInfo(key, day)
        assertEquals(PlacedOut(key, day), PlacedOutNotification.entry(info))
    }

    @Test
    fun adressIdAnvändsSomDetÄr() {
        // Id:t tolkas och byggs aldrig om, också med tecken som | och mellanslag.
        assertEquals("Kaplansgården|Jularbo m.fl.", PlacedOutNotification.userInfo(key, day)["adressId"])
    }

    @Test
    fun trasigNotisGerIngenTömning() {
        assertNull(PlacedOutNotification.entry(emptyMap()))
        assertNull(PlacedOutNotification.entry(mapOf("kalla" to "avesta", "adressId" to "x", "datum" to "11 nov")))
        assertNull(PlacedOutNotification.entry(mapOf("kalla" to "avesta", "datum" to "2026-11-11")))
    }

    @Test
    fun knappenOchKategorin() {
        assertEquals("Utställt", PlacedOutNotification.ACTION_TITLE)
        assertEquals("paminnelse", PlacedOutNotification.CATEGORY_IDENTIFIER)
        assertEquals("utstallt", PlacedOutNotification.ACTION_IDENTIFIER)
    }
}
