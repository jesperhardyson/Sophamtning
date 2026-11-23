package se.hardyson.sophamtning.core.reminders

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.storeJson

/** ReminderTimeTests på iOS. */
class ReminderTimeTest {
    private fun decode(json: String) = storeJson.decodeFromString(ReminderSettings.serializer(), json)
    private fun encode(settings: ReminderSettings) = storeJson.encodeToString(ReminderSettings.serializer(), settings)

    @Test
    fun gamlaInställningarLäsesSomKvällenFöre() {
        val s = decode("""{"reminderMinutes":1140,"liveActivityOn":true}""")
        assertTrue(s.enabledTimings == listOf(ReminderTiming.EveningBefore) && s.liveActivityTiming == ReminderTiming.EveningBefore)
        assertEquals(1140, s.reminderMinutes)
        assertEquals(360, s.morningMinutes)
    }

    @Test
    fun okäntValLäsesSomKvällenFöre() {
        val s = decode("""{"reminderMinutes":1080,"liveActivityOn":false,"timing":"lunch","morningMinutes":420}""")
        assertTrue(s.enabledTimings == listOf(ReminderTiming.EveningBefore) && s.liveActivityTiming == ReminderTiming.EveningBefore)
        assertEquals(420, s.morningMinutes)
    }

    @Test
    fun bådaTidernaSparas() {
        val s = ReminderSettings(eveningOn = false, morningOn = true, reminderMinutes = 1200, morningMinutes = 420, liveActivityTiming = ReminderTiming.SameMorning)
        assertEquals(s, decode(encode(s)))
    }

    @Test
    fun giltigMorgontid() {
        for ((m, ok) in listOf(285 to false, 300 to true, 540 to true, 555 to false, 310 to false, 1080 to false)) {
            assertEquals(ok, ReminderSettings.isValid(m, ReminderTiming.SameMorning), "$m")
        }
    }

    @Test
    fun trasigKvällstidPåverkarInteMorgonen() {
        val s = ReminderSettings(eveningOn = false, morningOn = true, reminderMinutes = 5, morningMinutes = 420, liveActivityTiming = ReminderTiming.SameMorning)
        assertEquals(420, s.minutes(ReminderTiming.SameMorning))
        assertEquals(360, ReminderSettings(eveningOn = false, morningOn = true, morningMinutes = 1000, liveActivityTiming = ReminderTiming.SameMorning).minutes(ReminderTiming.SameMorning))
        assertEquals(1080, ReminderSettings(reminderMinutes = 5).minutes(ReminderTiming.EveningBefore))
    }

    @Test
    fun tiderFörValen() {
        assertEquals(1080, ReminderTiming.EveningBefore.defaultMinutes)
        assertEquals(360, ReminderTiming.SameMorning.defaultMinutes)
        assertEquals(300, ReminderTiming.SameMorning.times.first())
        assertEquals(540, ReminderTiming.SameMorning.times.last())
        assertEquals(17, ReminderTiming.SameMorning.times.size)
        assertEquals(33, ReminderTiming.EveningBefore.times.size)
    }

    @Test
    fun tidFörTömning() {
        val evening = ReminderSettings(reminderMinutes = 1080)
        val morning = ReminderSettings(eveningOn = false, morningOn = true, morningMinutes = 360, liveActivityTiming = ReminderTiming.SameMorning)
        assertEquals(stockholm("2026-11-10T18:00"), ReminderTime.date(day("2026-11-11"), ReminderTiming.EveningBefore, evening))
        assertEquals(stockholm("2026-11-11T06:00"), ReminderTime.date(day("2026-11-11"), ReminderTiming.SameMorning, morning))
        // Sommartiden slutar 2026-10-25, så klockslaget ska stå kvar i svensk tid.
        assertEquals(stockholm("2026-10-25T18:00"), ReminderTime.date(day("2026-10-26"), ReminderTiming.EveningBefore, evening))
        assertEquals(day("2026-11-11"), ReminderTime.pickupDay(day("2026-11-10"), ReminderTiming.EveningBefore))
        assertEquals(day("2026-11-10"), ReminderTime.pickupDay(day("2026-11-10"), ReminderTiming.SameMorning))
    }

    @Test
    fun gammalKvällLäses() {
        val s = decode("""{"timing":"eveningBefore","reminderMinutes":1140,"morningMinutes":420,"liveActivityOn":true}""")
        assertTrue(s.eveningOn && !s.morningOn && s.liveActivityTiming == ReminderTiming.EveningBefore)
        assertTrue(s.minutes(ReminderTiming.EveningBefore) == 1140 && s.minutes(ReminderTiming.SameMorning) == 420)
    }

    @Test
    fun gammalMorgonLäses() {
        val s = decode("""{"timing":"sameMorning","reminderMinutes":1080,"morningMinutes":420,"liveActivityOn":false}""")
        assertTrue(!s.eveningOn && s.morningOn && s.liveActivityTiming == ReminderTiming.SameMorning)
    }

    @Test
    fun utanTimingOchOkändTimingBlirKväll() {
        assertEquals(listOf(ReminderTiming.EveningBefore), decode("""{"reminderMinutes":1080,"liveActivityOn":false}""").enabledTimings)
        assertEquals(listOf(ReminderTiming.EveningBefore), decode("""{"timing":"lunch","reminderMinutes":1080,"liveActivityOn":false}""").enabledTimings)
    }

    @Test
    fun bådaAvLäsesSomKväll() {
        val s = decode("""{"eveningOn":false,"morningOn":false,"reminderMinutes":1080,"liveActivityOn":false}""")
        assertEquals(listOf(ReminderTiming.EveningBefore), s.enabledTimings)
    }

    @Test
    fun nyaFältenSparasOchTimingSkrivsInte() {
        val s = ReminderSettings(eveningOn = true, morningOn = true, morningMinutes = 420, liveActivityTiming = ReminderTiming.SameMorning)
        val data = encode(s)
        assertEquals(s, decode(data))
        assertFalse(data.contains("\"timing\""))
    }

    @Test
    fun ogiltigTidGerFörval() {
        val s = ReminderSettings(reminderMinutes = 5, morningMinutes = 1000)
        assertTrue(s.minutes(ReminderTiming.EveningBefore) == 1080 && s.minutes(ReminderTiming.SameMorning) == 360)
    }

    @Test
    fun värdetPåRaden() {
        assertEquals("Kvällen före, 18:00", ReminderSettings().settingsValue)
        assertEquals("Samma morgon, 06:00", ReminderSettings(eveningOn = false, morningOn = true).settingsValue)
        assertEquals("18:00 och 07:00", ReminderSettings(morningOn = true, morningMinutes = 420).settingsValue)
    }

    @Test
    fun nästaPåminnelse() {
        val s = ReminderSettings(morningOn = true)
        val events = listOf(event("2026-11-11", listOf("rest")))
        assertEquals(
            ReminderTime.UpcomingReminder(day("2026-11-11"), ReminderTiming.EveningBefore, stockholm("2026-11-10T18:00")),
            ReminderTime.next(events, s, stockholm("2026-11-10T12:00")),
        )
        assertEquals(ReminderTiming.SameMorning, ReminderTime.next(events, s, stockholm("2026-11-10T19:00"))?.timing)
        assertNull(ReminderTime.next(events, s, stockholm("2026-11-11T07:00")))
    }

    @Test
    fun okäntLiveActivityValLäsesSomDetEnaValet() {
        // Från en senare version: hela filen ska ändå gå att läsa.
        val a = decode("""{"eveningOn":false,"morningOn":true,"reminderMinutes":1080,"liveActivityOn":true,"liveActivityTiming":"lunch"}""")
        assertTrue(a.morningOn && !a.eveningOn)
        assertEquals(ReminderTiming.EveningBefore, a.liveActivityTiming)
        val b = decode("""{"timing":"sameMorning","reminderMinutes":1080,"liveActivityOn":true,"liveActivityTiming":"lunch"}""")
        assertEquals(ReminderTiming.SameMorning, b.liveActivityTiming)
    }

    @Test
    fun nästaPåminnelseHopparÖverUtelämnadeTömningar() {
        val s = ReminderSettings(morningOn = true)
        val events = listOf(event("2026-11-11", listOf("rest")), event("2026-11-13", listOf("rest")))
        val next = ReminderTime.next(events, s, stockholm("2026-11-10T19:00"), skipping = setOf(day("2026-11-11")))
        assertEquals(ReminderTime.UpcomingReminder(day("2026-11-13"), ReminderTiming.EveningBefore, stockholm("2026-11-12T18:00")), next)
        assertNull(ReminderTime.next(listOf(events[0]), s, stockholm("2026-11-10T19:00"), skipping = setOf(day("2026-11-11"))))
    }
}
