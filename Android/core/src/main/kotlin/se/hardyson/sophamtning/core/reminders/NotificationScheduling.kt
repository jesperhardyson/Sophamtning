package se.hardyson.sophamtning.core.reminders

import java.time.Instant

/** Systemets tillstånd för notiser, utan detaljer appen inte använder. Som `NotificationAuthorization` på iOS. */
enum class NotificationAuthorization {
    /** Användaren har inte fått frågan än. */
    NotDetermined,
    Denied,
    Authorized,
}

/** Svaret när användaren slår på notiser för en adress, som `PermissionResult` på iOS. */
enum class PermissionResult {
    Granted,

    /** Systemet nekar notiser. Valet är kvar och visas som av. */
    Denied,

    /** Tillståndet gick bra eller behövdes inte, men valet gick inte att spara, eller adressen finns inte. Då är `lastStorageError` satt. */
    Failed,
}

/** En väntande notis som appen själv har lagt in. */
data class PendingNotification(
    val identifier: String,
    /** `null` när systemet inte kan ange nästa tid. */
    val fireDate: Instant?,
    val body: String,
)

/**
 * Det som `AppModel` behöver av systemets notiser, som `NotificationScheduling` på iOS. Appen implementerar det med alarm och
 * `NotificationManager`. Implementationen rör bara notiser vars identifierare `NotificationDiff.isOwn` känner igen.
 */
interface NotificationScheduling {
    suspend fun authorization(): NotificationAuthorization

    /** Visar systemets fråga. Sant om användaren tillåter. Anropas bara när användaren slår på en påminnelse eller Live Update. */
    suspend fun requestAuthorization(): Boolean

    /** Väntande notiser som appen själv har lagt in och som inte har kommit än, inga andra. */
    suspend fun pending(): List<PendingNotification>

    /** Lägger in notiserna. En notis med samma identifierare ersätter den gamla. Svarar med identifierarna som inte gick att lägga in. */
    suspend fun schedule(notifications: List<PlannedNotification>): List<String>

    /** Tar bort de väntande notiserna, och notiserna som redan visas, med de här identifierarna. */
    suspend fun cancel(identifiers: List<String>)

    /**
     * Visar en notis direkt, till exempel ett nytt meddelande från källan. Identifieraren börjar med `kalla.`, som
     * `NotificationDiff.isOwn` inte känner igen, så att planeringen aldrig tar bort notisen.
     */
    suspend fun deliverNow(identifier: String, title: String, body: String)
}

/**
 * Inga notiser, till exempel i tester: inget schemaläggs och ingen fråga ställs. Påminnelserna visas då inte alls
 * (`AppState.remindersAvailable`). Tillståndet är "inte avgjort", och inte nekat som på iOS, så att appen aldrig säger att
 * notiserna är avstängda i systemet när de inte är det.
 */
object DisabledNotifications : NotificationScheduling {
    override suspend fun authorization() = NotificationAuthorization.NotDetermined
    override suspend fun requestAuthorization() = false
    override suspend fun pending() = emptyList<PendingNotification>()
    override suspend fun schedule(notifications: List<PlannedNotification>) = emptyList<String>()
    override suspend fun cancel(identifiers: List<String>) {}
    override suspend fun deliverNow(identifier: String, title: String, body: String) {}
}
