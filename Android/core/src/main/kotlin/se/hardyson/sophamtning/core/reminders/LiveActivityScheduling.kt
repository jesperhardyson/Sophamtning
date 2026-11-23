package se.hardyson.sophamtning.core.reminders

/** Systemets läge för en Live Update, som `LiveActivityPhase` på iOS. */
enum class LiveActivityPhase {
    /** Alarmet för starten är satt. */
    Pending,

    /** Notisen visas. */
    Active,
    Stale,

    /** Avslutad av systemet, till exempel när tidsgränsen gått ut. */
    Ended,

    /** Bortsvept av användaren. */
    Dismissed,
    ;

    /**
     * Bara en väntande eller pågående Live Update aviserar eller syns. Räknas någon annan försvinner en notis tyst. `Stale`
     * räknas inte heller.
     */
    val countsAsExisting: Boolean get() = this == Pending || this == Active
}

data class SystemActivity(val activity: ExistingActivity, val phase: LiveActivityPhase)

/** Live Updaten startades inte, eftersom det inte gick just nu. Det är inget fel, och nästa planering försöker igen. */
class LiveActivityNotInForeground : Exception()

/** Det som `AppModel` behöver av Live Update, som `LiveActivityScheduling` på iOS. Appen implementerar det med alarm och en pågående notis. */
interface LiveActivityScheduling {
    /** Om Live Updates kan visas för appen just nu. */
    suspend fun areEnabled(): Boolean

    /** Alla Live Updates systemet känner till, i vilket läge de än är. */
    suspend fun current(): List<SystemActivity>

    /** Lägger in en Live Update, direkt eller till sin starttid ([PlannedLiveActivity.startMode]). Kastar när det inte går. */
    suspend fun start(activity: PlannedLiveActivity)

    suspend fun update(id: String, content: PickupActivityContent)

    suspend fun remove(id: String)

    /** Visar innehållet en kort stund och avslutar sedan Live Updaten, som knappen Klart gör. Utan egen avslutning uppdateras den och tas bort. */
    suspend fun end(id: String, content: PickupActivityContent) {
        update(id, content)
        remove(id)
    }
}

/** Inga Live Updates, till exempel i tester: inga finns och inga kan startas. */
object DisabledLiveActivities : LiveActivityScheduling {
    override suspend fun areEnabled() = false
    override suspend fun current() = emptyList<SystemActivity>()
    override suspend fun start(activity: PlannedLiveActivity) {}
    override suspend fun update(id: String, content: PickupActivityContent) {}
    override suspend fun remove(id: String) {}
}
