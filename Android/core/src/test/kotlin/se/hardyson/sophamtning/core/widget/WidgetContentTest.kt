package se.hardyson.sophamtning.core.widget

import java.io.File
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.Address
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.Links
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.api.SchedulePeriod
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.kommun.CalendarLink
import se.hardyson.sophamtning.core.kommun.SourceLink
import se.hardyson.sophamtning.core.schedule.FractionPickup
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.storage.savedAddress
import se.hardyson.sophamtning.core.storage.tempDir

/** Fredag 6 november 2026 klockan 12:00 svensk tid. */
private val now = StockholmClock.dateOn(day("2026-11-06"), 12 * 60)

private fun stockholm(text: String): Instant {
    val (date, time) = text.split("T")
    val (hour, minute) = time.split(":").map(String::toInt)
    return StockholmClock.dateOn(day(date), hour * 60 + minute)
}

private val info = mapOf(
    "rest" to FractionInfo(name = "Restavfall", short = "Rest", color = "#474C48", icon = "trash-2"),
    "mat" to FractionInfo(name = "Matavfall", short = "Mat", color = "#7A4A1E", icon = "apple"),
    "papper" to FractionInfo(name = "Papper", short = "Papper", color = "#2E5E86", icon = "package"),
)

private fun event(iso: String, fractions: List<String>, estimated: Boolean = false) =
    PickupEvent(date = day(iso), fractions = fractions, estimated = estimated, deviation = null, warning = null, labels = emptyMap())

private fun schedule(events: List<PickupEvent>, lastError: ApiError? = null, withResponse: Boolean = true, period: SchedulePeriod? = null): CachedSchedule {
    val response = AddressResponse(
        today = day("2026-11-06"),
        address = Address(id = "a", street = "Storgatan 12 B", locality = "Krylbo", kommun = "Avesta", source = "x", detail = null, selection = "address", notice = null),
        next = emptyList(), summary = "Gammal text", events = events, bins = emptyList(), fractions = info,
        links = Links(ics = "https://example.com/a.ics", web = "https://example.com/a"),
        updatedAt = day("2026-11-06"),
        schedule = period,
    )
    return CachedSchedule(response = if (withResponse) response else null, fetchedAt = now, lastAttemptAt = now, lastError = lastError)
}

private fun address(id: String, name: String, primary: Boolean): SavedAddress =
    savedAddress(key = AddressKey(source = "x", id = id), isPrimary = primary).copy(displayName = name)

private val home = address("home", name = "Hemma", primary = true)
private val cabin = address("cabin", name = "Stugan", primary = false)

private fun pickup(content: WidgetContent) = assertIs<WidgetContent.Pickup>(content, "Väntade kommande hämtning")

/** Gör alla JSON-filer i katalogen oläsbara, som en fil appen inte kommer åt, eller läsbara igen. */
private fun setReadable(readable: Boolean, directory: File) {
    directory.walkTopDown().filter { it.isFile && it.extension == "json" }.forEach { it.setReadable(readable, false) }
}

private fun endingSchedule(until: String?, events: List<PickupEvent> = listOf(event("2026-11-09", listOf("rest")))) =
    schedule(events, period = until?.let { SchedulePeriod(day(it), null) })

private fun fractionPickup(id: String, iso: String) = FractionPickup(fraction = id, date = day(iso), estimated = false, warning = null, daysUntil = 0)

/** WidgetContentTests på iOS, utan låsskärmen och hushållets bockar. */
class WidgetContentTest {
    @Test fun utanAdress() = assertEquals(WidgetContent.NoAddress, WidgetContent.make(emptyList(), null, now))

    @Test
    fun anvanderHuvudadressen() {
        assertEquals("Hemma", pickup(WidgetContent.make(listOf(cabin, home), schedule(listOf(event("2026-11-09", listOf("rest")))), now)).name)
    }

    @Test
    fun utanMarkeringAnvandsForstaAdressen() {
        assertEquals(WidgetContent.NoUpcoming("Första"), WidgetContent.make(listOf(address("a", name = "Första", primary = false), cabin), schedule(emptyList()), now))
    }

    @Test
    fun raknarDagarLokalt() {
        // Svaret sparades den 6:e, och dess egna dagsfält ignoreras. Nu är det lördag den 7:e, dagen före tömningen.
        val content = pickup(WidgetContent.make(listOf(home), schedule(listOf(event("2026-11-08", listOf("rest")))), stockholm("2026-11-07T09:00")))
        assertEquals("i morgon", content.relative)
        assertEquals("Sön 8 nov", content.shortDate)
    }

    @Test
    fun visarOmTreDagarMedAllaFraktionerPerNastaDatum() {
        val content = pickup(WidgetContent.make(listOf(home), schedule(listOf(event("2026-11-09", listOf("rest", "mat")), event("2026-11-12", listOf("papper"), estimated = true))), now))
        assertEquals("om 3 dagar", content.relative)
        assertEquals("Mån 9 nov", content.shortDate)
        assertEquals(listOf("mat", "rest", "papper"), content.fractions.map { it.fraction })
        assertEquals(listOf(3, 3, 6), content.fractions.map { it.daysUntil })
        assertEquals(listOf(false, false, true), content.fractions.map { it.estimated })
    }

    @Test
    fun beraknatDatumFarCa() {
        val content = pickup(WidgetContent.make(listOf(home), schedule(listOf(event("2026-11-09", listOf("rest"), estimated = true))), now))
        assertEquals("ca om 3 dagar", content.relative)
        assertEquals("ca mån 9 nov", content.shortDate)
    }

    @Test
    fun raderVisarKortDatumMedCaForBeraknade() {
        val content = pickup(WidgetContent.make(listOf(home), schedule(listOf(event("2026-11-09", listOf("rest")), event("2026-11-12", listOf("papper"), estimated = true))), now))
        assertEquals(listOf("mån 9 nov", "ca tors 12 nov"), content.fractions.map(WidgetContent::rowDate))
    }

    @Test fun tomningIDagVisasSomIDag() = assertEquals("i dag", pickup(WidgetContent.make(listOf(home), schedule(listOf(event("2026-11-06", listOf("rest")))), now)).relative)

    @Test
    fun baraPasseratVisarIngaKommande() {
        assertEquals(WidgetContent.NoUpcoming("Hemma"), WidgetContent.make(listOf(home), schedule(listOf(event("2026-11-02", listOf("rest")), event("2026-11-05", listOf("mat")))), now))
    }

    @Test
    fun saknatSchemaArInteTomtLage() {
        assertEquals(WidgetContent.NoSchedule("Hemma"), WidgetContent.make(listOf(home), null, now))
        // Ett försök utan svar och utan fel är också "ännu inte hämtat".
        assertEquals(WidgetContent.NoSchedule("Hemma"), WidgetContent.make(listOf(home), schedule(emptyList(), withResponse = false), now))
    }

    @Test
    fun misslyckadHamtningOchNotFoundHarEgnaLagen() {
        assertEquals(WidgetContent.Failed("Hemma"), WidgetContent.make(listOf(home), schedule(emptyList(), lastError = ApiError.Network, withResponse = false), now))
        assertEquals(WidgetContent.Failed("Hemma"), WidgetContent.make(listOf(home), schedule(emptyList(), lastError = ApiError.SourceUnavailable, withResponse = false), now))
        assertEquals(WidgetContent.NotFound("Hemma"), WidgetContent.make(listOf(home), schedule(emptyList(), lastError = ApiError.NotFound, withResponse = false), now))
    }

    @Test
    fun faltFelDoljerInteEttSparatSchema() {
        // Ett äldre svar visas även om det senaste försöket misslyckades, som på hemskärmen.
        pickup(WidgetContent.make(listOf(home), schedule(listOf(event("2026-11-09", listOf("rest"))), lastError = ApiError.NotFound), now))
    }

    @Test
    fun harSammaSanningSomHemskarmen() {
        // Huvudkortet och widgeten läser samma schema och ska vara överens i varje läge.
        val cases = listOf(
            null to "loading",
            schedule(emptyList(), lastError = ApiError.NotFound, withResponse = false) to "notFound",
            schedule(emptyList(), lastError = ApiError.Network, withResponse = false) to "failed",
            schedule(emptyList()) to "noUpcoming",
            schedule(listOf(event("2026-11-09", listOf("rest")))) to "pickup",
        )
        for ((value, expected) in cases) {
            val widgetName = when (WidgetContent.make(listOf(home), value, now)) {
                is WidgetContent.NoSchedule -> "loading"
                is WidgetContent.NotFound -> "notFound"
                is WidgetContent.Failed -> "failed"
                is WidgetContent.NoUpcoming -> "noUpcoming"
                is WidgetContent.Pickup -> "pickup"
                else -> "annat"
            }
            val status = HomeContent.make(listOf(home), value?.let { mapOf(home.key to it) } ?: emptyMap(), ReminderSettings(), now).primary?.status
            val homeName = when (status) {
                HomeContent.Status.Loading -> "loading"
                HomeContent.Status.Failed(ApiError.NotFound) -> "notFound"
                is HomeContent.Status.Failed -> "failed"
                HomeContent.Status.NoUpcoming -> "noUpcoming"
                is HomeContent.Status.Upcoming -> "pickup"
                null -> "ingen"
            }
            assertEquals(expected, widgetName)
            assertEquals(expected, homeName)
        }
    }

    // MARK: Tidslinje

    @Test
    fun tidslinjenByterVidSvenskMidnatt() {
        assertEquals(
            listOf(stockholm("2026-11-08T20:00"), stockholm("2026-11-09T00:00"), stockholm("2026-11-10T00:00")),
            WidgetContent.timelineDates(stockholm("2026-11-08T20:00"), days = 2),
        )
    }

    @Test
    fun tidslinjenStartarPaNuOchBorjarOmDagenGarOver() {
        // Klockan 23:59:30 svensk tid: nästa byte är om en halv minut.
        val almostMidnight = stockholm("2026-11-08T23:59") + Duration.ofSeconds(30)
        assertEquals(listOf(almostMidnight, stockholm("2026-11-09T00:00")), WidgetContent.timelineDates(almostMidnight, days = 1))
    }

    @Test
    fun tidslinjenFoljerSvenskTidAvenOmSommartidenAndras() {
        // 25 oktober 2026 slutar sommartiden: dygnet är 25 timmar, midnatten byts ändå vid väggklockan 00:00.
        val dates = WidgetContent.timelineDates(stockholm("2026-10-24T12:00"), days = 2)
        assertEquals(listOf(stockholm("2026-10-24T12:00"), stockholm("2026-10-25T00:00"), stockholm("2026-10-26T00:00")), dates)
        assertEquals(Duration.ofHours(25), Duration.between(dates[1], dates[2]))
    }

    @Test fun tidslinjenUtanDagarArBaraNu() = assertEquals(listOf(now), WidgetContent.timelineDates(now, days = 0))

    // MARK: Läsning från lagringen

    @Test
    fun lagringenUtanFilerGerNoAddress() {
        val data = WidgetData.read(LocalStore(tempDir()))
        assertEquals(WidgetContent.NoAddress, data.content(now))
        assertNull(data.reloadDate(now))
    }

    @Test
    fun lagringenGerHuvudadressenOchDessSchema() {
        val store = LocalStore(tempDir())
        store.setAddresses(listOf(cabin, home))
        store.setSchedule(schedule(listOf(event("2026-11-09", listOf("rest", "mat")))), home.key)
        val data = WidgetData.read(store)
        val content = pickup(data.content(now))
        assertEquals("Hemma", content.name)
        assertEquals(2, content.fractions.size)
        assertEquals("Matavfall", data.info("mat").name)
        // Okända fraktioner får sitt id som namn, som i appen.
        assertEquals("okand", data.info("okand").name)
    }

    @Test
    fun adresserSomInteGarAttLasaArInteNoAddress() {
        val dir = tempDir()
        val store = LocalStore(dir)
        store.setAddresses(listOf(home))
        setReadable(false, dir)
        try {
            val data = WidgetData.read(store)
            assertEquals(WidgetContent.Unavailable, data.content(now))
            assertNotEquals<WidgetContent>(WidgetContent.NoAddress, data.content(now))
            // Försöker igen inom 15 minuter.
            assertEquals(now + Duration.ofMinutes(15), data.reloadDate(now))
        } finally {
            setReadable(true, dir)
        }
    }

    @Test
    fun skadadAdressfilArInteNoAddress() {
        val dir = tempDir()
        File(dir, "addresses.json").writeText("inte json")
        val data = WidgetData.read(LocalStore(dir))
        assertEquals(WidgetContent.Unavailable, data.content(now))
        assertEquals(now + Duration.ofMinutes(15), data.reloadDate(now))
    }

    @Test
    fun schemaSomInteGarAttLasaGerUnavailableOchInteSaknatSchema() {
        val dir = tempDir()
        val store = LocalStore(dir)
        store.setAddresses(listOf(home))
        store.setSchedule(schedule(listOf(event("2026-11-09", listOf("rest")))), home.key)
        // Bara schemafilen blir oläsbar, adresserna går att läsa.
        val schedules = File(dir, "schedules")
        setReadable(false, schedules)
        try {
            val data = WidgetData.read(store)
            assertEquals(WidgetContent.Unavailable, data.content(now))
            assertEquals(now + Duration.ofMinutes(15), data.reloadDate(now))
        } finally {
            setReadable(true, schedules)
        }
    }

    @Test
    fun skadatSchemaArInteSaknatSchemaHellre() {
        val dir = tempDir()
        val store = LocalStore(dir)
        store.setAddresses(listOf(home))
        store.setSchedule(schedule(emptyList()), home.key)
        File(dir, "schedules/${home.key.fileName}.json").writeText("{")
        assertEquals(WidgetContent.Unavailable, WidgetData.read(store).content(now))
    }

    @Test
    fun saknadSchemafilArSaknatSchema() {
        val store = LocalStore(tempDir())
        store.setAddresses(listOf(home))
        val data = WidgetData.read(store)
        assertEquals(WidgetContent.NoSchedule("Hemma"), data.content(now))
        assertNull(data.reloadDate(now))
    }

    // MARK: Schemat slutar

    @Test
    fun widgetenVisarNarSchematSlutarInomFjortonDagar() {
        assertEquals("Schemat slutar 20 nov", WidgetContent.scheduleEnding(listOf(home), endingSchedule("2026-11-20"), now)?.shortText)
        assertNull(WidgetContent.scheduleEnding(listOf(home), endingSchedule("2026-11-21"), now))
        assertEquals(0, WidgetContent.scheduleEnding(listOf(home), endingSchedule("2026-11-06"), now)?.daysLeft)
        assertNull(WidgetContent.scheduleEnding(listOf(home), endingSchedule("2026-11-05"), now))
    }

    @Test
    fun widgetenVisarInteRadenForLivekallorUtanSchemaOchUtanHamtningar() {
        assertNull(WidgetContent.scheduleEnding(listOf(home), endingSchedule(null), now))
        assertNull(WidgetContent.scheduleEnding(listOf(home), null, now))
        assertNull(WidgetContent.scheduleEnding(emptyList(), endingSchedule("2026-11-20"), now))
        assertNull(WidgetContent.scheduleEnding(listOf(home), endingSchedule("2026-11-10", events = listOf(event("2026-11-01", listOf("rest")))), now))
    }

    @Test
    fun widgetenRaknarRadenFranTidslinjensTid() {
        // Raden försvinner av sig själv när dagarna går. Den 21 november är 15 dagar kvar i dag och 14 dagar kvar i morgon.
        val cached = endingSchedule("2026-11-21")
        assertNull(WidgetContent.scheduleEnding(listOf(home), cached, now))
        assertEquals(14, WidgetContent.scheduleEnding(listOf(home), cached, StockholmClock.dateOn(day("2026-11-07"), 0))?.daysLeft)
    }

    @Test
    fun widgetdataFranLagringenGerRadenOchGammalSparadDataUtanFaltetGarBra() {
        val store = LocalStore(tempDir())
        store.setAddresses(listOf(home))
        store.setSchedule(endingSchedule("2026-11-20"), home.key)
        assertEquals("Schemat slutar 20 nov", WidgetData.read(store).scheduleEnding(now)?.shortText)
        // Sparad data utan `schedule` avkodas utan fel och ger ingen rad.
        store.setSchedule(schedule(listOf(event("2026-11-09", listOf("rest")))), home.key)
        val old = WidgetData.read(store)
        assertNull(old.scheduleEnding(now))
        pickup(old.content(now))
    }

    @Test
    fun mellanstoraVisarBaraNästaTömning() {
        // Hemma: mat och papper den 25:e, plast den 9 dec och rest den 23 dec. Bara kärlen den 25:e visas, utan "+2 till".
        val fractions = listOf(fractionPickup("mat", "2026-11-25"), fractionPickup("papper", "2026-11-25"), fractionPickup("plast", "2026-12-09"), fractionPickup("rest", "2026-12-23"))
        val result = WidgetContent.mediumRows(fractions, maxRows = 3)
        assertEquals(listOf("mat", "papper"), result.rows.map { it.fraction })
        assertEquals(0, result.hidden)
    }

    @Test
    fun mellanstoraDöljerBaraSammaDagsKärl() {
        // Fyra kärl samma dag och plats för tre rader: två rader och "+2 till", som alla gäller samma tömning.
        val fractions = listOf(fractionPickup("mat", "2026-11-25"), fractionPickup("papper", "2026-11-25"), fractionPickup("plast", "2026-11-25"), fractionPickup("rest", "2026-11-25"), fractionPickup("glas", "2026-12-09"))
        val result = WidgetContent.mediumRows(fractions, maxRows = 3)
        assertEquals(listOf("mat", "papper"), result.rows.map { it.fraction })
        assertEquals(2, result.hidden)
        assertTrue(WidgetContent.mediumRows(emptyList(), maxRows = 3).rows.isEmpty())
    }

    // MARK: Ställ ut kärlen i widgeten

    @Test
    fun widgetensKnappDagenFöreOchSammaDag() {
        val store = LocalStore(tempDir())
        store.setAddresses(listOf(home))
        store.setSchedule(schedule(listOf(event("2026-11-07", listOf("rest")))), home.key)
        var data = WidgetData.read(store)
        assertEquals(PlacedOut(home.key, day("2026-11-07")), data.placeOutEntry(now))
        // Min egen bock gör att knappen försvinner och widgeten visar Utställt.
        store.markPlacedOut(PlacedOut(home.key, day("2026-11-07")), today = day("2026-11-06"))
        data = WidgetData.read(store)
        assertNull(data.placeOutEntry(now))
        assertTrue(data.placedOut(now))
    }

    @Test
    fun widgetensKnappInteLängreBort() {
        val store = LocalStore(tempDir())
        store.setAddresses(listOf(home))
        store.setSchedule(schedule(listOf(event("2026-11-09", listOf("rest")))), home.key)
        assertNull(WidgetData.read(store).placeOutEntry(now))
    }

    // MARK: Kalender

    /** Android: raden heter Lägg till i Google Kalender, och ikonen väljs i appen. */
    @Test
    fun kalenderlänken() {
        assertEquals("webcal://sopor.hardyson.se/api/v1/adress/x/y.ics", CalendarLink.webcal("https://sopor.hardyson.se/api/v1/adress/x/y.ics"))
        assertNull(CalendarLink.webcal(null))
        assertNull(CalendarLink.webcal("mailto:a@b.se"))
        val link = SourceLink.calendar("webcal://example.com/a.ics")
        assertEquals(SourceLink.Kind.Calendar, link.kind)
        assertEquals("Lägg till i Google Kalender", link.title)
        assertNull(link.webLink)
        assertEquals("Kalender", CalendarLink.SECTION)
        assertTrue(CalendarLink.FOOTER.contains("påminner kl. 18 kvällen innan"))
        // Kalendern har ett eget kort och står aldrig bland källans länkar.
        assertTrue(SourceLink.links(null, kommunInfo = "https://example.com/a").all { it.kind != SourceLink.Kind.Calendar })
    }

    /** Android: texten under raden, enligt specen, avsnittet Kalender. */
    @Test
    fun kalenderkortetsTexter() {
        assertEquals(
            "Tömningarna läggs in som en egen kalender i Google Kalender, som uppdateras av sig själv. Kalendern påminner kl. 18 kvällen innan, utöver appens notiser.",
            CalendarLink.FOOTER,
        )
    }

    /** Android: Google Kalenders länk för att prenumerera, med webcal-adressen kodad som en parameter. */
    @Test
    fun googleKalenderKodarAdressenMedProcentOchÅ() {
        assertEquals(
            "https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fsopor.hardyson.se%2Fics%2Forebro%2Fstorgatan-21_%25C3%25B6rebro-75130.ics",
            CalendarLink.googleCalendar("https://sopor.hardyson.se/ics/orebro/storgatan-21_%C3%B6rebro-75130.ics"),
        )
        assertEquals(
            "https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fsopor.hardyson.se%2Fics%2Favesta%2Fkaplansg%C3%A5rden%20jularbo.ics",
            CalendarLink.googleCalendar("https://sopor.hardyson.se/ics/avesta/kaplansgården jularbo.ics"),
        )
        // Bara https-adresser blir en prenumeration.
        assertNull(CalendarLink.googleCalendar("http://sopor.hardyson.se/ics/a.ics"))
        assertNull(CalendarLink.googleCalendar("mailto:a@b.se"))
    }
}
