package se.hardyson.sophamtning.reminders

import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.reminders.PickupActivityContent
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.StoreRead

/** En notis med ett alarm som inte har gått än. */
@Serializable
data class ScheduledNotification(
    val identifier: String,
    /** Millisekunder sedan 1970 i UTC. */
    val fireAt: Long,
    val title: String,
    val body: String,
    val key: AddressKey,
    val pickupDate: DayDate,
) {
    val fireDate: Instant get() = Instant.ofEpochMilli(fireAt)

    companion object {
        fun from(planned: PlannedNotification) =
            ScheduledNotification(planned.identifier, planned.fireDate.toEpochMilli(), planned.title, planned.body, planned.key, planned.pickupDate)
    }
}

/** En Live Update: ett alarm vid starten, och sedan en pågående notis. */
@Serializable
data class ScheduledLiveUpdate(
    val id: String,
    val key: AddressKey,
    val pickupDate: DayDate,
    /** Millisekunder sedan 1970 i UTC. */
    val start: Long,
    val content: PickupActivityContent,
    /** Alarmet har gått, eller den visades direkt. */
    val started: Boolean = false,
    /** Användaren har svept bort notisen. */
    val dismissed: Boolean = false,
)

@Serializable
data class ScheduledFile(
    val notifications: List<ScheduledNotification> = emptyList(),
    val liveUpdates: List<ScheduledLiveUpdate> = emptyList(),
)

/**
 * Det som appen har schemalagt, i `scheduled-reminders.json` i lagringens katalog. Systemet kan inte svara på vilka alarm
 * som väntar, och tar bort alla alarm vid omstart, så filen är det som `pending()` och `current()` läser och det som läggs
 * in igen efter omstart. En fil som inte går att läsa räknas som tom: nästa planering lägger då in allt igen.
 */
class ScheduledReminders(private val store: LocalStore) {
    fun read(): ScheduledFile = synchronized(lock) { load() }

    /** Ändrar filen i ett steg. Kastar när den inte går att spara, och då är filen som förut. */
    fun update(change: (ScheduledFile) -> ScheduledFile): ScheduledFile = synchronized(lock) {
        val updated = change(load())
        store.setRawData(json.encodeToString(ScheduledFile.serializer(), updated).encodeToByteArray(), FILE)
        updated
    }

    private fun load(): ScheduledFile = when (val read = store.rawData(FILE)) {
        is StoreRead.Value -> runCatching { json.decodeFromString(ScheduledFile.serializer(), read.value.decodeToString()) }.getOrDefault(ScheduledFile())
        else -> ScheduledFile()
    }

    companion object {
        const val FILE = "scheduled-reminders.json"

        /** Alla läsningar och skrivningar i processen går efter varandra: appen, alarmen och mottagarna delar filen. */
        private val lock = Any()
        private val json = Json { ignoreUnknownKeys = true }
    }
}
