package se.hardyson.sophamtning.core.home

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.Deviation
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.api.SchedulePeriod
import se.hardyson.sophamtning.core.api.fixture
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.SavedAddress

private fun fixtureResponse(name: String): AddressResponse = ApiDecoding.addressResponse(fixture(name))

private val key = AddressKey(source = "uppsala", id = "a")
private val address = SavedAddress(
    key = key, url = "https://sopor.hardyson.se/api/v1/x", street = "Storgatan 2", locality = "Uppsala", kommun = "Uppsala kommun",
    detail = null, selection = "address", displayName = "Hemma", isPrimary = true, addedAt = Instant.EPOCH,
)
private val today = day("2026-11-06")
private val noon = StockholmClock.dateOn(day("2026-11-06"), 12 * 60)

private fun detail(schedule: CachedSchedule?, now: Instant = noon, source: String? = "Uppsala Vatten", address: SavedAddress = se.hardyson.sophamtning.core.home.address) =
    AddressDetail.make(address, schedule, ReminderSettings(), sourceName = source, now = now)

private fun event(iso: String, fractions: List<String>, estimated: Boolean = false, deviation: Deviation? = null, warning: String? = null) =
    PickupEvent(date = day(iso), fractions = fractions, estimated = estimated, deviation = deviation, warning = warning, labels = emptyMap())

private fun schedule(events: List<PickupEvent>, fractions: Map<String, FractionInfo>? = null, fetchedAt: Instant? = null, error: ApiError? = null): CachedSchedule {
    val base = fixtureResponse("adress")
    val response = base.copy(next = emptyList(), summary = "", events = events, bins = emptyList(), fractions = fractions ?: base.fractions, schedule = null, messages = emptyList())
    return CachedSchedule(response = response, fetchedAt = fetchedAt ?: noon, lastAttemptAt = noon, lastError = error)
}

private fun periodSchedule(events: List<PickupEvent>, until: String?, reason: String? = "Avesta Vatten publicerar hämtschemat ett år i taget."): CachedSchedule {
    val base = fixtureResponse("adress")
    val period = until?.let { SchedulePeriod(day(it), reason) }
    val response = base.copy(next = emptyList(), summary = "", events = events, bins = emptyList(), schedule = period, messages = emptyList())
    return CachedSchedule(response = response, fetchedAt = noon, lastAttemptAt = noon, lastError = null)
}

/** Fredag 6 november 2026 är i dag, så `until` 14 dagar bort är 20 november. */
private fun ending(untilDaysFromToday: Int?, events: List<PickupEvent> = listOf(event("2026-11-09", listOf("rest"))), reason: String? = "Avesta Vatten publicerar hämtschemat ett år i taget.", now: Instant = noon): AddressDetail {
    val until = untilDaysFromToday?.let { StockholmClock.today(now).plusDays(it).iso }
    return detail(periodSchedule(events, until, reason), now = now)
}

private fun reminderDetail(schedule: CachedSchedule?, notificationsOn: Boolean = false, isPrimary: Boolean = true, liveActivityOn: Boolean = false) =
    AddressDetail.make(address.copy(notificationsOn = notificationsOn, isPrimary = isPrimary), schedule, ReminderSettings(liveActivityOn = liveActivityOn), sourceName = "Uppsala Vatten", now = noon)

private val sunday = day("2026-11-08")
private fun sundayAt(hour: Int) = StockholmClock.dateOn(sunday, hour * 60)
private val bothOnMorningActivity = ReminderSettings(morningOn = true, liveActivityTiming = ReminderTiming.SameMorning, liveActivityOn = true)

private fun reminderRow(now: Instant, reserveAt: Instant? = null, settings: ReminderSettings = bothOnMorningActivity, placedOut: Set<PlacedOut> = emptySet()): String {
    val cached = schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-11", listOf("rest"))))
    return AddressDetail.make(address.copy(notificationsOn = true), cached, settings, sourceName = null, now = now, reserveAt = reserveAt, ownPlacedOut = placedOut).reminderText
}

/** AddressDetailTests på iOS, med raden för Utställt utan hushåll och Google Kalender i stället för Kalender. */
class AddressDetailTest {
    @Test
    fun sparatSchemaVisasMedNastaOchKarl() {
        val result = detail(schedule(listOf(event("2026-11-09", listOf("rest", "mat")), event("2026-11-12", listOf("papper"), estimated = true))))
        assertEquals(AddressDetail.Mode.Schedule, result.mode)
        assertNull(result.notice)
        assertEquals(day("2026-11-09"), result.next?.date)
        assertEquals(listOf("mat", "rest", "papper"), result.bins.map { it.id })
        assertEquals("Mån 9 nov", result.bins.firstOrNull { it.id == "rest" }?.dateText)
        assertEquals("om 3 dagar", result.bins.firstOrNull { it.id == "rest" }?.daysText)
        assertEquals("ca tors 12 nov", result.bins.firstOrNull { it.id == "papper" }?.dateText)
        assertEquals(listOf("Mån 9 nov", "ca tors 12 nov"), result.rows.map { it.dateText })
        assertEquals("Hemma", result.title)
        assertNotNull(result.webLink)
    }

    @Test
    fun fleraFraktionerSammaDagBlirEnRadMedAllaChips() {
        val result = detail(schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-09", listOf("mat", "rest"), warning = "Helgdag"))))
        assertEquals(1, result.rows.size)
        assertEquals(listOf("rest", "mat"), result.rows[0].fractions.map { it.id })
        assertEquals("Helgdag", result.rows[0].warning)
        assertEquals("Helgdag", result.nextWarning)
    }

    @Test
    fun avvikelseVisasSomFlyttadFranEllerOrsak() {
        val result = detail(schedule(listOf(
            event("2026-11-17", listOf("rest"), deviation = Deviation(day("2026-11-16"), "Helg")),
            event("2026-11-18", listOf("mat"), deviation = Deviation(null, "Julhelgen")),
            event("2026-11-19", listOf("glas"), deviation = Deviation(null, "  ")),
        )))
        assertEquals(listOf("Flyttad från mån 16 nov", "Julhelgen", null), result.rows.map { it.deviation })
    }

    @Test
    fun tomVarningVisasInte() {
        val result = detail(schedule(listOf(event("2026-11-09", listOf("rest"), warning = "  "))))
        assertNull(result.rows[0].warning)
        assertNull(result.nextWarning)
    }

    @Test
    fun passeradeDatumVisasInteIDetKommandeSchemat() {
        assertEquals(listOf("2026-11-06"), detail(schedule(listOf(event("2026-11-05", listOf("rest")), event("2026-11-06", listOf("mat"))))).rows.map { it.date.iso })
    }

    @Test
    fun tomtSchemaGerIngaKommandeHamtningarMedLank() {
        val result = detail(schedule(listOf(event("2026-10-01", listOf("rest")))))
        assertEquals(AddressDetail.Mode.NoUpcoming, result.mode)
        assertNull(result.next)
        assertTrue(result.rows.isEmpty())
        assertNotNull(result.webLink)
    }

    @Test
    fun okandFraktionIAdressvynFaarIdSomNamn() {
        val result = detail(schedule(listOf(event("2026-11-24", listOf("tradgard"))), fractions = emptyMap()))
        assertEquals("tradgard", result.rows[0].fractions[0].info.name)
        assertEquals("tradgard", result.bins[0].info.name)
    }

    @Test
    fun tekniskaFelUtanSchemaSagerInteAttAdressenSaknas() {
        for (error in listOf(ApiError.SourceUnavailable, ApiError.Network, ApiError.Unexpected(500))) {
            val result = detail(CachedSchedule(lastAttemptAt = noon, lastError = error))
            assertEquals(AddressDetail.Mode.Unavailable, result.mode, "$error")
            assertEquals(AddressDetail.Notice.SourceUnavailable, result.notice, "$error")
        }
    }

    @Test
    fun fyrahundrafyraPaSparadAdressSagerAttAdressenInteHittas() {
        val result = detail(CachedSchedule(lastAttemptAt = noon, lastError = ApiError.NotFound))
        assertEquals(AddressDetail.Mode.Unavailable, result.mode)
        assertEquals(AddressDetail.Notice.NotFound, result.notice)
    }

    @Test
    fun fyrahundrafyraMedSparatSchemaBehallerSchemat() {
        val result = detail(schedule(listOf(event("2026-11-09", listOf("rest"))), error = ApiError.NotFound))
        assertEquals(AddressDetail.Mode.Schedule, result.mode)
        assertEquals(AddressDetail.Notice.NotFound, result.notice)
    }

    @Test
    fun missLyckadUppdateringVisarSparatSchemaOchNarDetHamtades() {
        val yesterday = StockholmClock.dateOn(day("2026-11-05"), 18 * 60 + 40)
        val result = detail(schedule(listOf(event("2026-11-09", listOf("rest"))), fetchedAt = yesterday, error = ApiError.SourceUnavailable))
        assertEquals(AddressDetail.Mode.Schedule, result.mode)
        assertEquals(AddressDetail.Notice.SavedShown("Hämtat i går 18:40 från Uppsala Vatten."), result.notice)
    }

    @Test
    fun hamtadTextFoljerSvenskTidOchDag() {
        val morning = StockholmClock.dateOn(today, 9 * 60 + 12)
        // Källans namn står i kortet ovanför, så raden har bara tiden.
        assertEquals("Hämtat i dag 09:12", detail(schedule(emptyList(), fetchedAt = morning)).fetchedText)
        val old = StockholmClock.dateOn(day("2026-11-01"), 7 * 60)
        assertEquals("Hämtat 1 nov 07:00", detail(schedule(emptyList(), fetchedAt = old), source = null).fetchedText)
    }

    @Test
    fun schemaSomInteHamtatsAnnuVisarLaddning() {
        val result = detail(null)
        assertEquals(AddressDetail.Mode.Loading, result.mode)
        assertNull(result.notice)
        assertNull(result.fetchedText)
    }

    @Test
    fun notistextenAngerKvallenForeOchTomningensDag() {
        assertEquals("Söndag kl. 18:00 inför måndagens tömning.", detail(schedule(listOf(event("2026-11-09", listOf("rest"))))).reminderText)
    }

    @Test
    fun notistextenHopparOverKvallarSomPasserat() {
        // Söndag 8 nov 19:00: kvällen före måndag har passerat.
        val late = StockholmClock.dateOn(day("2026-11-08"), 19 * 60)
        assertEquals("Onsdag kl. 18:00 inför torsdagens tömning.", detail(schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-12", listOf("glas")))), now = late).reminderText)
    }

    @Test
    fun tiderVisasMedValdTid() {
        val result = AddressDetail.make(address, null, ReminderSettings(reminderMinutes = 20 * 60 + 15), sourceName = null, now = noon)
        assertEquals("Kvällen före varje tömning kl. 20:15.", result.reminderText)
        assertEquals("Visas på låsskärmen kl. 20:15 dagen före till 08:15.", result.liveActivityText)
    }

    @Test
    fun liveActivityTextenArEnMening() {
        assertEquals("Visas på låsskärmen kl. 18:00 dagen före till 06:00.", AddressDetail.liveActivityText(ReminderSettings(reminderMinutes = 1080)))
        // 15:00 är inte kväll, så texten säger dagen före.
        assertEquals("Visas på låsskärmen kl. 15:00 dagen före till 03:00.", AddressDetail.liveActivityText(ReminderSettings(reminderMinutes = 900)))
        assertEquals(
            listOf(
                "Starten aviseras med ljud.",
                "Den försvinner senast efter 12 timmar.",
                "Öppna appen ibland, så att nästa tömning kommer med.",
                "Med notis vid samma tid får du en reserv om du inte bekräftar.",
            ),
            AddressDetail.liveActivityDetails(),
        )
    }

    @Test
    fun fyrahundraArVarkenNatfelEllerSaknadAdressOchHarEgenText() {
        val none = detail(CachedSchedule(lastAttemptAt = noon, lastError = ApiError.BadRequest))
        assertEquals(AddressDetail.Mode.Unavailable, none.mode)
        assertEquals(AddressDetail.Notice.BadRequest, none.notice)
        val saved = detail(schedule(listOf(event("2026-11-09", listOf("rest"))), error = ApiError.BadRequest))
        assertEquals(AddressDetail.Mode.Schedule, saved.mode)
        assertEquals(AddressDetail.Notice.BadRequest, saved.notice)
    }

    @Test
    fun sparfelSkiljsFranKallfel() {
        assertEquals(AddressDetail.Notice.StorageFailed, detail(CachedSchedule(lastAttemptAt = noon, lastError = ApiError.Unexpected(0))).notice)
        assertEquals(AddressDetail.Notice.SourceUnavailable, detail(CachedSchedule(lastAttemptAt = noon, lastError = ApiError.Unexpected(503))).notice)
    }

    @Test
    fun missadPaminnelseKravsMorgondagensTomningOchPasseradTid() {
        val tomorrow = schedule(listOf(event("2026-11-07", listOf("rest"))))
        val late = StockholmClock.dateOn(today, 18 * 60 + 1)
        val early = StockholmClock.dateOn(today, 17 * 60 + 59)
        val text = "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
        fun make(now: Instant, on: Boolean = true, schedule: CachedSchedule) =
            AddressDetail.make(address, schedule, ReminderSettings(), sourceName = null, now = now, remindersOn = on)
        assertEquals(text, make(late, schedule = tomorrow).missedReminder)
        assertNull(make(early, schedule = tomorrow).missedReminder)
        assertNull(make(late, on = false, schedule = tomorrow).missedReminder)
        // Tömning först i övermorgon har ingen missad kväll.
        assertNull(make(late, schedule = schedule(listOf(event("2026-11-08", listOf("rest"))))).missedReminder)
        // Exakt påminnelsetid räknas som passerad, eftersom planeraren inte schemalägger det.
        assertEquals(text, make(StockholmClock.dateOn(today, 18 * 60), schedule = tomorrow).missedReminder)
    }

    // MARK: Ordningen i adressvyn

    @Test
    fun kommandeVisarDeTreNarmasteDatumenOchLankForFler() {
        val result = detail(schedule(listOf(
            event("2026-11-09", listOf("rest", "mat")),
            event("2026-11-12", listOf("papper"), estimated = true),
            event("2026-11-16", listOf("plast")),
            event("2026-11-23", listOf("glas")),
        )))
        // Nästa tömning (9 nov) står i kortet ovanför, så Kommande börjar efter den.
        assertEquals(listOf("2026-11-12", "2026-11-16", "2026-11-23"), result.upcoming.map { it.date.iso })
        assertFalse(result.hasFullSchedule, "Alla datum står redan på sidan")
        // Hela schemat har alla datum, i samma format.
        assertEquals(listOf("2026-11-09", "2026-11-12", "2026-11-16", "2026-11-23"), result.rows.map { it.date.iso })
    }

    @Test
    fun helaSchematVisasNarFlerAnKommandeFinns() {
        val five = detail(schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-12", listOf("mat")), event("2026-11-16", listOf("plast")), event("2026-11-23", listOf("glas")), event("2026-11-30", listOf("rest")))))
        assertEquals(3, five.upcoming.size)
        assertTrue(five.hasFullSchedule)
        val four = detail(schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-12", listOf("mat")), event("2026-11-16", listOf("plast")), event("2026-11-23", listOf("glas")))))
        assertEquals(3, four.upcoming.size)
        assertFalse(four.hasFullSchedule)
    }

    @Test
    fun utanFlerAnNastaTomningArKommandeTom() {
        val one = detail(schedule(listOf(event("2026-11-09", listOf("rest")))))
        assertTrue(one.upcoming.isEmpty())
        assertFalse(one.hasFullSchedule)
        val none = detail(schedule(emptyList()))
        assertTrue(none.upcoming.isEmpty())
        assertFalse(none.hasFullSchedule)
    }

    @Test
    fun kommandeBorjarEfterNastaTomning() {
        val result = detail(schedule(listOf(event("2026-11-09", listOf("rest", "mat")), event("2026-11-11", listOf("papper")), event("2026-11-12", listOf("glas")), event("2026-11-16", listOf("plast")))))
        assertEquals(day("2026-11-09"), result.next?.date)
        assertEquals(listOf("2026-11-11", "2026-11-12", "2026-11-16"), result.upcoming.map { it.date.iso })
    }

    @Test
    fun radenHarDatumbrickaOchDagarKvarRaknatFranIDag() {
        val result = detail(schedule(listOf(
            event("2026-11-06", listOf("rest")),
            event("2026-11-07", listOf("mat")),
            event("2026-11-11", listOf("plast")),
            event("2026-12-02", listOf("glas"), estimated = true),
        )))
        assertEquals(listOf("6", "7", "11", "2"), result.rows.map { it.dayNumber })
        assertEquals(listOf("NOV", "NOV", "NOV", "DEC"), result.rows.map { it.month })
        assertEquals(listOf("i dag", "i morgon", "om 5 dagar", "ca om 26 dagar"), result.rows.map { it.daysText })
    }

    @Test
    fun dagarKvarRaknasFranDatumetOchInteFranSparadeFalt() {
        // Ett schema som hämtades för en vecka sedan, med sparade fält som säger något annat: dagarna räknas från i dag och datumet.
        val old = StockholmClock.dateOn(day("2026-10-30"), 8 * 60)
        val json = ApiDecoding.json.parseToJsonElement(fixture("adress")).jsonObject
        val next = buildJsonObject {
            put("fraction", "rest"); put("name", "Restavfall"); put("color", "#555555"); put("date", "2026-11-09")
            put("daysUntil", 10); put("isToday", true); put("isTomorrow", true); put("estimated", false); put("warning", JsonNull)
            put("text", "Restavfall – i dag, fredag 30 oktober")
        }
        val events = buildJsonObject {
            put("date", "2026-11-09"); put("fractions", JsonArray(listOf(JsonPrimitive("rest")))); put("estimated", false)
            put("deviation", JsonNull); put("warning", JsonNull); put("labels", JsonObject(emptyMap()))
        }
        val changed = JsonObject(json + mapOf("next" to JsonArray(listOf(next)), "summary" to JsonPrimitive("Restavfall i dag"), "events" to JsonArray(listOf(events))))
        val response = ApiDecoding.addressResponse(changed)
        val result = detail(CachedSchedule(response = response, fetchedAt = old, lastAttemptAt = old, lastError = null))
        assertEquals("Om 3 dagar", result.next?.headline)
        assertEquals("Måndag 9 november", result.next?.longDate)
        assertEquals("om 3 dagar", result.rows.firstOrNull()?.daysText)
        assertEquals("om 3 d", result.rows.firstOrNull()?.shortDaysText, "Talet och d hålls ihop med hårt mellanslag")
        assertEquals("om 3 dagar", result.bins.firstOrNull()?.daysText)
    }

    @Test
    fun varningenForNastaTomningVisasBaraIRutan() {
        val result = detail(schedule(listOf(
            event("2026-11-09", listOf("rest"), deviation = Deviation(day("2026-11-08"), "Helg"), warning = "Helgdag"),
            event("2026-11-12", listOf("mat"), warning = "Ställ ut tidigt"),
        )))
        assertEquals("Helgdag", result.nextWarning)
        // Kommande har bara datumen efter nästa tömning, med sina egna varningar.
        assertEquals(listOf("2026-11-12"), result.upcoming.map { it.date.iso })
        assertEquals(listOf<String?>("Ställ ut tidigt"), result.upcoming.map { it.warning })
        // Hela schemat visar alla varningar.
        assertEquals(listOf<String?>("Helgdag", "Ställ ut tidigt"), result.rows.map { it.warning })
    }

    @Test
    fun nastaTomningsAvvikelseStarIKortet() {
        val result = detail(schedule(listOf(
            event("2026-11-09", listOf("rest"), deviation = Deviation(day("2026-11-08"), "Helg"), warning = "Helgdag"),
            event("2026-11-12", listOf("mat")),
        )))
        assertEquals("Flyttad från sön 8 nov", result.nextDeviation)
        assertNull(detail(schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-12", listOf("mat"))))).nextDeviation)
    }

    @Test
    fun voiceOverLaserRadenMedDagarKvar() {
        val result = detail(schedule(listOf(event("2026-11-12", listOf("rest", "mat"), estimated = true, warning = "Helgdag"))))
        assertEquals("ca tors 12 nov, ca om 6 dagar. Restavfall, Matavfall. Helgdag", result.rows[0].accessibilityLabel)
    }

    @Test
    fun voiceOverLaserNastaTomningMedDatumDagarOchKarl() {
        assertEquals("Nästa tömning. Om 3 dagar. Måndag 9 november. Restavfall, Matavfall", detail(schedule(listOf(event("2026-11-09", listOf("rest", "mat"))))).next?.accessibilityLabel)
        assertEquals("Nästa tömning. Ca om 3 dagar. Ca måndag 9 november. Restavfall", detail(schedule(listOf(event("2026-11-09", listOf("rest"), estimated = true)))).next?.accessibilityLabel)
    }

    @Test
    fun voiceOverLaserKarletsKort() {
        val result = detail(schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-12", listOf("papper"), estimated = true))))
        assertEquals(listOf("Restavfall, om 3 dagar, Mån 9 nov", "Pappersförpackningar, om 6 dagar, ca tors 12 nov"), result.bins.map { it.accessibilityLabel })
    }

    @Test
    fun radensKortaDagarKvarHarCaOchLasesHeltAvVoiceOver() {
        val result = detail(schedule(listOf(
            event("2026-11-06", listOf("rest")),
            event("2026-11-07", listOf("mat")),
            event("2026-11-11", listOf("plast")),
            event("2026-12-02", listOf("glas"), estimated = true),
        )))
        assertEquals(listOf("i dag", "i morgon", "om 5 d", "ca om 26 d"), result.rows.map { it.shortDaysText })
    }

    // MARK: Hur långt schemat gäller

    @Test
    fun schemaperiodenAvkodasFranAvesta() {
        val response = fixtureResponse("adress-avesta")
        assertEquals(SchedulePeriod(day("2027-01-10"), "Avesta Vatten publicerar hämtschemat ett år i taget."), response.schedule)
        assertEquals(response, ApiDecoding.addressResponse(ApiDecoding.json.encodeToString(AddressResponse.serializer(), response)))
    }

    @Test
    fun schemaperiodenSaknasNullEllerTrasig() {
        // Äldre svar och sparade scheman saknar fältet.
        assertNull(fixtureResponse("adress").schedule)
        val json = ApiDecoding.json.parseToJsonElement(fixture("adress-avesta")).jsonObject
        val brokenValues = listOf(
            JsonNull,
            JsonPrimitive("2027-01-10"),
            buildJsonObject { put("until", "10 jan") },
            buildJsonObject { put("reason", "Utan datum") },
        )
        for (broken in brokenValues) {
            val response = ApiDecoding.addressResponse(JsonObject(json + ("schedule" to broken)))
            assertNull(response.schedule, "$broken")
            assertTrue(response.events.isNotEmpty(), "$broken")
        }
        val noReason = ApiDecoding.addressResponse(JsonObject(json + ("schedule" to buildJsonObject { put("until", "2027-01-10"); put("reason", JsonNull) })))
        assertEquals(SchedulePeriod(day("2027-01-10"), null), noReason.schedule)
    }

    @Test
    fun radenOmPeriodenVisasMedOrsak() {
        val result = detail(periodSchedule(listOf(event("2026-11-09", listOf("rest"))), "2027-01-10"))
        assertEquals(AddressDetail.Mode.Schedule, result.mode)
        assertEquals(AddressDetail.SchedulePeriodLine("Schemat gäller till 10 januari 2027.", "Avesta Vatten publicerar hämtschemat ett år i taget."), result.schedulePeriod)
    }

    @Test
    fun radenUtanOrsakOchForLivekallor() {
        val blank = detail(periodSchedule(listOf(event("2026-11-09", listOf("rest"))), "2027-01-10", reason = "  "))
        assertEquals(AddressDetail.SchedulePeriodLine("Schemat gäller till 10 januari 2027.", null), blank.schedulePeriod)
        // `null` gäller alla live-källor: ingen rad.
        val live = detail(periodSchedule(listOf(event("2026-11-09", listOf("rest"))), null))
        assertNull(live.schedulePeriod)
        assertEquals("Källan visar inga hämtningar för adressen just nu. Stämmer det inte, kontakta Uppsala Vatten.", live.noUpcomingMessage.message)
        // Inget schema än: ingen rad.
        assertNull(detail(null).schedulePeriod)
    }

    @Test
    fun liveKallaUtanNamnHanvisarTillAnsvarig() {
        val live = detail(periodSchedule(emptyList(), null), source = null)
        assertEquals("Källan visar inga hämtningar för adressen just nu. Stämmer det inte, kontakta den som ansvarar för hämtningen.", live.noUpcomingMessage.message)
    }

    @Test
    fun liveKallaEfterFelSagerBaraVadSchematSager() {
        assertEquals("Det senast hämtade schemat har inga fler hämtningar.", detail(schedule(emptyList(), error = ApiError.Network), source = "Uppsala Vatten").noUpcomingMessage.message)
    }

    @Test
    fun passeradPeriodUtanHamtningarSagerAttNastaPeriodInteArPublicerad() {
        val result = detail(periodSchedule(listOf(event("2026-11-01", listOf("rest"))), "2026-11-05"))
        assertEquals(AddressDetail.Mode.NoUpcoming, result.mode)
        assertNull(result.schedulePeriod)
        assertEquals(
            AddressDetail.NoUpcomingMessage(
                title = "Inga kommande hämtningar",
                message = "Schemat gällde till 5 november 2026, och källan har inte publicerat nästa period än. Avesta Vatten publicerar hämtschemat ett år i taget.",
            ),
            result.noUpcomingMessage,
        )
        assertNull(result.notice)
        assertEquals("Schemat gällde till 5 november 2026, och källan har inte publicerat nästa period än.", detail(periodSchedule(emptyList(), "2026-11-05", reason = null)).noUpcomingMessage.message)
    }

    @Test
    fun sparatSchemaEfterFelSagerInteAttKallanSaknarNastaPeriod() {
        // Hämtningen misslyckades och ett sparat schema med passerad period visas. Nästa period kan finnas hos källan utan
        // att ha kommit fram, så kortet säger bara vad det senast hämtade schemat säger.
        val failed = periodSchedule(listOf(event("2026-11-01", listOf("rest"))), "2026-11-05").copy(lastError = ApiError.Network)
        val result = detail(failed)
        assertEquals(AddressDetail.Mode.NoUpcoming, result.mode)
        assertEquals(AddressDetail.Notice.SavedShown("Hämtat i dag 12:00 från Uppsala Vatten."), result.notice)
        assertEquals(
            AddressDetail.NoUpcomingMessage(
                title = "Inga kommande hämtningar",
                message = "Det senast hämtade schemat gällde till 5 november 2026. Avesta Vatten publicerar hämtschemat ett år i taget.",
            ),
            result.noUpcomingMessage,
        )
        assertFalse(result.noUpcomingMessage.message.contains("inte publicerat"))
        // Utan period, som för live-källor, inte heller att schemat har tagit slut hos kommunen.
        assertEquals("Det senast hämtade schemat har inga fler hämtningar.", detail(periodSchedule(emptyList(), null).copy(lastError = ApiError.Network)).noUpcomingMessage.message)
        // En period som gäller fortfarande är densamma som utan fel.
        val current = periodSchedule(emptyList(), "2027-01-10", reason = null).copy(lastError = ApiError.Network)
        assertEquals("Inga fler hämtningar i schemat, som gäller till 10 januari 2027.", detail(current).noUpcomingMessage.message)
    }

    @Test
    fun helaSchematHarNamnetForstOchAdressvynUnderRubriken() {
        val area = address.copy(street = "Kaplansgården, Jularbo m.fl.", locality = "", kommun = "Avesta kommun", selection = "area", displayName = "Kaplansgården, Jularbo m.fl.", isPrimary = false)
        val result = detail(null, address = area)
        // Adressvyn har namnet som rubrik, så bara platsen står under.
        assertEquals(HomeContent.AddressLines(address = "", place = "Avesta kommun"), result.lines)
        // Hela schemat har rubriken "Hela schemat", så namnet står först.
        assertEquals(HomeContent.AddressLines(name = "Kaplansgården, Jularbo m.fl.", address = "", place = "Avesta kommun"), result.namedLines)
        assertEquals("Kaplansgården, Jularbo m.fl., Avesta kommun", result.namedLines.accessibilityLabel)
        // Huvudadressen med eget namn: namnet, gatan och platsen.
        assertEquals("Hemma, Storgatan 2, Uppsala", detail(null).namedLines.accessibilityLabel)
    }

    @Test
    fun periodenGallerHelaSistaDagenISverige() {
        val schedule = periodSchedule(listOf(event("2026-11-06", listOf("rest"))), "2026-11-06")
        // 23:30 svensk tid den sista dagen: perioden gäller fortfarande, och dagens hämtning visas.
        val late = detail(schedule, now = StockholmClock.dateOn(day("2026-11-06"), 23 * 60 + 30))
        assertEquals(AddressDetail.Mode.Schedule, late.mode)
        assertEquals("Schemat gäller till 6 november 2026.", late.schedulePeriod?.text)
        // 00:30 svensk tid dagen efter, som är kvällen före i New York: perioden har passerat.
        val after = detail(schedule, now = StockholmClock.dateOn(day("2026-11-07"), 30))
        assertEquals(AddressDetail.Mode.NoUpcoming, after.mode)
        assertNull(after.schedulePeriod)
        assertTrue(after.noUpcomingMessage.message.startsWith("Schemat gällde till 6 november 2026"))
    }

    @Test fun datumMedArUtanVeckodag() = assertEquals("10 januari 2027", SwedishFormat.dayMonthYear(day("2027-01-10")))

    @Test
    fun utanFlerHamtningarForeSlutetSagerKortetHurLangtSchematGaller() {
        // Sista hämtningen har passerat, men perioden gäller fortfarande: kortet och raden får inte motsäga varandra.
        val result = detail(periodSchedule(listOf(event("2026-11-02", listOf("rest"))), "2027-01-10"))
        assertEquals(AddressDetail.Mode.NoUpcoming, result.mode)
        assertEquals(
            AddressDetail.NoUpcomingMessage(
                title = "Inga kommande hämtningar",
                message = "Inga fler hämtningar i schemat, som gäller till 10 januari 2027. Avesta Vatten publicerar hämtschemat ett år i taget.",
            ),
            result.noUpcomingMessage,
        )
        // Perioden står i kortet, så den separata raden visas inte en gång till.
        assertNull(result.schedulePeriod)
        assertEquals("Inga fler hämtningar i schemat, som gäller till 10 januari 2027.", detail(periodSchedule(emptyList(), "2027-01-10", reason = null)).noUpcomingMessage.message)
    }

    @Test
    fun passeradPeriodMedHamtningarEfterIDagVisarIngenRad() {
        // Källans data säger emot sig själv: hämtningar efter en period som har passerat. Schemat visas, men ingen rad.
        val result = detail(periodSchedule(listOf(event("2026-11-09", listOf("rest"))), "2026-11-05"))
        assertEquals(AddressDetail.Mode.Schedule, result.mode)
        assertEquals(day("2026-11-09"), result.next?.date)
        assertNull(result.schedulePeriod)
    }

    // MARK: Schemat tar snart slut

    @Test
    fun rutanVisasNarSchematHarFjortonDagarEllerMindreKvar() {
        assertNull(ending(15).scheduleEnding)
        assertEquals(14, ending(14).scheduleEnding?.daysLeft)
        assertEquals(1, ending(1).scheduleEnding?.daysLeft)
        assertEquals(0, ending(0).scheduleEnding?.daysLeft)
    }

    @Test
    fun rutanVisasInteForPasseratDatumEllerLivekallor() {
        assertNull(ending(-1).scheduleEnding)
        assertNull(ending(null).scheduleEnding)
        assertNull(detail(null).scheduleEnding)
    }

    @Test
    fun rutanHarOrsakenOchSagerAttNyaTiderKommer() {
        val result = ending(10)
        assertEquals("Schemat tar snart slut", result.scheduleEnding?.title)
        assertEquals("Nya tider visas när källan publicerar dem.", result.scheduleEnding?.message)
        assertEquals("Nya tider visas när källan publicerar dem.", ending(10, reason = null).scheduleEnding?.message)
        // Källans orsak står en gång, under raden "Schemat gäller till", och inte i rutan.
        assertEquals("Avesta Vatten publicerar hämtschemat ett år i taget.", result.schedulePeriod?.reason)
        assertEquals(false, result.scheduleEnding?.message?.contains("Avesta Vatten"))
    }

    @Test
    fun rutanVisasInteUtanKommandeHamtningar() {
        // Då säger kortet utan hämtningar hur långt schemat gäller, så rutan skulle bara upprepa det.
        val result = ending(5, events = listOf(event("2026-11-01", listOf("rest"))))
        assertEquals(AddressDetail.Mode.NoUpcoming, result.mode)
        assertNull(result.scheduleEnding)
    }

    @Test
    fun efterDatumetGallerOmgangCsTexter() {
        val result = ending(-3, events = listOf(event("2026-11-01", listOf("rest"))))
        assertNull(result.scheduleEnding)
        assertTrue(result.noUpcomingMessage.message.contains("källan har inte publicerat nästa period än"))
    }

    /** Prövar Stockholmstid mot telefonens tidszon och säger något först med TZ=America/New_York. */
    @Test
    fun rutanRaknasISvenskTidOavsettTelefonensTidszon() {
        // 00:30 den 7 november i Stockholm är 18:30 den 6:e i New York. I dag är den 7:e, och 21 november är 14 dagar kvar.
        val early = StockholmClock.dateOn(day("2026-11-07"), 30)
        assertEquals(14, detail(periodSchedule(listOf(event("2026-11-09", listOf("rest"))), "2026-11-21"), now = early).scheduleEnding?.daysLeft)
    }

    // MARK: Utställt

    /** Android: utan påminnelser finns varken knapp eller rad. */
    @Test
    fun adressvynUtanHushallHarIngenRad() {
        assertNull(detail(schedule(listOf(event("2026-11-09", listOf("rest"))))).placedOut)
    }

    /** Android: raden Utställt med "av dig" och klockslaget, i stället för hushållets bock. */
    @Test
    fun adressvynVisarUtstalltAvDigOchKlockslaget() {
        val mark = PlacedOut(key, day("2026-11-09"))
        val at = StockholmClock.dateOn(day("2026-11-08"), 19 * 60 + 42)
        val result = AddressDetail.make(
            address.copy(notificationsOn = true), schedule(listOf(event("2026-11-09", listOf("rest")))), ReminderSettings(), sourceName = null,
            now = sundayAt(20), ownPlacedOut = setOf(mark), placedOutTimes = mapOf(mark to at),
        )
        val line = assertNotNull(result.placedOut)
        assertFalse(line.showsButton)
        assertEquals("Utställt", line.placedOutTitle)
        assertEquals("av dig · kl. 19:42", line.placedOutSubtitle)
    }

    // MARK: Påminnelser utan hämtningar

    @Test fun paminnelserVisasMedHamtningar() = assertTrue(reminderDetail(schedule(listOf(event("2026-11-09", listOf("rest"))))).showsReminders)

    @Test
    fun paminnelserDoljsUtanHamtningar() {
        val result = reminderDetail(schedule(emptyList()))
        assertEquals(AddressDetail.Mode.NoUpcoming, result.mode)
        assertFalse(result.showsReminders)
    }

    @Test
    fun paminnelserVisasUtanHamtningarNarNotisenArPa() {
        val result = reminderDetail(schedule(emptyList()), notificationsOn = true)
        assertTrue(result.showsReminders)
        assertEquals("Inga hämtningar att påminna om just nu.", result.reminderText)
    }

    @Test
    fun paminnelserVisasUtanHamtningarNarLiveActivityArPaForHuvudadressen() {
        val primary = reminderDetail(schedule(emptyList()), liveActivityOn = true)
        assertTrue(primary.showsReminders)
        assertEquals("Inga hämtningar att påminna om just nu.", primary.liveActivityText)
        // Live Update gäller bara huvudadressen.
        assertFalse(reminderDetail(schedule(emptyList()), isPrimary = false, liveActivityOn = true).showsReminders)
    }

    @Test fun paminnelserVisasInteMedanSchematLaddas() = assertFalse(reminderDetail(null, notificationsOn = true).showsReminders)

    @Test
    fun liveActivityGerKnappenStallUtBaraForHuvudadressen() {
        val cached = schedule(listOf(event("2026-11-06", listOf("rest"))))
        val settings = ReminderSettings(liveActivityOn = true)
        assertEquals(true, AddressDetail.make(address, cached, settings, sourceName = null, now = noon).placedOut?.showsButton)
        assertNull(AddressDetail.make(address.copy(isPrimary = false), cached, settings, sourceName = null, now = noon).placedOut)
    }

    // MARK: Nästa påminnelse när reserven finns

    @Test
    fun reservenGoromInteEnTidigareKvallsnotis() {
        // Morgonnotisen blir reserv 06:45, men kvällens notis 18:00 kommer före och är nästa.
        val reserve = StockholmClock.dateOn(day("2026-11-09"), 6 * 60 + 45)
        assertEquals("Söndag kl. 18:00 inför måndagens tömning.", reminderRow(sundayAt(15), reserveAt = reserve))
    }

    @Test
    fun reservenVisasNarDenArNastaPaminnelse() {
        val reserve = StockholmClock.dateOn(day("2026-11-09"), 6 * 60 + 45)
        // Kvällens tid har passerat: nästa är morgonen, Live Updatens val, och den ersätts av reserven.
        assertEquals("Måndag kl. 06:45, samma dag som tömningen, om aktiviteten inte syns.", reminderRow(sundayAt(19), reserveAt = reserve))
        // Nästa är först tisdag kväll, och reserven kommer före: den gäller.
        val late = StockholmClock.dateOn(day("2026-11-09"), 6 * 60 + 20)
        assertEquals("Måndag kl. 06:45, samma dag som tömningen, om aktiviteten inte syns.", reminderRow(late, reserveAt = reserve))
    }

    @Test
    fun morgonpaminnelsenLovasInteIAdressvynNarUtstalld() {
        val mark = PlacedOut(address.key, day("2026-11-09"))
        assertEquals("Tisdag kl. 18:00 inför onsdagens tömning.", reminderRow(sundayAt(19), settings = ReminderSettings(morningOn = true), placedOut = setOf(mark)))
    }

    // MARK: Kalender

    /** Android: raden öppnar Google Kalenders prenumeration med adressens `links.ics`. */
    @Test
    fun kalenderlänkenGårTillGoogleKalender() {
        val result = detail(schedule(listOf(event("2026-11-09", listOf("rest")))))
        assertEquals(
            "https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fsopor.hardyson.se%2Fics%2Fuppsala%2Fstorgatan-2_uppsala-4004688.ics",
            result.calendarLink,
        )
        assertNull(detail(null).calendarLink)
    }
}
