package se.hardyson.sophamtning.core.storage

import java.io.File
import java.io.IOException
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.dates.DayDate

class LocalStoreTest {
    @Test
    fun spararOchLaserAdress() {
        val store = LocalStore(tempDir())
        val saved = savedAddress(isPrimary = true)
        store.setAddresses(listOf(saved))
        assertEquals(listOf(saved), store.addresses())
        assertContentEquals("storgatan-21_örebro-75130".encodeToByteArray(), store.addresses().first().key.id.encodeToByteArray())
    }

    @Test
    fun filnamnInnehallerBaraHex() {
        assertEquals(64, testKey.fileName.length)
        assertTrue(testKey.fileName.all { it in "0123456789abcdef" })
    }

    @Test
    fun filnamnArKantSha256OchSkiljerGranser() {
        assertEquals("28f0462e0be6d48847a301fd2b7389cfa572904da8d74853d5e86ebbf1105832", testKey.fileName)
        assertTrue(AddressKey("a", "bc").fileName != AddressKey("ab", "c").fileName)
    }

    @Test
    fun skrivfelKastas() {
        val dir = tempDir()
        val file = File(dir, "en-fil").apply { writeText("x") }
        val store = LocalStore(File(file, "under"))
        assertFailsWith<IOException> { store.setAddresses(listOf(savedAddress())) }
        assertFailsWith<IOException> { store.setSchedule(CachedSchedule(), testKey) }
    }

    @Test
    fun taBortSaknatSchemaArInteFel() {
        LocalStore(tempDir()).removeSchedule(testKey)
    }

    @Test
    fun skadadFilBehandlasSomSaknad() {
        val dir = tempDir()
        val store = LocalStore(dir)
        store.setSchedule(CachedSchedule(response = fixtureResponse(), fetchedAt = Instant.now()), testKey)
        File(dir, "schedules/${testKey.fileName}.json").writeText("{")
        assertNull(store.schedule(testKey))
        for (name in listOf("addresses.json", "settings.json", "placed-out.json", "sources.json")) File(dir, name).writeText("{")
        assertTrue(store.addresses().isEmpty())
        assertEquals(ReminderSettings(), store.settings())
        assertTrue(store.placedOut().isEmpty())
        assertNull(store.sources())
    }

    @Test
    fun standardinstallningarArAvstangda() {
        val store = LocalStore(tempDir())
        assertFalse(store.settings().liveActivityOn)
        assertEquals(1080, store.settings().reminderMinutes)
        assertFalse(savedAddress().notificationsOn)
    }

    @Test
    fun giltigaPaminnelsetider() {
        for ((m, ok) in listOf(899 to false, 900 to true, 915 to true, 916 to false, 1380 to true, 1395 to false)) {
            assertEquals(ok, ReminderSettings.isValid(m, ReminderTiming.EveningBefore), "$m")
        }
    }

    @Test
    fun spararOchTarBortSchema() {
        val store = LocalStore(tempDir())
        val schedule = CachedSchedule(response = fixtureResponse(), fetchedAt = Instant.ofEpochSecond(1_800_000_000), lastError = ApiError.SourceUnavailable)
        store.setSchedule(schedule, testKey)
        assertEquals(schedule, store.schedule(testKey))
        store.removeSchedule(testKey)
        assertNull(store.schedule(testKey))
    }

    @Test
    fun ovantatFelSparasMedStatus() {
        val store = LocalStore(tempDir())
        val schedule = CachedSchedule(lastAttemptAt = Instant.ofEpochSecond(1_800_000_000), lastError = ApiError.Unexpected(500))
        store.setSchedule(schedule, testKey)
        assertEquals(schedule, store.schedule(testKey))
    }

    @Test
    fun spararInstallningarUtplaceradeOchKallor() {
        val store = LocalStore(tempDir())
        val settings = ReminderSettings(reminderMinutes = 960, liveActivityOn = true)
        store.setSettings(settings)
        assertEquals(settings, store.settings())
        val placed = listOf(PlacedOut(testKey, DayDate.parse("2026-11-09")!!))
        store.setPlacedOut(placed)
        assertEquals(placed, store.placedOut())
        val sources = CachedSources(SourcesResponse(emptyList(), emptyMap()), Instant.ofEpochSecond(1_800_000_000))
        store.setSources(sources)
        assertEquals(sources, store.sources())
    }

    @Test
    fun tvaLagerDelarFiler() {
        val dir = tempDir()
        LocalStore(dir).setAddresses(listOf(savedAddress()))
        assertEquals(1, LocalStore(dir).addresses().size)
    }

    @Test
    fun lagringenSkiljerSaknadFranOlasbarFil() {
        val dir = tempDir()
        val store = LocalStore(dir)
        assertIs<StoreRead.Missing>(store.addressesState())
        assertIs<StoreRead.Missing>(store.settingsState())
        assertIs<StoreRead.Missing>(store.scheduleState(testKey))

        store.setAddresses(listOf(savedAddress(isPrimary = true)))
        store.setSettings(ReminderSettings())
        store.setSchedule(CachedSchedule(), testKey)
        assertEquals(1, assertIs<StoreRead.Value<List<SavedAddress>>>(store.addressesState()).value.size)
        assertIs<StoreRead.Value<*>>(store.settingsState())
        assertIs<StoreRead.Value<*>>(store.scheduleState(testKey))

        File(dir, "addresses.json").writeText("skräp")
        File(dir, "settings.json").writeText("skräp")
        File(dir, "schedules/${testKey.fileName}.json").writeText("skräp")
        assertIs<StoreRead.Unreadable>(store.addressesState())
        assertIs<StoreRead.Unreadable>(store.settingsState())
        assertIs<StoreRead.Unreadable>(store.scheduleState(testKey))
        // De gamla anropen läser en skadad fil som saknad, som förut.
        assertTrue(store.addresses().isEmpty())
    }

    @Test
    fun lagringenSkiljerOtillgangligFranSkadadFil() {
        val dir = tempDir()
        val store = LocalStore(dir)
        store.setAddresses(listOf(savedAddress(isPrimary = true)))
        val file = File(dir, "addresses.json")
        // Läsningen misslyckas men innehållet är helt: otillgänglig, inte skadad.
        file.setReadable(false, false)
        try {
            assertIs<StoreRead.Unavailable>(store.addressesState())
        } finally {
            file.setReadable(true, false)
        }
        // Läsningen går bra men innehållet går inte att tolka: skadad.
        file.writeText("skräp")
        assertIs<StoreRead.Unreadable>(store.addressesState())
    }

    @Test
    fun unmarkTarBortBaraDenBocken() {
        val store = LocalStore(tempDir())
        val first = PlacedOut(testKey, DayDate.parse("2026-11-09")!!)
        val second = PlacedOut(testKey, DayDate.parse("2026-11-10")!!)
        store.setPlacedOut(listOf(first, second))
        store.unmarkPlacedOut(first)
        assertEquals(listOf(second), store.placedOut())
    }

    @Test
    fun raDataSkrivsLasesOchTasBort() {
        val store = LocalStore(tempDir())
        val name = "motor.data"
        assertIs<StoreRead.Missing>(store.rawData(name))
        store.setRawData(byteArrayOf(1, 2, 3), name)
        assertContentEquals(byteArrayOf(1, 2, 3), assertIs<StoreRead.Value<ByteArray>>(store.rawData(name)).value)
        store.removeRawData(name)
        store.removeRawData(name)
        assertIs<StoreRead.Missing>(store.rawData(name))
    }

    @Test
    fun installningarUtanForslagsfaltetLasesSomForut() {
        // Inställningar sparade före fältet `reminderOfferShown` ska läsas som de är, inte som skadade.
        val dir = tempDir()
        File(dir, "settings.json").writeText("""{"reminderMinutes":960,"liveActivityOn":true}""")
        val settings = LocalStore(dir).settings()
        assertEquals(960, settings.reminderMinutes)
        assertTrue(settings.liveActivityOn)
        assertFalse(settings.reminderOfferShown)
    }

    @Test
    fun avbrutenSkrivningLamnarGamlaFilenHel() {
        val dir = tempDir()
        LocalStore(dir).setAddresses(listOf(savedAddress(isPrimary = true)))
        val failing = LocalStore(dir) { file, bytes ->
            file.writeBytes(bytes.copyOf(bytes.size / 2))
            throw IOException("avbruten")
        }
        assertFailsWith<IOException> { failing.setAddresses(listOf(savedAddress(), savedAddress(AddressKey("x", "y")))) }
        assertEquals(listOf(savedAddress(isPrimary = true)), LocalStore(dir).addresses())
        // Ingen temporär fil blir kvar.
        assertEquals(listOf("addresses.json"), dir.list()!!.sorted())
    }

    @Test
    fun filenHarSammaFormatSomIos() {
        // Tider som sekunder sedan 2001, som JSONEncoder på iOS.
        val dir = tempDir()
        LocalStore(dir).setAddresses(listOf(savedAddress(addedAt = Instant.parse("2001-01-01T00:01:00Z"))))
        assertTrue("\"addedAt\":60.0" in File(dir, "addresses.json").readText())
        val ios = """[{"key":{"source":"orebro","id":"a"},"url":"https://x.se/a","street":"A","locality":"B","kommun":"C",
            "selection":"address","displayName":"A","isPrimary":true,"notificationsOn":false,"addedAt":815000000.5}]"""
        File(dir, "addresses.json").writeText(ios)
        assertEquals(Instant.parse("2026-10-29T20:53:20.500Z"), LocalStore(dir).addresses().single().addedAt)
    }

    @Test
    fun djuptNastladFilArOlasbarOchKrascharInte() {
        val dir = tempDir()
        File(dir, "addresses.json").writeText("[".repeat(200_000))
        assertIs<StoreRead.Unreadable>(LocalStore(dir).addressesState())
        File(dir, "settings.json").writeText("{\"a\":".repeat(200_000))
        assertIs<StoreRead.Unreadable>(LocalStore(dir).settingsState())
        File(dir, "schedules").mkdirs()
        File(dir, "schedules/${testKey.fileName}.json").writeText("{\"response\":" + "[".repeat(200_000))
        assertIs<StoreRead.Unreadable>(LocalStore(dir).scheduleState(testKey))
    }
}
