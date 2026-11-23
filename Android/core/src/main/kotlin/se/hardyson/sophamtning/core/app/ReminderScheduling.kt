package se.hardyson.sophamtning.core.app

import java.time.Instant
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.SavedAddress

/** Systemets tillstånd för notiser, som `NotificationAuthorization` på iOS. */
enum class NotificationAuthorization { NotDetermined, Denied, Authorized }

/** Svaret när en påminnelse slås på, som `PermissionResult` på iOS. */
enum class PermissionResult {
    Granted,

    /** Systemet nekar notiser. Valet är kvar och visas som av. */
    Denied,

    /** Valet gick inte att spara eller adressen finns inte. Då är `lastStorageError` satt. */
    Failed,
}

/** Det som påminnelserna planeras från: samma uppgifter som planeraren får på iOS, läst ur lagringen. */
data class ReminderRequest(
    val addresses: List<SavedAddress>,
    val schedules: Map<AddressKey, CachedSchedule>,
    val settings: ReminderSettings,
    val placedOut: Set<PlacedOut>,
    val now: Instant,
)

/**
 * De anrop `AppModel` gör till påminnelserna: notiser, alarm och Live Update. Motsvarar `NotificationScheduling` och
 * `LiveActivityScheduling` på iOS. Android-lagret, med planeraren, alarm och notiser, byggs i plan 5.
 */
interface ReminderScheduling {
    /**
     * Om påminnelserna finns i den här versionen av appen. Falskt tills plan 5: då visas inget förslag, inget reglage och
     * ingen rad om påminnelser, eftersom de inte skulle fungera.
     */
    val available: Boolean

    suspend fun authorization(): NotificationAuthorization

    /** Frågar om tillstånd för notiser. Anropas bara när användaren slår på en påminnelse. */
    suspend fun requestAuthorization(): Boolean

    /** Planerar om alla påminnelser och ändrar bara skillnaden mot det som redan är schemalagt. */
    suspend fun apply(request: ReminderRequest)

    /** Tar bort väntande notiser med de här identifierarna. */
    suspend fun cancel(identifiers: List<String>)

    /** Tar bort alla appens väntande notiser och alarm, efter Börja om. */
    suspend fun cancelAll()

    /** Avslutar tömningens Live Update, om den finns. */
    suspend fun endLiveUpdate(entry: PlacedOut)

    /** Visar en notis direkt, till exempel för ett nytt meddelande från källan. */
    suspend fun deliverNow(identifier: String, title: String, body: String)
}

/**
 * Inga påminnelser: inget schemaläggs och ingen fråga ställs. Används tills plan 5. Tillståndet är "inte avgjort", så att
 * appen aldrig säger att notiserna är avstängda i systemet när de inte är det.
 */
object NoReminders : ReminderScheduling {
    override val available = false
    override suspend fun authorization() = NotificationAuthorization.NotDetermined
    override suspend fun requestAuthorization() = false
    override suspend fun apply(request: ReminderRequest) {}
    override suspend fun cancel(identifiers: List<String>) {}
    override suspend fun cancelAll() {}
    override suspend fun endLiveUpdate(entry: PlacedOut) {}
    override suspend fun deliverNow(identifier: String, title: String, body: String) {}
}
