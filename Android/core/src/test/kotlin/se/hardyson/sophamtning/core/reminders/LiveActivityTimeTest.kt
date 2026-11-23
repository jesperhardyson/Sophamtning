package se.hardyson.sophamtning.core.reminders

import kotlin.test.Test
import kotlin.test.assertEquals
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.storeJson

/** LiveActivityTimeTests på iOS. */
class LiveActivityTimeTest {
    private fun decode(json: String) = storeJson.decodeFromString(ReminderSettings.serializer(), json)

    @Test
    fun gammalInställningFårNotisensTid() {
        val evening = decode("""{"eveningOn":true,"morningOn":true,"reminderMinutes":1140,"morningMinutes":420,"liveActivityTiming":"eveningBefore","liveActivityOn":true}""")
        assertEquals(1140, evening.liveActivityStartMinutes)
        val morning = decode("""{"eveningOn":true,"morningOn":false,"reminderMinutes":1140,"morningMinutes":420,"liveActivityTiming":"sameMorning","liveActivityOn":true}""")
        assertEquals(420, morning.liveActivityStartMinutes)
    }

    @Test
    fun egenTidSparasOchÄrOberoende() {
        var s = ReminderSettings(reminderMinutes = 900, liveActivityMinutes = 1260)
        assertEquals(1260, s.liveActivityStartMinutes)
        assertEquals(900, s.minutes(ReminderTiming.EveningBefore))
        s = s.copy(reminderMinutes = 1080)
        assertEquals(1260, s.liveActivityStartMinutes)
        assertEquals(s, storeJson.decodeFromString(ReminderSettings.serializer(), storeJson.encodeToString(ReminderSettings.serializer(), s)))
    }

    @Test
    fun ogiltigAktivitetstidGerNotisensTid() {
        // 21:00 går inte på morgonen, så morgonens notistid gäller.
        val s = ReminderSettings(morningMinutes = 420, liveActivityTiming = ReminderTiming.SameMorning, liveActivityMinutes = 1260)
        assertEquals(420, s.liveActivityStartMinutes)
    }

    @Test
    fun aktivitetensTidFörTömning() {
        val s = ReminderSettings(reminderMinutes = 900, liveActivityMinutes = 1260)
        assertEquals(StockholmClock.dateOn(day("2026-11-24"), 1260), ReminderTime.liveActivityStart(day("2026-11-25"), s))
    }
}

/** De två testerna i LiveActivityTimeTests på iOS som gäller texterna. */
class LiveActivityTimeTextsTest {
    @Test
    fun textenVisarHelaTiden() {
        assertEquals("Visas på låsskärmen kl. 21:00 dagen före till 09:00.", se.hardyson.sophamtning.core.home.AddressDetail.liveActivityText(ReminderSettings(liveActivityMinutes = 1260)))
        assertEquals("Visas på låsskärmen kl. 15:00 dagen före till 03:00.", se.hardyson.sophamtning.core.home.AddressDetail.liveActivityText(ReminderSettings(liveActivityMinutes = 900)))
        assertEquals(
            "Visas på låsskärmen kl. 06:00–18:00 samma dag.",
            se.hardyson.sophamtning.core.home.AddressDetail.liveActivityText(ReminderSettings(liveActivityTiming = ReminderTiming.SameMorning, liveActivityMinutes = 360)),
        )
    }

    /** Android: systemet har ingen gräns som iOS, så det är appen som tar bort Live Updaten. Inget hushåll. */
    @Test
    fun tidslistansTextFörAktiviteten() {
        assertEquals(
            "Appen visar en Live Update i högst 12 timmar. Den försvinner tidigare när du trycker Klart eller sveper bort den.",
            ReminderTiming.liveActivityTimesFooter,
        )
    }
}
