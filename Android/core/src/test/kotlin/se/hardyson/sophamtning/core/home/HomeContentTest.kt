package se.hardyson.sophamtning.core.home

import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.api.SchedulePeriod
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.kommun.kommunDisplayName
import se.hardyson.sophamtning.core.kommun.kommunRepeatsLocality
import se.hardyson.sophamtning.core.kommun.localityAndKommun
import se.hardyson.sophamtning.core.kommun.shortKommunName
import se.hardyson.sophamtning.core.reminders.ExistingActivity
import se.hardyson.sophamtning.core.reminders.PickupActivityContent
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.storage.savedAddress

private val monday = homeMonday
private val today = homeToday
private val now = homeNow
private val home = homeAddress
private val cabin = cabinAddress
private fun event(iso: String, fractions: List<String>, estimated: Boolean = false) = homeEvent(iso, fractions, estimated)
private fun schedule(events: List<PickupEvent>, lastError: ApiError? = null) = homeSchedule(events, lastError = lastError)

private fun make(addresses: List<SavedAddress>, schedules: Map<AddressKey, CachedSchedule>, settings: ReminderSettings = ReminderSettings(), time: Instant = now) =
    HomeContent.make(addresses, schedules, settings, time)

private fun upcoming(entry: HomeContent.Entry?) = assertIs<HomeContent.Status.Upcoming>(assertNotNull(entry).status).pickup

private val on = home.copy(notificationsOn = true)

private fun reminder(events: List<PickupEvent>, time: Instant) = assertNotNull(make(listOf(on), mapOf(on.key to schedule(events)), time = time).primary).reminder?.detail

private val tuesdayPickup = listOf(event("2026-11-11", listOf("rest")))

private fun endingSchedule(until: String?, events: List<PickupEvent> = listOf(event("2026-11-09", listOf("rest"))), lastError: ApiError? = null) =
    homeSchedule(events, lastError = lastError, period = until?.let { SchedulePeriod(day(it), "Orsak.") })

private fun endingHome(cached: CachedSchedule?): HomeContent {
    val address = savedAddress(key = AddressKey(source = "x", id = "a"), isPrimary = true)
    return HomeContent.make(listOf(address), cached?.let { mapOf(address.key to it) } ?: emptyMap(), ReminderSettings(), now)
}

private val sunday = StockholmClock.dateOn(day("2026-11-08"), 12 * 60)
private val sundayEvening = StockholmClock.dateOn(day("2026-11-08"), 19 * 60)

private fun footLine(placedOut: Set<PlacedOut> = emptySet()): String? {
    val events = listOf(event("2026-11-09", listOf("rest")), event("2026-11-11", listOf("rest")))
    val content = HomeContent.make(listOf(on), mapOf(on.key to schedule(events)), ReminderSettings(morningOn = true), sundayEvening, ownPlacedOut = placedOut)
    return assertNotNull(content.primary?.reminder).line
}

/** HomeContentTests på iOS, med raden för Utställt utan hushåll. */
class HomeContentTest {
    @Test
    fun utanAdresserFinnsInteNagotHuvudkort() {
        val content = make(emptyList(), emptyMap())
        assertNull(content.primary)
        assertTrue(content.others.isEmpty())
    }

    @Test
    fun huvudkortetVisarNastaTomning() {
        val primary = assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest", "mat")))))).primary)
        assertEquals("Hemma", primary.title)
        assertEquals(HomeContent.AddressLines(address = "Storgatan 12 B", place = "Krylbo · Avesta kommun"), primary.lines)
        val pickup = upcoming(primary)
        assertEquals(monday, pickup.date)
        assertEquals("Om 3 dagar", pickup.headline)
        assertEquals("Måndag 9 november", pickup.longDate)
        assertEquals(listOf("rest", "mat"), pickup.fractions.map { it.id })
        assertEquals(listOf("Restavfall", "Matavfall"), pickup.fractions.map { it.info.name })
    }

    @Test
    fun ovrigaAdresserBlirRaderMedKortDatumOchRelativDag() {
        val content = make(listOf(home, cabin), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))), cabin.key to schedule(listOf(event("2026-11-18", listOf("plast"))))))
        val row = assertNotNull(content.others.firstOrNull())
        assertEquals(1, content.others.size)
        assertEquals("Stugan", row.title)
        assertEquals(HomeContent.AddressLines(address = "Bergsvägen 4", place = "Horndal · Avesta kommun"), row.lines)
        assertEquals("Ons 18 nov · om 12 dagar", row.summary)
        assertEquals(listOf("plast"), upcoming(row).fractions.map { it.id })
        assertEquals("Stugan, Bergsvägen 4, Horndal, Avesta kommun, Ons 18 nov · om 12 dagar, Plastförpackningar", row.accessibilityLabel)
    }

    @Test
    fun dagarRaknasLokaltEjFranSparatDatum() {
        // Svaret sparades den 6:e, men nu är det lördag den 7:e.
        val later = StockholmClock.dateOn(day("2026-11-07"), 9 * 60)
        assertEquals("I morgon", upcoming(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-08", listOf("rest"))))), time = later).primary).headline)
    }

    @Test
    fun tvaDagarKvarArIOvermorgon() {
        // Nu är det lördag den 7:e, och tömningen är måndag den 9:e.
        val later = StockholmClock.dateOn(day("2026-11-07"), 9 * 60)
        assertEquals("I övermorgon", upcoming(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), time = later).primary).headline)
        // Ett beräknat datum får "Ca" först.
        assertEquals("Ca i övermorgon", upcoming(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"), estimated = true)))), time = later).primary).headline)
    }

    @Test
    fun hamtningIDagVisasSomIDag() {
        assertEquals("I dag", upcoming(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-06", listOf("rest")))))).primary).headline)
    }

    @Test
    fun uppskattatDatumVisasMedCa() {
        val content = make(listOf(home, cabin), mapOf(
            home.key to schedule(listOf(event("2026-11-09", listOf("rest"), estimated = true))),
            cabin.key to schedule(listOf(event("2026-11-18", listOf("plast"), estimated = true))),
        ))
        val pickup = upcoming(content.primary)
        assertEquals("Ca om 3 dagar", pickup.headline)
        assertEquals("Ca måndag 9 november", pickup.longDate)
        assertEquals("ca Ons 18 nov · om 12 dagar", content.others[0].summary)
    }

    // MARK: Tömningsdagen

    @Test fun tomningIDagGerRad() = assertEquals("Kärlen ska stå ute i dag.", assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-06", listOf("rest")))))).primary).dayNote)

    @Test fun tomningIMorgonGerIngenRad() = assertNull(assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-07", listOf("rest")))))).primary).dayNote)

    @Test
    fun beraknadTomningIDagSagerSomBeraknat() {
        val primary = assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-06", listOf("rest"), estimated = true))))).primary)
        assertEquals("Kärlen ska stå ute i dag, om tömningen kommer som beräknat.", primary.dayNote)
    }

    @Test fun utanHamtningarGerIngenRad() = assertNull(assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-02", listOf("rest")))))).primary).dayNote)

    @Test
    fun passeratSchemaGerIngaKommandeHamtningar() {
        val primary = assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-02", listOf("rest")))))).primary)
        assertEquals(HomeContent.Status.NoUpcoming, primary.status)
        assertEquals("Inga kommande hämtningar", primary.summary)
        assertNull(primary.reminder)
    }

    @Test
    fun utanPaslagenPaminnelseVisasInbjudan() {
        assertNull(assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))))).primary).reminder?.detail)
    }

    @Test
    fun notisPaGerPaminnelseKvallenFore() {
        assertEquals("Söndag kl. 18:00", assertNotNull(make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest")))))).primary).reminder?.detail)
    }

    @Test
    fun utanAktivitetLovasIngenLiveActivity() {
        // Utan någon Live Update hos systemet påminner inget, och kortet får inte låta som att något gör det.
        val content = make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(reminderMinutes = 1050, liveActivityOn = true))
        assertEquals("Ingen Live Update planerad", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun felVidStartVisasPaKortet() {
        val content = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivityError = "Kunde inte läggas in.")
        assertEquals("Kunde inte läggas in.", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun felVidStartVisasAvenMedNotiser() {
        // Notiser på, misslyckad direktstart och passerad tid: varken Live Update eller notis för nästa tömning.
        val schedules = mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-12", listOf("rest")))))
        val content = HomeContent.make(listOf(on), schedules, ReminderSettings(liveActivityOn = true), now, liveActivityError = "Kunde inte läggas in.")
        assertEquals("Kunde inte läggas in.", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun felVisasInteNarValetArAv() {
        val content = HomeContent.make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = false), now, liveActivityError = "Gammalt fel.")
        assertEquals("Söndag kl. 18:00", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun passeradPaminnelseForNastaTomningVisas() {
        val schedules = mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-12", listOf("rest")))))
        val content = HomeContent.make(listOf(on), schedules, ReminderSettings(), now, missedReminder = "Tömning i morgon. Påminnelsen för i kväll har redan passerat.")
        assertEquals("Tömning i morgon. Påminnelsen för i kväll har redan passerat.", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun felGarForePasseradPaminnelse() {
        val content = HomeContent.make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivityError = "Kunde inte läggas in.", missedReminder = "Passerad.")
        assertEquals("Kunde inte läggas in.", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun passeradStarttidLovasInte() {
        val content = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivity = activity(pending = true, start = now - Duration.ofSeconds(60)))
        assertEquals("Ingen Live Update planerad", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun vantandeLiveActivityVisarSinStarttid() {
        val schedules = mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))))
        val start = StockholmClock.dateOn(day("2026-11-08"), 1050)
        // Tiden kommer från Live Updaten, som kan ha lagts in före en ändring av inställningen.
        // Notisen kommer efter starten och nämns efter Live Updaten.
        val content = HomeContent.make(listOf(on), schedules, ReminderSettings(reminderMinutes = 1200, liveActivityOn = true), now, liveActivity = activity(pending = true, start = start))
        assertEquals("Live Update söndag kl. 17:30, notis söndag kl. 20:00", assertNotNull(content.primary).reminder?.detail)
        val same = HomeContent.make(listOf(on), schedules, ReminderSettings(reminderMinutes = 1050, liveActivityOn = true), now, liveActivity = activity(pending = true, start = start))
        assertEquals("Notis och Live Update söndag kl. 17:30", assertNotNull(same.primary).reminder?.detail)
    }

    @Test
    fun fotenVisarBådaNotistiderna() {
        val schedules = mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-16", listOf("rest")))))
        val both = ReminderSettings(eveningOn = true, morningOn = true, reminderMinutes = 900, morningMinutes = 360)
        assertEquals("Påminnelse söndag kl. 15:00 och måndag kl. 06:00", assertNotNull(HomeContent.make(listOf(on), schedules, both, now).primary?.reminder).line)
        // När kvällens tid har passerat återstår bara morgonens för samma tömning.
        val sundayAfternoon = StockholmClock.dateOn(day("2026-11-08"), 16 * 60)
        assertEquals("Påminnelse måndag kl. 06:00", assertNotNull(HomeContent.make(listOf(on), schedules, both, sundayAfternoon).primary?.reminder).line)
    }

    @Test
    fun fotenVisarBådaTidernaMedLiveActivity() {
        val schedules = mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))))
        val start = StockholmClock.dateOn(day("2026-11-08"), 900)
        val both = ReminderSettings(eveningOn = true, morningOn = true, reminderMinutes = 900, morningMinutes = 360, liveActivityOn = true)
        val content = HomeContent.make(listOf(on), schedules, both, now, liveActivity = activity(pending = true, start = start))
        assertEquals("Notis och Live Update söndag kl. 15:00, notis måndag kl. 06:00", assertNotNull(content.primary).reminder?.detail)
        // Live Update på morgonen och notis bara på kvällen: båda nämns, var för sig.
        val morningStart = StockholmClock.dateOn(day("2026-11-09"), 360)
        val eveningOnly = ReminderSettings(reminderMinutes = 900, liveActivityTiming = se.hardyson.sophamtning.core.storage.ReminderTiming.SameMorning, liveActivityOn = true)
        val split = HomeContent.make(listOf(on), schedules, eveningOnly, now, liveActivity = activity(pending = true, start = morningStart))
        assertEquals("Notis söndag kl. 15:00, Live Update måndag kl. 06:00", assertNotNull(split.primary).reminder?.detail)
    }

    @Test
    fun baraLiveActivityNamnerBaraLiveActivity() {
        val start = StockholmClock.dateOn(day("2026-11-08"), 1050)
        val content = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivity = activity(pending = true, start = start))
        assertEquals("Live Update söndag kl. 17:30", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun startadLiveActivityVisasSomPagaende() {
        val content = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivity = activity(pending = false, start = now))
        assertEquals("Live Update visas nu", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun utanAktivitetVisasNotisenSomForut() {
        // Starten misslyckades eller ska inte ske, och notisen är det som faktiskt påminner.
        val content = HomeContent.make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivity = null)
        assertEquals("Söndag kl. 18:00", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun avstangdaLiveActivitiesSagsPaKortet() {
        val content = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivitiesEnabled = false)
        assertEquals("Live Updates är avstängda", assertNotNull(content.primary).reminder?.detail)
    }

    @Test
    fun notisValetSomIosInteTillaterVisasSomAv() {
        val schedules = mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest")))))
        assertNull(assertNotNull(HomeContent.make(listOf(on), schedules, ReminderSettings(), now, remindersAllowed = false).primary).reminder?.detail)
        assertEquals("Ingen Live Update planerad", assertNotNull(HomeContent.make(listOf(on), schedules, ReminderSettings(liveActivityOn = true), now, remindersAllowed = false).primary).reminder?.detail)
    }

    @Test
    fun voiceOverAtgardenForPaminnelsenHarSammaNamnSomValet() {
        assertEquals("Slå på påminnelse", HomeContent.reminderActionTitle(isOn = false))
        assertEquals("Stäng av påminnelse", HomeContent.reminderActionTitle(isOn = true))
    }

    @Test
    fun saknatSchemaVisasInteSomAttAdressenSaknas() {
        assertEquals(HomeContent.Status.Loading, assertNotNull(make(listOf(home), emptyMap()).primary).status)
        val failed = assertNotNull(make(listOf(home), mapOf(home.key to CachedSchedule(response = null, fetchedAt = null, lastAttemptAt = now, lastError = ApiError.Network))).primary)
        assertEquals(HomeContent.Status.Failed(ApiError.Network), failed.status)
        assertEquals("Kunde inte hämta schemat", failed.summary)
    }

    @Test
    fun felEfterTidigareLyckatSvarBehallerSchemaOchNoterarFelet() {
        val primary = assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))), lastError = ApiError.SourceUnavailable))).primary)
        assertIs<HomeContent.Status.Upcoming>(primary.status)
        assertTrue(primary.refreshFailed)
    }

    @Test
    fun okandFraktionVisasMedIdSomNamn() {
        val unknown = homeSchedule(listOf(event("2026-11-09", listOf("tradgard"))), fractions = emptyMap())
        assertEquals(listOf("tradgard"), upcoming(make(listOf(home), mapOf(home.key to unknown)).primary).fractions.map { it.info.name })
    }

    @Test
    fun utanHuvudmarkeringFarForstaAdressenHuvudkortet() {
        assertEquals("Hemma", assertNotNull(make(listOf(home.copy(isPrimary = false), cabin), emptyMap()).primary).title)
    }

    @Test
    fun adressSomInteFinnsLangreFarEgenText() {
        val gone = make(listOf(home), mapOf(home.key to CachedSchedule(response = null, fetchedAt = null, lastAttemptAt = now, lastError = ApiError.NotFound)))
        assertEquals("Adressen hittas inte längre", assertNotNull(gone.primary).summary)
    }

    @Test
    fun radMedMisslyckadUppdateringNamnerDetISinEtikett() {
        val content = make(listOf(home, cabin), mapOf(
            home.key to schedule(listOf(event("2026-11-09", listOf("rest")))),
            cabin.key to schedule(listOf(event("2026-11-18", listOf("plast"))), lastError = ApiError.Network),
        ))
        assertTrue(content.others[0].accessibilityLabel.contains("Kunde inte uppdateras"))
    }

    @Test fun tomningIDagUtanSenareHamtningGerNeutralPaminnelsetext() = assertNull(reminder(listOf(event("2026-11-06", listOf("rest"))), now))

    @Test
    fun tomningIDagRaknarPaminnelsenFranNastaHamtning() {
        assertEquals("Söndag kl. 18:00", reminder(listOf(event("2026-11-06", listOf("rest")), event("2026-11-09", listOf("mat"))), now))
    }

    @Test fun tomningIMorgonForeKlockan18GerPaminnelseSammaKvall() = assertEquals("Fredag kl. 18:00", reminder(listOf(event("2026-11-07", listOf("rest"))), now))

    @Test
    fun tomningIMorgonEfter18GerNeutralTextOmIngenSenareFinns() {
        val evening = StockholmClock.dateOn(today, 19 * 60)
        assertNull(reminder(listOf(event("2026-11-07", listOf("rest"))), evening))
        assertEquals("Onsdag kl. 18:00", reminder(listOf(event("2026-11-07", listOf("rest")), event("2026-11-12", listOf("mat"))), evening))
    }

    // MARK: Adress och plats på var sin rad

    @Test
    fun adressenOchPlatsenPaVarSinRad() {
        val street = saved("s", name = "Hemma", street = "Storgatan 12", locality = "Krylbo", primary = true)
        // Ett område har hela namnet som gata och ingen ort, som i API:t.
        val area = saved("a", name = "Stugan", street = "Kaplansgården, Jularbo m.fl.", locality = "", primary = false)
        val content = make(listOf(street, area), emptyMap())
        assertEquals(HomeContent.AddressLines(address = "Storgatan 12", place = "Krylbo · Avesta kommun"), assertNotNull(content.primary).lines)
        assertEquals(HomeContent.AddressLines(address = "Kaplansgården, Jularbo m.fl.", place = "Avesta kommun"), content.others[0].lines)
    }

    @Test
    fun kommunenVisasInteNarDenArSammaSomOrten() {
        val same = saved("u", name = "Jobbet", street = "Stationsgatan 12", locality = "Uppsala", kommun = "Uppsala kommun", primary = true)
        assertEquals(HomeContent.AddressLines(address = "Stationsgatan 12", place = "Uppsala"), assertNotNull(make(listOf(same), emptyMap()).primary).lines)
        // Utan hänsyn till skiftläge.
        val shouting = saved("v", name = "Jobbet", street = "Stationsgatan 12", locality = "UPPSALA", kommun = "Uppsala kommun", primary = true)
        assertEquals("UPPSALA", assertNotNull(make(listOf(shouting), emptyMap()).primary).lines.place)
    }

    @Test
    fun utanGataFinnsBaraPlatsen() {
        val noStreet = saved("t", name = "Hemma", street = "", locality = "Krylbo", primary = true)
        assertEquals(HomeContent.AddressLines(address = "", place = "Krylbo · Avesta kommun"), assertNotNull(make(listOf(noStreet), emptyMap()).primary).lines)
        val onlyKommun = saved("k", name = "Hemma", street = " ", locality = "", primary = true)
        assertEquals(HomeContent.AddressLines(address = "", place = "Avesta kommun"), assertNotNull(make(listOf(onlyKommun), emptyMap()).primary).lines)
    }

    @Test
    fun gatanUpprepasInteNarNamnetArDetsamma() {
        // Ett område sparas med sitt namn, som också är gatan. Bara platsen står under namnet.
        val area = saved("r", name = "Ringänget, Veddarsbo m.fl.", street = "Ringänget, Veddarsbo m.fl.", locality = "", primary = true)
        val entry = assertNotNull(make(listOf(area), emptyMap()).primary)
        assertEquals(HomeContent.AddressLines(address = "", place = "Avesta kommun"), entry.lines)
        assertTrue(entry.accessibilityLabel.startsWith("Ringänget, Veddarsbo m.fl., Avesta kommun"))
        // Samma sak med en gata med nummer, oavsett skiftläge och mellanslag runt omkring.
        val street = saved("s", name = "testgatan 3", street = " Testgatan 3 ", locality = "Uppsala", kommun = "Uppsala kommun", primary = true)
        assertEquals(HomeContent.AddressLines(address = "", place = "Uppsala"), assertNotNull(make(listOf(street), emptyMap()).primary).lines)
        // Ett eget namn ger gatan på raden under, som förut.
        val named = saved("n", name = "Hemma", street = "Testgatan 3", locality = "Uppsala", kommun = "Uppsala kommun", primary = true)
        assertEquals("Testgatan 3", assertNotNull(make(listOf(named), emptyMap()).primary).lines.address)
    }

    @Test
    fun helaSchematVisarAlltidAdressenMedNamn() {
        // Ett område som sparats med sitt namn: namnet står en gång, som namn, och platsen under.
        val area = saved("r", name = "Ringänget, Veddarsbo m.fl.", street = "Ringänget, Veddarsbo m.fl.", locality = "", primary = true)
        val areaLines = HomeContent.namedLines(area)
        assertEquals(HomeContent.AddressLines(name = "Ringänget, Veddarsbo m.fl.", address = "", place = "Avesta kommun"), areaLines)
        assertEquals("Ringänget, Veddarsbo m.fl., Avesta kommun", areaLines.accessibilityLabel)
        // En gata som sparats med gatan som namn, som alla adresser utom den första.
        val street = saved("s", name = "Storgatan 12", street = "Storgatan 12", locality = "Krylbo", primary = false)
        val streetLines = HomeContent.namedLines(street)
        assertEquals(HomeContent.AddressLines(name = "Storgatan 12", address = "", place = "Krylbo · Avesta kommun"), streetLines)
        assertEquals("Storgatan 12, Krylbo, Avesta kommun", streetLines.accessibilityLabel)
        // Ett eget namn: namnet, gatan och platsen.
        val named = saved("n", name = "Hemma", street = "Storgatan 12", locality = "Krylbo", primary = true)
        val namedLines = HomeContent.namedLines(named)
        assertEquals(HomeContent.AddressLines(name = "Hemma", address = "Storgatan 12", place = "Krylbo · Avesta kommun"), namedLines)
        assertEquals("Hemma, Storgatan 12, Krylbo, Avesta kommun", namedLines.accessibilityLabel)
        // Ett område med eget namn.
        val stugan = saved("a", name = "Stugan", street = "Kaplansgården, Jularbo m.fl.", locality = "", primary = false)
        assertEquals(HomeContent.AddressLines(name = "Stugan", address = "Kaplansgården, Jularbo m.fl.", place = "Avesta kommun"), HomeContent.namedLines(stugan))
    }

    @Test
    fun adressenSynsMinstEnGangOverallt() {
        val addresses = listOf(
            saved("r", name = "Ringänget, Veddarsbo m.fl.", street = "Ringänget, Veddarsbo m.fl.", locality = "", primary = true),
            saved("s", name = "Storgatan 12", street = "Storgatan 12", locality = "Krylbo", primary = false),
            saved("n", name = "Hemma", street = "Bergsvägen 4", locality = "Horndal", primary = false),
        )
        val content = make(addresses, emptyMap())
        val entries = listOf(assertNotNull(content.primary)) + content.others
        for ((entry, address) in entries.zip(addresses)) {
            val plain = address.displayName
            assertEquals(plain, entry.title)
            assertTrue(entry.accessibilityLabel.startsWith(plain), plain)
            val street = address.street
            assertTrue(entry.title == street || entry.lines.accessibilityLabel.startsWith(street.replace(" ", " ")), plain)
            val full = HomeContent.namedLines(address).accessibilityLabel
            assertTrue(full.startsWith(plain), plain)
            assertTrue(full.contains(street), plain)
            assertTrue(full.endsWith("kommun"), plain)
        }
    }

    @Test
    fun voiceOverLaserAdressOchPlatsUtanMittpunkt() {
        assertEquals("Storgatan 12, Krylbo, Avesta kommun", HomeContent.AddressLines(address = "Storgatan 12", place = "Krylbo · Avesta kommun").accessibilityLabel)
        assertEquals("Kaplansgården, Jularbo m.fl., Avesta kommun", HomeContent.AddressLines(address = "Kaplansgården, Jularbo m.fl.", place = "Avesta kommun").accessibilityLabel)
        assertEquals("Uppsala", HomeContent.AddressLines(address = "", place = "Uppsala").accessibilityLabel)
    }

    @Test
    fun kommunensKortaNamnSomISokningen() {
        assertEquals("Avesta", shortKommunName("Avesta kommun"))
        assertEquals("Region Gotland", shortKommunName("Region Gotland"))
    }

    @Test
    fun kommunVisasMedHelaNamnet() {
        assertEquals("Säters kommun", kommunDisplayName("Säters kommun"))
        assertEquals("Avesta kommun", kommunDisplayName(" Avesta kommun "))
        assertEquals("Region Gotland", kommunDisplayName("Region Gotland"))
    }

    @Test
    fun kommunenUppreparOrtenAvenIGenitiv() {
        assertTrue(kommunRepeatsLocality("Säters kommun", "Säter"))
        assertTrue(kommunRepeatsLocality("Stockholms kommun", "Stockholm"))
        assertTrue(kommunRepeatsLocality("Falu kommun", "Falun"))
        assertTrue(kommunRepeatsLocality("Uppsala kommun", "Uppsala"))
        assertTrue(kommunRepeatsLocality("Uppsala kommun", "uppsala"))
        assertFalse(kommunRepeatsLocality("Avesta kommun", "Krylbo"))
        assertFalse(kommunRepeatsLocality("Avesta kommun", ""))
        assertFalse(kommunRepeatsLocality("Säters kommun", "Sät"))
    }

    @Test
    fun ortOchKommunSomPaKortensUndertitel() {
        // Sökträffens rad: kommunen döljs när den bara upprepar orten, annars står hela namnet efter en mittpunkt.
        assertEquals("Uppsala", localityAndKommun("Uppsala", "Uppsala kommun"))
        assertEquals("Säter", localityAndKommun("Säter", "Säters kommun"))
        assertEquals("Krylbo · Avesta kommun", localityAndKommun("Krylbo", "Avesta kommun"))
        assertEquals("Avesta kommun", localityAndKommun(" ", "Avesta kommun"))
        assertEquals("Krylbo", localityAndKommun("Krylbo", ""))
    }

    @Test
    fun undertitelnDoljerKommunenSomBaraUppreparOrten() {
        val sater = saved("s", name = "Hemma", street = "Storgatan 3", locality = "Säter", kommun = "Säters kommun", primary = true)
        val stockholm = saved("t", name = "Jobbet", street = "Drottninggatan 1", locality = "Stockholm", kommun = "Stockholms kommun", primary = false)
        val falun = saved("f", name = "Stugan", street = "Åsgatan 5", locality = "Falun", kommun = "Falu kommun", primary = false)
        val content = make(listOf(sater, stockholm, falun), emptyMap())
        assertEquals("Säter", assertNotNull(content.primary).lines.place)
        assertEquals(listOf("Stockholm", "Falun"), content.others.map { it.lines.place })
    }

    @Test
    fun mittpunktenBorjarAldrigEnRad() {
        val content = make(listOf(home, cabin), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))), cabin.key to schedule(listOf(event("2026-11-18", listOf("plast"))))))
        for (entry in listOf(assertNotNull(content.primary)) + content.others) {
            assertFalse(entry.lines.place.contains(" ·"))
            assertFalse(entry.summary.contains(" ·"))
        }
        // Gatunamn och nummer hålls ihop, men husets bokstav får stå kvar.
        assertEquals("Storgatan 12 B", assertNotNull(content.primary).lines.address)
    }

    // MARK: Påminnelse på raderna

    @Test
    fun radMedNotisPaVisarPlaneradPaminnelse() {
        val other = saved("o", name = "Stugan", street = "Bergsvägen 4", locality = "Horndal", primary = false, notifications = true)
        val content = make(listOf(home, other), mapOf(home.key to schedule(tuesdayPickup), other.key to schedule(tuesdayPickup)))
        assertEquals(HomeContent.RowReminder.Scheduled("Påminnelse tisdag kl. 18:00"), content.others[0].rowReminder)
        assertEquals("Påminnelse tisdag kl. 18:00", content.others[0].rowReminder?.text)
        // Raden har sitt läge, och huvudkortets text är bara huvudkortets.
        assertNull(content.others[0].reminder)
        assertNull(content.primary?.rowReminder)
    }

    @Test
    fun radMedNotisAvVisarIngenPaminnelse() {
        assertNull(make(listOf(home, cabin), mapOf(home.key to schedule(tuesdayPickup), cabin.key to schedule(tuesdayPickup))).others[0].rowReminder)
    }

    @Test
    fun radMedNekadeNotiserSagerAttNotiserArAvstangda() {
        val other = saved("o", name = "Stugan", street = "Bergsvägen 4", locality = "Horndal", primary = false, notifications = true)
        val content = HomeContent.make(listOf(on, other), mapOf(on.key to schedule(tuesdayPickup), other.key to schedule(tuesdayPickup)), ReminderSettings(), now, remindersAllowed = false, remindersDenied = true)
        assertEquals(HomeContent.RowReminder.Denied, content.others[0].rowReminder)
        assertEquals("Notiser är avstängda för appen", content.others[0].rowReminder?.text)
        // Huvudkortets reglage är av och säger att notiserna är avstängda.
        assertEquals(false, content.primary?.reminder?.isOn)
        assertEquals(true, content.primary?.reminder?.isDenied)
    }

    @Test
    fun radMedNotisAvOchNekadeNotiserVisarIngenting() {
        val content = HomeContent.make(listOf(home, cabin), mapOf(home.key to schedule(tuesdayPickup), cabin.key to schedule(tuesdayPickup)), ReminderSettings(), now, remindersAllowed = false, remindersDenied = true)
        assertNull(content.others[0].rowReminder)
    }

    @Test
    fun radNarNotiserInteArBestamdaVisarPlaneradPaminnelse() {
        // Systemet har inte frågat än (till exempel efter en ominstallation): inte nekat, så raden visar det planerade läget.
        val other = saved("o", name = "Stugan", street = "Bergsvägen 4", locality = "Horndal", primary = false, notifications = true)
        val content = HomeContent.make(listOf(home, other, cabin), mapOf(home.key to schedule(tuesdayPickup), other.key to schedule(tuesdayPickup), cabin.key to schedule(tuesdayPickup)), ReminderSettings(), now, remindersAllowed = false, remindersDenied = false)
        assertEquals(HomeContent.RowReminder.Scheduled("Påminnelse tisdag kl. 18:00"), content.others[0].rowReminder)
        // Notis av för adressen: ingenting.
        assertNull(content.others[1].rowReminder)
    }

    @Test
    fun radensPaminnelseHarIngenLiveActivity() {
        // Live Update gäller bara huvudadressen. Raden visar notisen även när Live Update är på eller har fel.
        val other = saved("o", name = "Stugan", street = "Bergsvägen 4", locality = "Horndal", primary = false, notifications = true)
        val pending = activity(pending = true, start = StockholmClock.dateOn(day("2026-11-08"), 17 * 60 + 30))
        val content = HomeContent.make(
            listOf(home, other), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))), other.key to schedule(tuesdayPickup)),
            ReminderSettings(liveActivityOn = true), now, liveActivity = pending, liveActivityError = "Kunde inte läggas in.", reserveAt = now + Duration.ofHours(1),
        )
        assertEquals(HomeContent.RowReminder.Scheduled("Påminnelse tisdag kl. 18:00"), content.others[0].rowReminder)
    }

    @Test
    fun radenRaknarFranNastaKvallSomInteHarPasserat() {
        // Tömning i morgon lördag, och kvällen före (fredag 18:00) har passerat: samma text som huvudkortet.
        val evening = StockholmClock.dateOn(today, 19 * 60)
        val other = saved("o", name = "Stugan", street = "Bergsvägen 4", locality = "Horndal", primary = false, notifications = true)
        val events = listOf(event("2026-11-07", listOf("rest")), event("2026-11-11", listOf("mat")))
        val content = make(listOf(home, other), mapOf(home.key to schedule(events), other.key to schedule(events)), time = evening)
        assertEquals(HomeContent.RowReminder.Missed("Tömning i morgon. Påminnelsen för i kväll har redan passerat."), content.others[0].rowReminder)
        // Tömning i dag: kvällen före har passerat, och påminnelsen gäller tömningen på onsdag.
        val todayFirst = make(listOf(home, other), mapOf(home.key to schedule(tuesdayPickup), other.key to schedule(listOf(event("2026-11-06", listOf("rest")), event("2026-11-11", listOf("mat"))))))
        assertEquals(HomeContent.RowReminder.Scheduled("Påminnelse tisdag kl. 18:00"), todayFirst.others[0].rowReminder)
        // Ingen senare tömning: samma neutrala text som huvudkortet.
        val onlyToday = make(listOf(home, other), mapOf(home.key to schedule(tuesdayPickup), other.key to schedule(listOf(event("2026-11-06", listOf("rest"))))))
        assertEquals(HomeContent.RowReminder.Scheduled("Påminnelser på"), onlyToday.others[0].rowReminder)
    }

    @Test
    fun radUtanKommandeHamtningHarIngenPaminnelse() {
        val other = saved("o", name = "Stugan", street = "Bergsvägen 4", locality = "Horndal", primary = false, notifications = true)
        assertNull(make(listOf(home, other), mapOf(home.key to schedule(tuesdayPickup), other.key to schedule(listOf(event("2026-11-02", listOf("rest")))))).others[0].rowReminder)
    }

    // MARK: Reglaget för påminnelsen på huvudkortet

    @Test
    fun reglagetArAvUtanPaminnelse() {
        val reminder = assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))))).primary?.reminder)
        assertEquals(HomeContent.PrimaryReminder(isOn = false, isDenied = false, title = "Påminn mig", detail = null), reminder)
    }

    @Test
    fun reglagetArPaMedTidenForPaminnelsenUnder() {
        val reminder = assertNotNull(make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest")))))).primary?.reminder)
        assertTrue(reminder.isOn)
        assertFalse(reminder.isDenied)
        assertEquals("Påminn mig", reminder.title)
        assertEquals("Söndag kl. 18:00", reminder.detail)
    }

    @Test
    fun nekadeNotiserGerAvstangtReglageOchText() {
        val denied = HomeContent.make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(), now, remindersAllowed = false, remindersDenied = true)
        assertEquals(
            HomeContent.PrimaryReminder(isOn = false, isDenied = true, title = "Notiser är avstängda för appen", detail = null, showsDeniedNotice = true),
            assertNotNull(denied.primary?.reminder),
        )
        // Också när valet inte är på vet modellen att systemet nekar, men kortet visar då ingen ruta.
        val off = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(), now, remindersAllowed = false, remindersDenied = true)
        assertTrue(assertNotNull(off.primary?.reminder).isDenied)
    }

    @Test
    fun ejFragadeNotiserVisasSomAvUtanNekat() {
        val reminder = assertNotNull(HomeContent.make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(), now, remindersAllowed = false).primary?.reminder)
        assertFalse(reminder.isOn)
        assertFalse(reminder.isDenied)
        assertEquals("Påminn mig", reminder.title)
    }

    @Test
    fun liveActivityVisasIUndertexten() {
        val start = StockholmClock.dateOn(day("2026-11-08"), 17 * 60 + 30)
        val reminder = assertNotNull(HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivity = activity(pending = true, start = start)).primary?.reminder)
        assertFalse(reminder.isOn)
        assertEquals("Live Update söndag kl. 17:30", reminder.detail)
    }

    @Test
    fun passeradPaminnelseVisasIUndertexten() {
        val missed = "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
        val content = HomeContent.make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(), now, missedReminder = missed)
        assertEquals(missed, assertNotNull(content.primary?.reminder).detail)
    }

    @Test
    fun raderOchKortUtanHamtningHarInteReglaget() {
        val content = make(listOf(home, cabin), mapOf(home.key to schedule(listOf(event("2026-11-02", listOf("rest")))), cabin.key to schedule(listOf(event("2026-11-18", listOf("plast"))))))
        assertNull(assertNotNull(content.primary).reminder)
        assertNull(content.others[0].reminder)
    }

    @Test
    fun reglagetUppreparInteAttPaminnelserArPa() {
        // Tömning i dag och ingen senare: reglaget säger redan att påminnelsen är på, så ingen undertext.
        val reminder = assertNotNull(make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-06", listOf("rest")))))).primary?.reminder)
        assertTrue(reminder.isOn)
        assertEquals("Påminn mig", reminder.title)
        assertNull(reminder.detail)
    }

    // MARK: Schemat slutar

    @Test
    fun hemkortetVisarNarSchematSlutarInomFjortonDagar() {
        // Fredag 6 november: 20 november är 14 dagar kvar, 21 november 15.
        assertEquals("Schemat slutar 20 nov", endingHome(endingSchedule("2026-11-20")).primary?.scheduleEnding?.shortText)
        assertNull(endingHome(endingSchedule("2026-11-21")).primary?.scheduleEnding)
        assertEquals(0, endingHome(endingSchedule("2026-11-06")).primary?.scheduleEnding?.daysLeft)
        assertNull(endingHome(endingSchedule("2026-11-05")).primary?.scheduleEnding)
    }

    @Test
    fun hemkortetVisarInteRadenForLivekallorEllerUtanSchema() {
        assertNull(endingHome(endingSchedule(null)).primary?.scheduleEnding)
        assertNull(endingHome(null).primary?.scheduleEnding)
    }

    @Test
    fun hemkortetVisarInteRadenUtanKommandeHamtningar() {
        assertNull(endingHome(endingSchedule("2026-11-10", events = listOf(event("2026-11-01", listOf("rest"))))).primary?.scheduleEnding)
    }

    @Test
    fun hemkortetVisarRadenOckssaMedEttSparatSchemaEfterFel() {
        assertNotNull(endingHome(endingSchedule("2026-11-20", lastError = ApiError.SourceUnavailable)).primary?.scheduleEnding)
    }

    @Test
    fun radenUnderFlerAdresserHarIngenSchemaslutarOchVoiceOverLaserDenInte() {
        val other = savedAddress(key = AddressKey(source = "x", id = "b"), isPrimary = false)
        val primary = savedAddress(key = AddressKey(source = "x", id = "a"), isPrimary = true)
        val ending = endingSchedule("2026-11-20")
        val content = HomeContent.make(listOf(primary, other), mapOf(primary.key to ending, other.key to ending), ReminderSettings(), now)
        assertNotNull(content.primary?.scheduleEnding)
        assertTrue(assertNotNull(content.primary).accessibilityLabel.contains("Schemat slutar"))
        assertNull(content.others[0].scheduleEnding)
        assertFalse(content.others[0].accessibilityLabel.contains("Schemat slutar"))
    }

    // MARK: Utställt

    /** Android: utan påminnelser finns varken knapp eller rad. */
    @Test
    fun utanHushallIngenRad() {
        val content = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(), sunday)
        assertNull(content.primary?.placedOut)
    }

    @Test
    fun ingaKommandeHamtningarArNeutral() {
        assertEquals(HomeContent.Entry.SummaryTone.Neutral, assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-02", listOf("rest")))))).primary).summaryTone)
        assertEquals(HomeContent.Entry.SummaryTone.Date, assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))))).primary).summaryTone)
        assertEquals(HomeContent.Entry.SummaryTone.Neutral, assertNotNull(make(listOf(home), emptyMap()).primary).summaryTone)
        val failed = make(listOf(home), mapOf(home.key to CachedSchedule(response = null, fetchedAt = null, lastAttemptAt = now, lastError = ApiError.Network)))
        assertEquals(HomeContent.Entry.SummaryTone.Warning, assertNotNull(failed.primary).summaryTone)
    }

    // MARK: Påminnelsen i huvudkortets fot

    @Test
    fun paminnelsenArEnRadIKortetsFot() {
        val reminder = assertNotNull(make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest")))))).primary?.reminder)
        assertEquals("Påminnelse söndag kl. 18:00", reminder.line)
        assertFalse(reminder.showsDeniedNotice)
    }

    @Test
    fun avstangdPaminnelseGerIngenRadIFoten() {
        val reminder = assertNotNull(make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")))))).primary?.reminder)
        assertNull(reminder.line)
        assertFalse(reminder.showsDeniedNotice)
    }

    @Test
    fun liveActivityArEnRadIFotenAvenMedNotisenAv() {
        val start = StockholmClock.dateOn(day("2026-11-08"), 17 * 60 + 30)
        val content = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(liveActivityOn = true), now, liveActivity = activity(pending = true, start = start))
        assertEquals("Live Update söndag kl. 17:30", assertNotNull(content.primary?.reminder).line)
    }

    @Test
    fun rutanOmNekadeNotiserVisasBaraNarPaminnelsenArPa() {
        val denied = HomeContent.make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(), now, remindersAllowed = false, remindersDenied = true)
        val wanted = assertNotNull(denied.primary?.reminder)
        assertTrue(wanted.showsDeniedNotice)
        assertNull(wanted.line)
        // Påminnelsen är av: inget har slutat fungera, så ingen ruta och ingen rad.
        val off = HomeContent.make(listOf(home), mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(), now, remindersAllowed = false, remindersDenied = true)
        val notWanted = assertNotNull(off.primary?.reminder)
        assertFalse(notWanted.showsDeniedNotice)
        assertNull(notWanted.line)
    }

    @Test
    fun ejFragadeNotiserGerIngenRadOchIngenRuta() {
        val reminder = assertNotNull(HomeContent.make(listOf(on), mapOf(on.key to schedule(listOf(event("2026-11-09", listOf("rest"))))), ReminderSettings(), now, remindersAllowed = false).primary?.reminder)
        assertNull(reminder.line)
        assertFalse(reminder.showsDeniedNotice)
    }

    // MARK: Adress och plats på en rad

    @Test
    fun adressOchPlatsStarPaEnRad() {
        assertEquals("Storgatan 12, Krylbo · Avesta kommun", HomeContent.AddressLines(address = "Storgatan 12", place = "Krylbo · Avesta kommun").singleLine)
        assertEquals("Kaplansgården, Jularbo m.fl., Avesta kommun", HomeContent.AddressLines(address = "Kaplansgården, Jularbo m.fl.", place = "Avesta kommun").singleLine)
        // Utan gata står bara platsen, och utan plats bara gatan.
        assertEquals("Uppsala", HomeContent.AddressLines(address = "", place = "Uppsala").singleLine)
        assertEquals("Testgatan 1", HomeContent.AddressLines(address = "Testgatan 1", place = "").singleLine)
    }

    /** Android: min egen utställda för en annan adress, i stället för hushållets bock. Raden visar "Kärlen är utställda". */
    @Test
    fun listradenVisarUtstalltForEnAnnanAdress() {
        val mark = PlacedOut(cabin.key, monday)
        val at = StockholmClock.dateOn(day("2026-11-08"), 19 * 60 + 42)
        val content = HomeContent.make(
            listOf(home, cabin),
            mapOf(home.key to schedule(listOf(event("2026-11-10", listOf("rest")))), cabin.key to schedule(listOf(event("2026-11-09", listOf("rest"))))),
            ReminderSettings(), sunday, ownPlacedOut = setOf(mark), placedOutTimes = mapOf(mark to at),
        )
        val row = assertNotNull(content.others.firstOrNull { it.key == cabin.key }?.placedOut)
        assertEquals("Kärlen är utställda", row.placedOutText)
        assertEquals("Utställt", row.placedOutTitle)
        assertEquals("av dig · kl. 19:42", row.placedOutSubtitle)
    }

    @Test
    fun huvudadressMedNotiserFarKnappenStallUtPaTomningsdagen() {
        val withReminders = saved("hemma", name = "Hemma", street = "Storgatan 3", locality = "Avesta", primary = true, notifications = true)
        assertEquals(true, assertNotNull(make(listOf(withReminders), mapOf(withReminders.key to schedule(listOf(event("2026-11-06", listOf("rest")))))).primary).placedOut?.showsButton)
    }

    @Test
    fun huvudadressMedLiveActivityFarKnappenStallUt() {
        val off = saved("hemma", name = "Hemma", street = "Storgatan 3", locality = "Avesta", primary = true)
        val primary = assertNotNull(make(listOf(off), mapOf(off.key to schedule(listOf(event("2026-11-07", listOf("rest"))))), ReminderSettings(liveActivityOn = true)).primary)
        assertEquals(true, primary.placedOut?.showsButton)
    }

    @Test
    fun utanPaminnelserFarHuvudadressenIngenKnapp() {
        val off = saved("hemma", name = "Hemma", street = "Storgatan 3", locality = "Avesta", primary = true)
        assertNull(assertNotNull(make(listOf(off), mapOf(off.key to schedule(listOf(event("2026-11-06", listOf("rest")))))).primary).placedOut)
    }

    @Test
    fun radUtanNotiserFarIngenKnappFastLiveActivityArPa() {
        val main = saved("hemma", name = "Hemma", street = "Storgatan 3", locality = "Avesta", primary = true)
        val other = saved("jobbet", name = "Jobbet", street = "Torget 1", locality = "Avesta", primary = false)
        val content = make(listOf(main, other), mapOf(main.key to schedule(listOf(event("2026-11-06", listOf("rest")))), other.key to schedule(listOf(event("2026-11-06", listOf("rest"))))), ReminderSettings(liveActivityOn = true))
        assertNull(content.others.firstOrNull()?.placedOut)
    }

    // MARK: Utställda tömningar hoppas över i påminnelsetexten

    @Test
    fun morgonpaminnelsenLovasInteNarTomningenArUtstalld() {
        // Kvällens tid har passerat. Utan bock är morgonen nästa.
        assertEquals("Påminnelse måndag kl. 06:00", footLine())
        // Utställt tar bort morgonens notis, så raden går vidare till nästa tömning och dess båda tider.
        assertEquals("Påminnelse tisdag kl. 18:00 och onsdag kl. 06:00", footLine(placedOut = setOf(PlacedOut(home.key, monday))))
    }

    @Test
    fun fotenEfterUtställtMedVäntandeAktivitet() {
        val schedules = mapOf(home.key to schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-16", listOf("rest")))))
        val start = StockholmClock.dateOn(day("2026-11-08"), 900)
        val both = ReminderSettings(eveningOn = true, morningOn = true, reminderMinutes = 900, morningMinutes = 360, liveActivityOn = true)
        val mark = PlacedOut(home.key, day("2026-11-09"))
        val content = HomeContent.make(listOf(on), schedules, both, now, liveActivity = activity(pending = true, start = start), ownPlacedOut = setOf(mark))
        // Den utställda tömningens påminnelser och Live Update lovas inte. Foten går vidare till nästa tömning.
        // Nästa tömning är den 16:e, mer än en vecka bort, så datumen står med.
        assertEquals("Påminnelse söndag 15 nov kl. 15:00 och måndag 16 nov kl. 06:00", assertNotNull(content.primary?.reminder).line)
    }

    @Test
    fun fotenVisarDatumFrånEnVeckaBort() {
        // I dag är fredag 6 november. Torsdag 12 november är sex dagar bort, och veckodagen räcker.
        val near = HomeContent.make(listOf(on), mapOf(home.key to schedule(listOf(event("2026-11-13", listOf("rest"))))), ReminderSettings(reminderMinutes = 900), now)
        assertEquals("Påminnelse torsdag kl. 15:00", assertNotNull(near.primary?.reminder).line)
        // Fredag 13 november är en vecka bort, och då står datumet med.
        val far = HomeContent.make(listOf(on), mapOf(home.key to schedule(listOf(event("2026-11-14", listOf("rest"))))), ReminderSettings(eveningOn = true, morningOn = true, reminderMinutes = 900), now)
        assertEquals("Påminnelse fredag 13 nov kl. 15:00 och lördag 14 nov kl. 06:00", assertNotNull(far.primary?.reminder).line)
    }

    @Test
    fun fotenVisarDatumMedLiveActivity() {
        val start = StockholmClock.dateOn(day("2026-11-24"), 900)
        val la = ExistingActivity(
            id = "a", key = home.key, pickupDate = day("2026-11-25"),
            content = PickupActivityContent(addressName = "Hemma", dateText = "", shortDateText = "", fractions = emptyList(), estimated = false, warning = null),
            isPending = true, start = start,
        )
        val both = ReminderSettings(eveningOn = true, morningOn = true, reminderMinutes = 900, morningMinutes = 360, liveActivityOn = true)
        val content = HomeContent.make(listOf(on), mapOf(home.key to schedule(listOf(event("2026-11-25", listOf("rest"))))), both, now, liveActivity = la)
        assertEquals("Notis och Live Update tisdag 24 nov kl. 15:00, notis onsdag 25 nov kl. 06:00", assertNotNull(content.primary?.reminder).detail)
    }
}
