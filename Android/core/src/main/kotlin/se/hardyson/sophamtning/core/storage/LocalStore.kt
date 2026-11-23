package se.hardyson.sophamtning.core.storage

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.AccessDeniedException
import java.nio.file.Files
import java.nio.file.NoSuchFileException
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.messages.SourceMessageMemory

/**
 * Resultatet av att läsa en fil. `Missing` är en fil som inte finns, vilket är ett normalt läge. Finns den men går inte att
 * läsa får appen aldrig skriva över den. `Unavailable`: själva läsningen misslyckades, så innehållet kan vara helt i sin
 * ordning. `Unreadable`: läsningen gick bra men innehållet går inte att tolka, alltså skadat.
 */
sealed interface StoreRead<out T> {
    data object Missing : StoreRead<Nothing>
    data class Value<T>(val value: T) : StoreRead<T>
    data object Unavailable : StoreRead<Nothing>
    data object Unreadable : StoreRead<Nothing>
}

/**
 * Lokal lagring som JSON-filer, i samma format som iOS-appens. Skrivningar är atomiska: innehållet skrivs till en temporär
 * fil som sedan flyttas på plats, så att en avbruten skrivning lämnar den gamla filen hel. Skrivfel kastas.
 *
 * Widgeten, rutan i snabbinställningarna och notiserna körs i appens process. Filerna för Utställt och visade eller
 * avslutade Live Updates läses och skrivs därför under ett lås per fil, i stället för `NSFileCoordinator` på iOS.
 */
class LocalStore(
    private val directory: File,
    /** Skriver byte till en fil. Byts bara ut i test, för att pröva en avbruten skrivning. */
    private val writeBytes: (File, ByteArray) -> Unit = ::writeAndSync,
) {
    // MARK: Adresser, inställningar, utställda och källor

    fun addresses(): List<SavedAddress> = read(ADDRESSES, addressList) ?: emptyList()

    /** Som `addresses()`, men skiljer en fil som saknas från en som inte går att läsa. */
    fun addressesState(): StoreRead<List<SavedAddress>> = readState(ADDRESSES, addressList)

    fun settingsState(): StoreRead<ReminderSettings> = readState(SETTINGS, ReminderSettings.serializer())

    fun scheduleState(key: AddressKey): StoreRead<CachedSchedule> = readState(scheduleFile(key), CachedSchedule.serializer())

    fun setAddresses(addresses: List<SavedAddress>) = write(ADDRESSES, addressList, addresses)

    fun settings(): ReminderSettings = read(SETTINGS, ReminderSettings.serializer()) ?: ReminderSettings()

    fun setSettings(settings: ReminderSettings) = write(SETTINGS, ReminderSettings.serializer(), settings)

    fun placedOut(): List<PlacedOut> = (placedOutState() as? StoreRead.Value)?.value ?: emptyList()

    fun placedOutState(): StoreRead<List<PlacedOut>> = locked(PLACED_OUT) { readState(PLACED_OUT, placedOutList) }

    fun setPlacedOut(placedOut: List<PlacedOut>) = updateLocked(PLACED_OUT) { placedOut }

    /** Lägger till en post utan att tappa någon som skrivs samtidigt. Passerade poster rensas samtidigt. */
    fun markPlacedOut(entry: PlacedOut, today: DayDate) = updateLocked(PLACED_OUT) { saved ->
        val current = saved.filter { it.date >= today }
        if (entry in current) current else current + entry
    }

    /** Tar bort en enskild post, till exempel när användaren ångrar. Finns den inte skrivs ingenting. Tiden tas bort med den. */
    fun unmarkPlacedOut(entry: PlacedOut) {
        updateLocked(PLACED_OUT) { saved -> saved.filter { it != entry } }
        pruneTimes()
    }

    /** Tar bort poster vars datum har passerat. Finns inget att ta bort skrivs ingenting. Tiderna rensas med dem. */
    fun prunePlacedOut(today: DayDate) {
        updateLocked(PLACED_OUT) { saved -> saved.filter { it.date >= today } }
        pruneTimes()
    }

    // MARK: Tiden för Utställt (bara Android)

    /**
     * När kärlen ställdes ut, för raden "av dig · kl. 19:42". Bara de som fortfarande är utställda. Sparas i
     * `placed-out-times.json` som `{ "<filnamn>-<iso>": <sekunder sedan 2001> }`. Filen finns bara på Android, och en fil som
     * inte går att läsa ger inga tider.
     */
    fun placedOutTimes(): Map<PlacedOut, Instant> {
        val times = locked(PLACED_OUT_TIMES) { read(PLACED_OUT_TIMES, timesMap) } ?: return emptyMap()
        return placedOut().mapNotNull { entry -> times[timeKey(entry)]?.let { entry to it } }.toMap()
    }

    /** Sparar tiden för en utställd tömning. Tider för tömningar som inte längre är utställda tas bort samtidigt. */
    fun setPlacedOutTime(entry: PlacedOut, at: Instant) = updateTimes { it + (timeKey(entry) to at) }

    /** Tar bort tiderna för tömningar som inte längre är utställda. Ett fel här är bara städning som görs nästa gång. */
    private fun pruneTimes() {
        try {
            updateTimes { it }
        } catch (_: IOException) {
        }
    }

    private fun updateTimes(change: (Map<String, Instant>) -> Map<String, Instant>) = locked(PLACED_OUT_TIMES) {
        val saved = read(PLACED_OUT_TIMES, timesMap) ?: emptyMap()
        val current = placedOut().map(::timeKey).toSet()
        val updated = change(saved).filterKeys { it in current }
        if (updated != saved) write(PLACED_OUT_TIMES, timesMap, updated)
    }

    private fun timeKey(entry: PlacedOut) = "${entry.key.fileName}-${entry.date.iso}"

    // MARK: Visade och avslutade Live Updates

    /** Tömningar vars Live Update bevisligen har visats. Går filen inte att läsa är listan tom, och reservnotisen behålls. */
    fun shownActivities(): List<PlacedOut> = (locked(SHOWN) { readState(SHOWN, placedOutList) } as? StoreRead.Value)?.value ?: emptyList()

    fun markShown(entries: List<PlacedOut>, today: DayDate) = mark(entries, SHOWN, today)

    fun clearShown() = updateLocked(SHOWN) { emptyList() }

    /** Tömningar vars Live Update har avslutats eller svepts bort efter sin start. De startas inte om. */
    fun endedActivities(): List<PlacedOut> = (locked(ENDED) { readState(ENDED, placedOutList) } as? StoreRead.Value)?.value ?: emptyList()

    fun markEnded(entries: List<PlacedOut>, today: DayDate) = mark(entries, ENDED, today)

    fun clearEnded() = updateLocked(ENDED) { emptyList() }

    /** Glömmer att tömningens Live Update har visats eller avslutats, så att den får starta igen, till exempel efter Ångra. */
    fun forgetActivity(entry: PlacedOut) {
        updateLocked(SHOWN) { saved -> saved.filter { it != entry } }
        updateLocked(ENDED) { saved -> saved.filter { it != entry } }
    }

    private fun mark(entries: List<PlacedOut>, file: String, today: DayDate) = updateLocked(file) { saved ->
        val current = saved.filter { it.date >= today }.toMutableList()
        for (entry in entries) if (entry.date >= today && entry !in current) current += entry
        current
    }

    fun sources(): CachedSources? = read(SOURCES, CachedSources.serializer())

    fun setSources(sources: CachedSources) = write(SOURCES, CachedSources.serializer(), sources)

    // MARK: Meddelanden från källan

    /** Sedda och stängda meddelanden. En fil som inte går att läsa ger [StoreRead.Unreadable] och skrivs inte över här. */
    fun sourceMessageMemoryState(): StoreRead<SourceMessageMemory> = readState(SOURCE_MESSAGES, SourceMessageMemory.serializer())

    fun setSourceMessageMemory(memory: SourceMessageMemory) = write(SOURCE_MESSAGES, SourceMessageMemory.serializer(), memory)

    // MARK: Scheman

    fun schedule(key: AddressKey): CachedSchedule? = read(scheduleFile(key), CachedSchedule.serializer())

    fun setSchedule(schedule: CachedSchedule, key: AddressKey) = write(scheduleFile(key), CachedSchedule.serializer(), schedule)

    /** Tar bort schemat. Ett schema som redan saknas är inte ett fel. */
    fun removeSchedule(key: AddressKey) {
        Files.deleteIfExists(File(directory, scheduleFile(key)).toPath())
    }

    // MARK: Rå data

    /** En fil med data som kärnan inte tolkar. Namnet är ett filnamn i katalogen. */
    fun rawData(name: String): StoreRead<ByteArray> {
        val file = File(directory, name)
        if (!file.exists()) return StoreRead.Missing
        return try {
            StoreRead.Value(file.readBytes())
        } catch (_: IOException) {
            StoreRead.Unavailable
        }
    }

    fun setRawData(data: ByteArray, name: String) = writeAtomically(File(directory, name), data)

    /** Tar bort filen. En fil som redan saknas är inte ett fel. */
    fun removeRawData(name: String) {
        Files.deleteIfExists(File(directory, name).toPath())
    }

    /** Flyttar en fil som inte går att läsa åt sidan (`<namn>.skadad-<tid>`) i stället för att radera den. */
    fun moveAsideAddresses(at: Instant) = moveAside(ADDRESSES, at)
    fun moveAsideSettings(at: Instant) = moveAside(SETTINGS, at)

    private fun moveAside(path: String, at: Instant) {
        val source = File(directory, path)
        if (!source.exists()) return
        Files.move(source.toPath(), File(directory, "$path.skadad-${at.epochSecond}").toPath())
    }

    // MARK: Filer

    private fun scheduleFile(key: AddressKey) = "schedules/${key.fileName}.json"

    internal fun <T> readState(path: String, serializer: KSerializer<T>): StoreRead<T> {
        val file = File(directory, path)
        if (!file.exists()) return StoreRead.Missing
        val text = try {
            file.readText()
        } catch (_: IOException) {
            return StoreRead.Unavailable
        }
        return try {
            StoreRead.Value(storeJson.decodeFromString(serializer, text))
        } catch (_: Exception) {
            StoreRead.Unreadable
        }
    }

    private fun <T> read(path: String, serializer: KSerializer<T>): T? = (readState(path, serializer) as? StoreRead.Value)?.value

    internal fun <T> write(path: String, serializer: KSerializer<T>, value: T) =
        writeAtomically(File(directory, path), storeJson.encodeToString(serializer, value).encodeToByteArray())

    private fun writeAtomically(file: File, bytes: ByteArray) {
        val parent = file.parentFile
        if (!parent.isDirectory && !parent.mkdirs()) throw IOException("Katalogen ${parent.name} går inte att skapa")
        val temp = File.createTempFile(".${file.name}.", ".tmp", parent)
        try {
            writeBytes(temp, bytes)
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            temp.delete()
        }
    }

    // MARK: Låsta filer

    private fun <T> locked(path: String, block: () -> T): T = synchronized(lockFor(path), block)

    /**
     * Läser och skriver under samma lås, så att ingen annan skrivning hamnar mellan läsningen och skrivningen. Filen går att
     * ersätta om den är skadad. Går den inte att läsa just nu skrivs den aldrig över. En oförändrad fil skrivs inte.
     */
    private fun updateLocked(path: String, change: (List<PlacedOut>) -> List<PlacedOut>) = locked(path) {
        val saved = when (val state = readState(path, placedOutList)) {
            is StoreRead.Value -> state.value
            StoreRead.Missing, StoreRead.Unreadable -> emptyList()
            StoreRead.Unavailable -> throw AccessDeniedException(path)
        }
        val updated = change(saved)
        if (updated != saved) write(path, placedOutList, updated)
    }

    private fun lockFor(path: String): Any = locks.computeIfAbsent(File(directory, path).absolutePath) { Any() }

    companion object {
        /**
         * Skriver och synkar till disken före flytten, som `AtomicFile` i Android. Annars kan flytten nå disken före
         * innehållet vid strömavbrott, och filen blir tom.
         */
        private fun writeAndSync(file: File, bytes: ByteArray) {
            FileOutputStream(file).use { stream ->
                stream.write(bytes)
                stream.fd.sync()
            }
        }

        private const val ADDRESSES = "addresses.json"
        private const val SETTINGS = "settings.json"
        private const val SOURCES = "sources.json"
        private const val SOURCE_MESSAGES = "source-messages.json"
        private const val PLACED_OUT = "placed-out.json"
        private const val SHOWN = "shown-activities.json"
        private const val ENDED = "ended-activities.json"
        private const val PLACED_OUT_TIMES = "placed-out-times.json"

        private val addressList = ListSerializer(SavedAddress.serializer())
        private val placedOutList = ListSerializer(PlacedOut.serializer())
        private val timesMap = MapSerializer(String.serializer(), SwiftDateSerializer)

        /** Ett lås per fil för hela processen, så att två `LocalStore` för samma katalog inte skriver över varandra. */
        private val locks = ConcurrentHashMap<String, Any>()
    }
}
