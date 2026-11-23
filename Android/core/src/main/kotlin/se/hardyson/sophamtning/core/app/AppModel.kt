package se.hardyson.sophamtning.core.app

import java.time.Duration
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.home.AddressDetail
import se.hardyson.sophamtning.core.home.HomeContent
import se.hardyson.sophamtning.core.messages.ActiveSourceMessage
import se.hardyson.sophamtning.core.messages.SourceMessageMemory
import se.hardyson.sophamtning.core.messages.SourceMessages
import se.hardyson.sophamtning.core.placedout.PlacedOutAction
import se.hardyson.sophamtning.core.reminders.DisabledNotifications
import se.hardyson.sophamtning.core.reminders.ExistingActivity
import se.hardyson.sophamtning.core.reminders.LiveActivityAction
import se.hardyson.sophamtning.core.reminders.LiveActivityDiff
import se.hardyson.sophamtning.core.reminders.LiveActivityNotInForeground
import se.hardyson.sophamtning.core.reminders.LiveActivityPhase
import se.hardyson.sophamtning.core.reminders.LiveActivityScheduling
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.NotificationDiff
import se.hardyson.sophamtning.core.reminders.NotificationScheduling
import se.hardyson.sophamtning.core.reminders.PermissionResult
import se.hardyson.sophamtning.core.reminders.PlannedLiveActivity
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.reminders.PlannerAddress
import se.hardyson.sophamtning.core.reminders.PlannerInput
import se.hardyson.sophamtning.core.reminders.ReminderPlan
import se.hardyson.sophamtning.core.reminders.ReminderPlanner
import se.hardyson.sophamtning.core.reminders.ReminderTime
import se.hardyson.sophamtning.core.reminders.StartMode
import se.hardyson.sophamtning.core.reminders.SystemActivity
import se.hardyson.sophamtning.core.reminders.startMode
import se.hardyson.sophamtning.core.schedule.RefreshOutcome
import se.hardyson.sophamtning.core.schedule.ScheduleLogic
import se.hardyson.sophamtning.core.schedule.ScheduleRefresher
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.AddressList
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.CachedSources
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.storage.StoreRead

/**
 * Filen som inte går att läsa, om någon. Hemskärmen visar då ett eget läge i stället för det tomma. `...Unreadable`:
 * innehållet är skadat, och Börja om erbjuds. `...Unavailable`: filen går inte att läsa just nu, och bara Försök igen erbjuds.
 */
enum class StorageProblem { AddressesUnreadable, AddressesUnavailable, SettingsUnreadable, SettingsUnavailable }

/** Appens tillstånd vid ett ögonblick. Allt som visas räknas från det och en given tid, aldrig från en sparad text. */
data class AppState(
    val addresses: List<SavedAddress> = emptyList(),
    val schedules: Map<AddressKey, CachedSchedule> = emptyMap(),
    val settings: ReminderSettings = ReminderSettings(),
    /** Det senaste lagringsfelet, tills det rensas med `clearStorageError()`. Då är det tidigare läget kvar. */
    val lastStorageError: String? = null,
    val storageProblem: StorageProblem? = null,
    /** Systemets tillstånd för notiser, senast läst. */
    val notificationAuthorization: NotificationAuthorization = NotificationAuthorization.NotDetermined,
    /** De utställda i `placed-out.json`. */
    val ownPlacedOut: Set<PlacedOut> = emptySet(),
    /** När kärlen ställdes ut, för raden "av dig · kl. 19:42". */
    val placedOutTimes: Map<PlacedOut, Instant> = emptyMap(),
    /** Sedda och stängda meddelanden från källorna. */
    val sourceMessageMemory: SourceMessageMemory = SourceMessageMemory(),
    /** Källornas namn per id, från den sparade källistan. Tom när listan inte har hämtats. */
    val sourceNames: Map<String, String> = emptyMap(),
    /** Om påminnelserna finns, alltså om notiserna inte är [DisabledNotifications]. Annars visas inget om påminnelser. */
    val remindersAvailable: Boolean = false,
    /** Om några väntande notiser inte gick att lägga in, annars `null`. Försöket upprepas vid nästa planering. */
    val reminderError: String? = null,
    /** Om Live Updates kan visas, senast läst. Läses om av `applyReminders()`. Valet i appen ändras aldrig av det. */
    val liveActivitiesEnabled: Boolean = true,
    /** Huvudadressens Live Update efter senaste planeringen, med den pågående först. Hemkortet visar den. */
    val currentLiveActivity: ExistingActivity? = null,
    /** Om Live Updaten inte gick att lägga in, annars `null`. Notisen står då kvar, och försöket upprepas vid nästa planering. */
    val liveActivityError: String? = null,
    /** Tömningar som redan är påminda: utställda, visade eller med en Live Update som syns nu. */
    val handledPickups: Set<PlacedOut> = emptySet(),
    /** Reservnotiser som väntar framför, med sina tider. */
    val reserveNotifications: Map<PlacedOut, Instant> = emptyMap(),
    /** Tömningar med en väntande Live Update. */
    val pendingActivityPickups: Set<PlacedOut> = emptySet(),
) {
    val primary: SavedAddress? get() = addresses.firstOrNull { it.isPrimary } ?: addresses.firstOrNull()

    fun address(key: AddressKey): SavedAddress? = addresses.firstOrNull { it.key == key }

    /** Notiser är på för adressen och systemet tillåter dem. `notificationsOn` är användarens val och ändras aldrig av systemet. */
    fun remindersOn(address: SavedAddress): Boolean =
        address.notificationsOn && notificationAuthorization == NotificationAuthorization.Authorized

    /** Om tömningen redan är påmind: Utställt är tryckt eller Live Updaten visas eller har visats. */
    fun handledPickup(key: AddressKey, date: DayDate): Boolean = PlacedOut(key, date) in handledPickups

    /** Tiden för adressens väntande reservnotis, annars `null`. Reserven kommer om Live Updaten inte syns eller bekräftas. */
    fun reserveNotificationDate(address: SavedAddress, now: Instant): Instant? {
        if (!remindersOn(address)) return null
        return reserveNotifications.filter { it.key.key == address.key && it.value > now }.values.minOrNull()
    }

    /**
     * "Påminnelsen har passerat" gäller bara en adress med notiser på, och inte när tömningen som dagens sista påminnelse
     * gäller redan är påmind, Live Updaten väntar eller en reservnotis ligger framför.
     */
    fun missedReminderApplies(address: SavedAddress, now: Instant): Boolean {
        // Tömningen som dagens sista påminnelse gäller: i morgon med bara kvällen före, i dag när samma morgon är på.
        val day = ReminderTime.pickupDay(StockholmClock.today(now), settings.latestTiming)
        val pickup = PlacedOut(address.key, day)
        return remindersOn(address) && pickup !in handledPickups && pickup !in pendingActivityPickups &&
            (reserveNotifications[pickup]?.let { it <= now } ?: true)
    }

    /**
     * "Tömning i morgon. Påminnelsen för i kväll har redan passerat." (eller "Tömning i dag. … i morse …") för en adress
     * med påminnelser på, när påminnelsetiden för tömningen redan passerat. Ingen ersättningsnotis skickas, eftersom varje
     * planering annars kunde skicka en ny.
     */
    fun missedReminderText(address: SavedAddress, now: Instant): String? {
        if (!missedReminderApplies(address, now)) return null
        return AddressDetail.missedReminder(schedules[address.key]?.response?.events ?: emptyList(), settings, now)
    }

    /** Samma text för den första adressen den gäller. */
    fun missedReminderText(now: Instant): String? = addresses.firstNotNullOfOrNull { missedReminderText(it, now) }

    /**
     * Kortet "Vill du bli påmind?" på hemskärmen: efter att en adress har sparats, så länge ingen påminnelse är på och
     * förslaget inte har besvarats. Inte när systemet har nekat notiser, och bara när huvudadressen har en kommande hämtning.
     */
    fun showsReminderOffer(now: Instant): Boolean {
        if (!remindersAvailable) return false
        if (storageProblem != null || settings.reminderOfferShown || notificationAuthorization == NotificationAuthorization.Denied) return false
        if (addresses.any { it.notificationsOn }) return false
        val primary = addresses.firstOrNull { it.isPrimary } ?: return false
        val events = schedules[primary.key]?.response?.events ?: return false
        return ScheduleLogic.nextPickup(events, StockholmClock.today(now)) != null
    }

    /** Hemskärmens innehåll vid [now]. Utan påminnelser står ingen rad eller reglage om dem. */
    fun homeContent(now: Instant): HomeContent = HomeContent.make(
        addresses = addresses,
        schedules = schedules,
        settings = settings,
        now = now,
        remindersAllowed = notificationAuthorization == NotificationAuthorization.Authorized,
        remindersDenied = notificationAuthorization == NotificationAuthorization.Denied,
        liveActivity = currentLiveActivity,
        liveActivitiesEnabled = liveActivitiesEnabled,
        liveActivityError = liveActivityError,
        missedReminder = addresses.firstOrNull { it.isPrimary }?.let { missedReminderText(it, now) },
        reserveAt = addresses.firstOrNull { it.isPrimary }?.let { reserveNotificationDate(it, now) },
        ownPlacedOut = ownPlacedOut,
        placedOutTimes = placedOutTimes,
    ).let { content ->
        if (remindersAvailable) {
            content
        } else {
            HomeContent(content.primary?.copy(reminder = null, rowReminder = null), content.others.map { it.copy(rowReminder = null) })
        }
    }

    /** Adressvyns innehåll med delen Påminnelser dold när påminnelserna inte finns. */
    fun withoutUnavailableReminders(detail: AddressDetail): AddressDetail =
        if (remindersAvailable) detail else detail.copy(showsReminders = false, missedReminder = null)

    /** Adressvyns innehåll vid [now], eller `null` när adressen inte finns längre. */
    fun addressDetail(key: AddressKey, now: Instant): AddressDetail? {
        val address = address(key) ?: return null
        return AddressDetail.make(
            address = address,
            schedule = schedules[key],
            settings = settings,
            sourceName = sourceNames[key.source],
            now = now,
            remindersOn = missedReminderApplies(address, now),
            reserveAt = reserveNotificationDate(address, now),
            ownPlacedOut = ownPlacedOut,
            placedOutTimes = placedOutTimes,
        ).let(::withoutUnavailableReminders)
    }
}

/**
 * Appens tillstånd: sparade adresser, inställningar och hämtade scheman, och påminnelsernas planering bakom
 * [NotificationScheduling] och [LiveActivityScheduling]. Som `AppModel` på iOS, utan hushållet.
 *
 * Funktionerna anropas från samma tråd, appens huvudtråd, som `@MainActor` på iOS. Hämtningar och planeringar körs i
 * [scope] och köas, så att två aldrig körs samtidigt och ett avbrott hos den som anropar inte avbryter köplatsen.
 */
class AppModel(
    private val api: SoporApi,
    private val store: LocalStore,
    private val notifications: NotificationScheduling,
    private val liveActivities: LiveActivityScheduling,
    private val clock: () -> Instant,
    private val scope: CoroutineScope,
    /** Appens version och bygge, till exempel "1.0.1 (301)". Sparas med källistan. */
    private val appVersion: String? = null,
) {
    private val refresher = ScheduleRefresher(api, store)
    private val refreshLock = Mutex()
    private val reminderLock = Mutex()
    private var reminderJob: Job? = null

    /** Live Updates appen själv har tagit bort. Systemet kan lista dem en stund som avslutade, och det är inget svep. */
    private val removedActivityIds = mutableSetOf<String>()

    /** När källistan senast försökte hämtas utan att lyckas, så att inte varje tangenttryck hämtar på nytt. */
    private var failedSourcesAt: Instant? = null

    /** När källistan senast hämtades för att ett meddelande saknade källans namn, så att det görs högst en gång i timmen. */
    private var sourceNamesFetchedAt: Instant? = null

    /** Om `source-messages.json` gick att läsa. Annars skickas inga notiser för meddelanden och filen skrivs inte över. */
    private var sourceMessageMemoryKnown = true

    /** Varför `addresses.json` eller `settings.json` inte går att läsa. Då skrivs filen aldrig över. */
    private enum class StoreIssue { Corrupt, Unavailable }

    private var addressesIssue: StoreIssue? = null
    private var settingsIssue: StoreIssue? = null
    private val addressesReadable get() = addressesIssue == null
    private val settingsReadable get() = settingsIssue == null

    private val _state: MutableStateFlow<AppState>
    val state: StateFlow<AppState>

    init {
        val addresses = when (val read = store.addressesState()) {
            is StoreRead.Value -> read.value
            StoreRead.Missing -> emptyList()
            StoreRead.Unreadable -> emptyList<SavedAddress>().also { addressesIssue = StoreIssue.Corrupt }
            StoreRead.Unavailable -> emptyList<SavedAddress>().also { addressesIssue = StoreIssue.Unavailable }
        }
        val settings = when (val read = store.settingsState()) {
            is StoreRead.Value -> read.value
            StoreRead.Missing -> ReminderSettings()
            StoreRead.Unreadable -> ReminderSettings().also { settingsIssue = StoreIssue.Corrupt }
            StoreRead.Unavailable -> ReminderSettings().also { settingsIssue = StoreIssue.Unavailable }
        }
        _state = MutableStateFlow(
            AppState(
                addresses = addresses,
                schedules = readSchedules(addresses),
                settings = settings,
                ownPlacedOut = store.placedOut().toSet(),
                placedOutTimes = store.placedOutTimes(),
                sourceNames = readSourceNames(),
                remindersAvailable = notifications !== DisabledNotifications,
            ),
        )
        state = _state.asStateFlow()
        updateProblem()
        loadSourceMessageMemory()
    }

    private val current: AppState get() = _state.value

    fun now(): Instant = clock()

    private fun readSchedules(addresses: List<SavedAddress>): Map<AddressKey, CachedSchedule> =
        addresses.mapNotNull { address -> store.schedule(address.key)?.let { address.key to it } }.toMap()

    private fun readSourceNames(): Map<String, String> =
        store.sources()?.response?.sources?.associate { it.id to it.name } ?: emptyMap()

    private fun updateProblem() {
        val problem = when (addressesIssue) {
            StoreIssue.Corrupt -> StorageProblem.AddressesUnreadable
            StoreIssue.Unavailable -> StorageProblem.AddressesUnavailable
            null -> when (settingsIssue) {
                StoreIssue.Corrupt -> StorageProblem.SettingsUnreadable
                StoreIssue.Unavailable -> StorageProblem.SettingsUnavailable
                null -> null
            }
        }
        _state.update { it.copy(storageProblem = problem) }
    }

    private fun setError(message: String) = _state.update { it.copy(lastStorageError = message) }

    fun clearStorageError() = _state.update { it.copy(lastStorageError = null) }

    // MARK: Lagring

    /** Läser om adresser och inställningar som inte gick att läsa. Först när läsningen lyckats ändras något. */
    private fun reloadStorageIfNeeded() {
        if (!addressesReadable) {
            when (val read = store.addressesState()) {
                is StoreRead.Value -> adopt(read.value)
                StoreRead.Missing -> adopt(emptyList())
                StoreRead.Unreadable -> addressesIssue = StoreIssue.Corrupt
                StoreRead.Unavailable -> addressesIssue = StoreIssue.Unavailable
            }
        }
        if (!settingsReadable) {
            when (val read = store.settingsState()) {
                is StoreRead.Value -> {
                    settingsIssue = null
                    _state.update { it.copy(settings = read.value) }
                }
                StoreRead.Missing -> {
                    settingsIssue = null
                    _state.update { it.copy(settings = ReminderSettings()) }
                }
                StoreRead.Unreadable -> settingsIssue = StoreIssue.Corrupt
                StoreRead.Unavailable -> settingsIssue = StoreIssue.Unavailable
            }
        }
        updateProblem()
    }

    private fun adopt(saved: List<SavedAddress>) {
        addressesIssue = null
        _state.update { it.copy(addresses = saved, schedules = readSchedules(saved)) }
    }

    /** "Försök igen": läser om filerna som inte gick att läsa. */
    fun retryStorage() {
        reloadStorageIfNeeded()
        applyReminders()
    }

    /**
     * "Börja om", efter bekräftelse, och bara för en fil vars innehåll är skadat. Den skadade filen flyttas åt sidan och
     * raderas inte. Är det adresserna börjar appen utan sparade adresser, och appens påminnelser tas bort. Är det
     * inställningarna används standardinställningarna. Går det inte att flytta filen ändras inget och felet är satt.
     */
    suspend fun startOver() {
        reloadStorageIfNeeded()
        val date = now()
        if (addressesIssue == StoreIssue.Corrupt) {
            try {
                store.moveAsideAddresses(date)
            } catch (_: Exception) {
                setError("Kunde inte flytta den skadade filen. Inget har ändrats.")
                return
            }
            addressesIssue = null
            _state.update { it.copy(addresses = emptyList(), schedules = emptyMap()) }
            val own = notifications.pending().map { it.identifier }.filter(NotificationDiff::isOwn)
            if (own.isNotEmpty()) notifications.cancel(own)
        }
        if (settingsIssue == StoreIssue.Corrupt) {
            try {
                store.moveAsideSettings(date)
            } catch (_: Exception) {
                setError("Kunde inte flytta den skadade filen. Inget har ändrats.")
                return
            }
            settingsIssue = null
            _state.update { it.copy(settings = ReminderSettings()) }
        }
        updateProblem()
        applyReminders()
    }

    // MARK: Uppdatering

    /**
     * Uppdaterar alla adresser, en i taget. Anrop köas efter varandra: ett anrop som kommer medan ett annat pågår väntar,
     * och adresser som då är nyss hämtade hoppas över av `RefreshPolicy`. [startingActivities] avgör om planeringen efter en
     * lyckad hämtning får starta en Live Update. [context] avgör om ett nytt meddelande från källan ger en notis
     * (`Background`) eller bara visas som kort (`Foreground`).
     */
    suspend fun refreshAll(manual: Boolean, startingActivities: Boolean = true, context: RefreshContext = RefreshContext.Foreground) {
        // Avbryts den som anropar (dra för att uppdatera lämnar skärmen) fortsätter köplatsen ändå, i modellens scope.
        scope.launch {
            refreshLock.withLock {
                performRefresh(manual, startingActivities)
                noteSourceMessages(context)
            }
        }.join()
    }

    private suspend fun performRefresh(manual: Boolean, startingActivities: Boolean) {
        reloadStorageIfNeeded()
        var fetchedAny = false
        for (address in current.addresses) {
            // Avbryts modellens scope hämtas inga fler adresser.
            currentCoroutineContext().ensureActive()
            // En adress som tagits bort under tiden hämtas inte.
            if (current.address(address.key) == null) continue
            val outcome = refresher.refresh(address, now(), manual)
            if (outcome == RefreshOutcome.Fetched) fetchedAny = true
            if (current.address(address.key) != null) {
                // En schemafil som inte går att läsa ersätter inte det som redan finns i minnet.
                var schedule = when (val read = store.scheduleState(address.key)) {
                    is StoreRead.Value -> read.value
                    StoreRead.Missing -> null
                    StoreRead.Unreadable, StoreRead.Unavailable -> current.schedules[address.key]
                }
                if (outcome == RefreshOutcome.StorageFailed) {
                    setError("Kunde inte spara schemat.")
                    // Försöket gick inte att spara. Utan en markering i minnet skulle en ny adress stå kvar som "hämtar".
                    schedule = (schedule ?: CachedSchedule()).copy(lastAttemptAt = now(), lastError = ApiError.Unexpected(0))
                }
                _state.update { state ->
                    val schedules = if (schedule == null) state.schedules - address.key else state.schedules + (address.key to schedule)
                    state.copy(schedules = schedules)
                }
            } else {
                // Adressen togs bort medan hämtningen pågick, så schemat ska inte bli kvar.
                removeStoredSchedule(address.key)
            }
        }
        if (fetchedAny) applyReminders(startingActivities)
    }

    // MARK: Källor

    /**
     * Källistan för kommunfrågan: den sparade om den är högst ett dygn gammal och hämtades av samma appversion, annars
     * hämtas en ny. Misslyckas hämtningen används den sparade listan, även om den är äldre. `null` när inget är sparat och
     * hämtningen misslyckas, och det betyder "okänt", aldrig "inga källor".
     */
    suspend fun sourceList(): List<Source>? {
        val saved = store.sources()
        val now = now()
        if (saved != null && saved.appVersion == appVersion && Duration.between(saved.fetchedAt, now) < SOURCES_MAX_AGE) {
            return saved.response.sources
        }
        // Finns en gammal lista väntar vi med nästa försök. Utan lista försöker vi varje gång, för Försök igen.
        val failed = failedSourcesAt
        if (saved != null && failed != null && Duration.between(failed, now) < SOURCES_RETRY_AFTER) {
            return saved.response.sources
        }
        return try {
            val fresh = api.sources()
            failedSourcesAt = null
            // Listan är bara en cache. Går den inte att spara hämtas den på nytt nästa gång.
            try {
                store.setSources(CachedSources(fresh, fetchedAt = now, appVersion = appVersion))
            } catch (_: Exception) {
            }
            _state.update { it.copy(sourceNames = fresh.sources.associate { s -> s.id to s.name }) }
            fresh.sources
        } catch (e: CancellationException) {
            // Ett avbrott (texten ändrades, skärmen stängdes) är inget misslyckande och skjuter inte upp nästa hämtning.
            currentCoroutineContext().ensureActive()
            saved?.response?.sources
        } catch (_: Exception) {
            failedSourcesAt = now
            saved?.response?.sources
        }
    }

    /** Källans namn från den sparade källistan, eller `null` när listan inte har hämtats. */
    fun sourceName(source: String): String? = store.sources()?.response?.sources?.firstOrNull { it.id == source }?.name

    // MARK: Adresser

    /**
     * Sparar adressen. En adress som redan finns läggs inte till igen men räknas som sparad. Går sparandet fel är det
     * tidigare läget kvar, felet är satt och svaret är `false`.
     */
    fun add(hit: SearchHit): Boolean {
        val key = AddressKey(hit.source, hit.id)
        val addresses = current.addresses
        if (addresses.any { it.key == key }) return true
        // Den första adressen heter "Hemma", ett område får områdets namn och övriga gatan.
        val name = if (addresses.isEmpty()) "Hemma" else hit.street
        val address = SavedAddress(
            key = key, url = hit.url, street = hit.street, locality = hit.locality, kommun = hit.kommun, detail = hit.detail,
            selection = hit.selection, displayName = name, isPrimary = false, addedAt = now(),
        )
        return saveAddresses(AddressList.add(address, addresses))
    }

    /** Tar bort adressen och dess sparade schema. Går sparandet av listan fel är allt kvar. */
    fun remove(key: AddressKey) {
        if (!saveAddresses(AddressList.remove(key, current.addresses))) return
        _state.update { it.copy(schedules = it.schedules - key) }
        removeStoredSchedule(key)
        applyReminders()
    }

    private fun removeStoredSchedule(key: AddressKey) {
        try {
            store.removeSchedule(key)
        } catch (_: Exception) {
            setError("Kunde inte ta bort det sparade schemat.")
        }
    }

    private fun saveAddresses(updated: List<SavedAddress>): Boolean {
        if (!addressesReadable) {
            setError("Adresserna går inte att läsa just nu. Inget har ändrats.")
            return false
        }
        try {
            store.setAddresses(updated)
        } catch (_: Exception) {
            setError("Kunde inte spara adressen. Inget har ändrats.")
            return false
        }
        _state.update { it.copy(addresses = updated) }
        return true
    }

    /** Byter namn. Ogiltigt namn (tomt eller över 60 tecken) eller lagringsfel ger `false` och ändrar ingenting. */
    fun rename(key: AddressKey, name: String): Boolean {
        AddressList.validName(name) ?: return false
        // Notisernas text innehåller namnet.
        val saved = saveAddresses(AddressList.rename(key, name, current.addresses))
        applyReminders()
        return saved
    }

    fun setPrimary(key: AddressKey) {
        if (!saveAddresses(AddressList.setPrimary(key, current.addresses))) return
        applyReminders()
    }

    /**
     * Ersätter en adress som källan inte längre känner igen med en nyss sparad. Namn, huvudadress och notisval följer med,
     * och den gamla tas bort först när den nya är sparad. Allt sparas i ett steg.
     */
    fun replace(old: AddressKey, new: AddressKey): Boolean {
        val addresses = current.addresses
        if (old == new) return false
        val oldAddress = addresses.firstOrNull { it.key == old } ?: return false
        val newAddress = addresses.firstOrNull { it.key == new } ?: return false
        val merged = newAddress.copy(displayName = oldAddress.displayName, isPrimary = oldAddress.isPrimary, notificationsOn = oldAddress.notificationsOn)
        val updated = addresses.mapNotNull { address ->
            when (address.key) {
                old -> null
                new -> merged
                else -> address
            }
        }
        if (!saveAddresses(updated)) return false
        _state.update { it.copy(schedules = it.schedules - old) }
        removeStoredSchedule(old)
        applyReminders()
        return true
    }

    // MARK: Utställt

    /**
     * Ställer ut kärlen för tömningen [date]: sparas i `placed-out.json` med tiden, Live Updaten avslutas och tömningens
     * notiser tas bort, som `PlacedOutAction`. Används av knappen i appen, Klart i Live Updaten och Utställt i notisen.
     */
    suspend fun markPlacedOut(key: AddressKey, date: DayDate) {
        val entry = PlacedOut(key, date)
        val today = StockholmClock.today(now())
        val saved = PlacedOutAction.perform(
            store, entry, today,
            end = { endActivities(entry) },
            cancelReminder = { notifications.cancel(listOf(it)) },
        )
        if (!saved) {
            setError("Kunde inte spara att kärlen är utställda.")
            return
        }
        // Tiden är bara för raden Utställt. Går den inte att spara står raden utan klockslag.
        try {
            store.setPlacedOutTime(entry, now())
        } catch (_: Exception) {
        }
        readPlacedOut()
        applyReminders()
    }

    /** Ångrar bocken. Påminnelsen kommer tillbaka om tiden inte har passerat. */
    suspend fun undoPlacedOut(key: AddressKey, date: DayDate) {
        val entry = PlacedOut(key, date)
        try {
            store.unmarkPlacedOut(entry)
        } catch (_: Exception) {
            setError("Kunde inte ångra. Inget har ändrats.")
            return
        }
        // Live Update får starta igen för samma tömning. Går det inte att spara startar den bara inte om.
        try {
            store.forgetActivity(entry)
        } catch (_: Exception) {
        }
        readPlacedOut()
        applyReminders()
    }

    /**
     * Avslutar tömningens Live Update. En väntande har aldrig visats och tas bort direkt. En pågående visar bocken i
     * `PlacedOutAction.checkmarkDuration` innan den försvinner.
     */
    private suspend fun endActivities(entry: PlacedOut) {
        for (item in liveActivities.current()) {
            val activity = item.activity
            if (activity.key != entry.key || activity.pickupDate != entry.date) continue
            when (item.phase) {
                LiveActivityPhase.Pending -> liveActivities.remove(activity.id)
                LiveActivityPhase.Ended, LiveActivityPhase.Dismissed -> {}
                else -> liveActivities.end(activity.id, activity.content.markedPlacedOut())
            }
            removedActivityIds += activity.id
        }
    }

    private fun readPlacedOut() {
        val placedOut = when (val read = store.placedOutState()) {
            is StoreRead.Value -> read.value.toSet()
            StoreRead.Missing, StoreRead.Unreadable -> emptySet()
            // Det går inte att veta vad som är utställt, så det som visas står kvar.
            StoreRead.Unavailable -> return
        }
        _state.update { it.copy(ownPlacedOut = placedOut, placedOutTimes = store.placedOutTimes()) }
    }

    // MARK: Inställningar

    /** Opt-in: inget schemaläggs förrän valet är på. */
    fun setLiveActivity(on: Boolean) {
        if (!saveSettings(current.settings.copy(liveActivityOn = on))) return
        applyReminders()
    }

    /**
     * Live Update som användaren slår på eller av i appen. På Android är den en notis, så frågan om notiser ställs när den
     * slås på och tillståndet inte är avgjort, som för Påminn mig. Valet sparas även när systemet nekar notiser, så att
     * rutan om avstängda notiser visas. `Denied` när systemet nekar, `Failed` när valet inte gick att spara.
     */
    suspend fun setLiveUpdate(on: Boolean): PermissionResult {
        var status = NotificationAuthorization.Authorized
        if (on) {
            status = notifications.authorization()
            if (status == NotificationAuthorization.NotDetermined) {
                status = if (notifications.requestAuthorization()) NotificationAuthorization.Authorized else NotificationAuthorization.Denied
                _state.update { it.copy(notificationAuthorization = status) }
            }
        }
        if (!saveSettings(current.settings.copy(liveActivityOn = on))) return PermissionResult.Failed
        applyReminders()
        return if (status == NotificationAuthorization.Authorized) PermissionResult.Granted else PermissionResult.Denied
    }

    /** Slår kvällen före eller samma morgon på eller av. Minst ett val är alltid på, så det sista går inte att stänga av. */
    fun setReminder(timing: ReminderTiming, on: Boolean): Boolean {
        val settings = current.settings
        val updated = when (timing) {
            ReminderTiming.EveningBefore -> settings.copy(eveningOn = on)
            ReminderTiming.SameMorning -> settings.copy(morningOn = on)
        }
        if (!updated.eveningOn && !updated.morningOn) return false
        if (updated == settings) return true
        if (!saveSettings(updated)) return false
        applyReminders()
        return true
    }

    /** Tiden för ett val, i steg om 15 minuter. Annars, eller vid lagringsfel, är allt kvar som förut. */
    fun setReminderMinutes(minutes: Int, timing: ReminderTiming): Boolean {
        if (!ReminderSettings.isValid(minutes, timing)) return false
        val settings = current.settings
        // Samma tid igen är ingen ändring: inget sparas.
        if (minutes == settings.minutes(timing)) return true
        val updated = when (timing) {
            ReminderTiming.EveningBefore -> settings.copy(reminderMinutes = minutes)
            ReminderTiming.SameMorning -> settings.copy(morningMinutes = minutes)
        }
        if (!saveSettings(updated)) return false
        applyReminders()
        return true
    }

    /** När Live Update visas. Den får tiden som notisen för det nya valet har. Vid lagringsfel är allt kvar som förut. */
    fun setLiveActivityTiming(timing: ReminderTiming): Boolean {
        val settings = current.settings
        if (timing == settings.liveActivityTiming) return true
        if (!saveSettings(settings.copy(liveActivityTiming = timing, liveActivityMinutes = settings.minutes(timing)))) return false
        forgetStoppedActivities()
        applyReminders()
        return true
    }

    /** Live Updatens egen tid. En ändrad tid är ett nytt val, så en bortsvept Live Update får starta igen. */
    fun setLiveActivityMinutes(minutes: Int): Boolean {
        val settings = current.settings
        if (!ReminderSettings.isValid(minutes, settings.liveActivityTiming)) return false
        if (minutes == settings.liveActivityStartMinutes) return true
        if (!saveSettings(settings.copy(liveActivityMinutes = minutes))) return false
        forgetStoppedActivities()
        applyReminders()
        return true
    }

    /** Valet Meddelanden från källan. Frågar aldrig om tillstånd för notiser. */
    fun setSourceMessages(on: Boolean): Boolean = saveSettings(current.settings.copy(sourceMessagesOn = on))

    /** En ändrad påminnelse är ett nytt val: en Live Update som svepts bort får starta igen med den nya tiden. */
    private fun forgetStoppedActivities() {
        try {
            store.clearShown()
            store.clearEnded()
        } catch (_: Exception) {
        }
    }

    private fun saveSettings(updated: ReminderSettings): Boolean {
        if (!settingsReadable) {
            setError("Inställningarna går inte att läsa just nu. Inget har ändrats.")
            return false
        }
        try {
            store.setSettings(updated)
        } catch (_: Exception) {
            setError("Kunde inte spara inställningen. Inget har ändrats.")
            return false
        }
        _state.update { it.copy(settings = updated) }
        return true
    }

    // MARK: Påminnelser

    /**
     * Slår notiser för en adress på eller av. Frågan om tillstånd ställs först när de slås på och tillståndet inte är
     * avgjort. Att stänga av kräver inget tillstånd.
     */
    suspend fun setNotifications(on: Boolean, key: AddressKey): PermissionResult {
        if (!on) return if (setNotificationsOn(false, key)) PermissionResult.Granted else PermissionResult.Failed
        if (current.address(key) == null) return PermissionResult.Failed
        var status = notifications.authorization()
        if (status == NotificationAuthorization.NotDetermined) {
            status = if (notifications.requestAuthorization()) NotificationAuthorization.Authorized else NotificationAuthorization.Denied
        }
        _state.update { it.copy(notificationAuthorization = status) }
        // Nekas tillstånd ändras aldrig `notificationsOn`, så att notiserna planeras igen när tillståndet kommer tillbaka.
        if (status != NotificationAuthorization.Authorized) return PermissionResult.Denied
        return if (setNotificationsOn(true, key)) PermissionResult.Granted else PermissionResult.Failed
    }

    /** "Inte nu", eller en påminnelse som slogs på: förslaget visas inte igen. */
    fun dismissReminderOffer() {
        if (current.settings.reminderOfferShown) return
        saveSettings(current.settings.copy(reminderOfferShown = true))
    }

    private fun setNotificationsOn(on: Boolean, key: AddressKey): Boolean {
        val addresses = current.addresses
        if (addresses.none { it.key == key }) return false
        val updated = addresses.map { if (it.key == key) it.copy(notificationsOn = on) else it }
        if (updated != addresses && !saveAddresses(updated)) return false
        // En påminnelse som slås på besvarar förslaget. Påminnelsen är redan sparad, så ett fel här rapporteras inte.
        if (on && !current.settings.reminderOfferShown) {
            val settings = current.settings.copy(reminderOfferShown = true)
            _state.update { it.copy(settings = settings) }
            if (settingsReadable) {
                try {
                    store.setSettings(settings)
                } catch (_: Exception) {
                }
            }
        }
        applyReminders()
        return true
    }

    /**
     * Läser systemets tillstånd, kör planeraren och ändrar bara skillnaden mot det som redan är schemalagt. Körs vid lyckad
     * hämtning, när appen öppnas, efter omstart av telefonen och när ett val ändras. Uppdateringarna köas, så att två aldrig
     * körs samtidigt. Med [startingActivities] falskt startas ingen Live Update, men de kan tas bort och uppdateras.
     */
    fun applyReminders(startingActivities: Boolean = true) {
        val previous = reminderJob
        reminderJob = scope.launch {
            previous?.join()
            reminderLock.withLock { performApplyReminders(startingActivities) }
        }
    }

    /** Väntar tills köade påminnelseuppdateringar är klara. */
    suspend fun settleReminders() {
        reminderJob?.join()
    }

    /**
     * Ordningen är planera, ändra Live Updates, läs dem på nytt, planera igen och ändra notiserna. En notis tas alltså bort
     * först när Live Updaten faktiskt finns. Ska en Live Update bort läggs dess notis in före borttagningen, så att ingen
     * tömning står utan påminnelse om processen dör mitt i. En ny startas före borttagningen av den gamla, så att ett fel
     * lämnar den gamla kvar.
     */
    private suspend fun performApplyReminders(startingActivities: Boolean) {
        reloadStorageIfNeeded()
        // Går adresserna eller inställningarna inte att läsa vet appen inte vad användaren valt, så inget ändras.
        if (!addressesReadable || !settingsReadable) return
        val status = notifications.authorization()
        val systemAllows = liveActivities.areEnabled()
        _state.update { it.copy(notificationAuthorization = status, liveActivitiesEnabled = systemAllows) }

        val current = now()
        val today = StockholmClock.today(current)
        // Rensningen är bara städning. Lyckas den inte görs den nästa gång.
        try {
            store.prunePlacedOut(today)
        } catch (_: Exception) {
        }
        val placedOut = when (val read = store.placedOutState()) {
            is StoreRead.Value -> read.value.toSet()
            StoreRead.Missing, StoreRead.Unreadable -> emptySet()
            // Det går inte att veta vad som är utställt, så inget ändras.
            StoreRead.Unavailable -> return
        }
        _state.update { it.copy(ownPlacedOut = placedOut, placedOutTimes = store.placedOutTimes()) }
        val state = this.current
        val settings = state.settings

        val primary = state.addresses.firstOrNull { it.isPrimary }?.key
        val snapshot = liveActivities.current()
        recordShown(snapshot, current, today, settings.liveActivityOn)
        val existing = snapshot.filter { it.phase.countsAsExisting }.map { it.activity }
        // En väntande vars start har passerat går inte att lita på, så den ersätter ingen notis.
        val counted = existing.filter { !LiveActivityDiff.isOverdue(it, current) }
        // Visad eller avslutad men inte längre kvar: bortsvept eller avslutad. Bara omstarten stoppas. Notisen rörs inte av
        // det, och bara en bevisat visad Live Update släcker reserven (`shownActivities` i planeraren).
        val stopped = (store.shownActivities().toSet() + store.endedActivities()) - existing.map { PlacedOut(it.key, it.pickupDate) }.toSet()
        val desired = reminderPlan(state, counted, placedOut + stopped, systemAllows).liveActivity
        val todayContent = ReminderPlanner.activityContent(today, plannerInput(state, counted, placedOut, systemAllows))
        val actions = LiveActivityDiff.actions(
            desired, existing, today, settings.liveActivityOn, primary = primary, canStart = startingActivities, now = current,
            todayContent = todayContent,
        ).toMutableList()
        // Utan läsbart schema för huvudadressen går det inte att planera någon ersättning, så dess Live Updates står kvar.
        if (settings.liveActivityOn && primary != null && state.schedules[primary]?.response == null) {
            val protected = existing.filter { it.key == primary }.map { it.id }.toSet()
            actions.removeAll { (it is LiveActivityAction.Remove && it.id in protected) || (it is LiveActivityAction.End && it.id in protected) }
        }

        val removals = actions.mapNotNull {
            when (it) {
                is LiveActivityAction.Remove -> it.id
                is LiveActivityAction.End -> it.id
                else -> null
            }
        }
        // Live Updates som visar bocken för Utställt en kort stund innan de avslutas.
        val endings = actions.filterIsInstance<LiveActivityAction.End>().associate { it.id to it.content }
        if (removals.isNotEmpty() && status == NotificationAuthorization.Authorized) {
            // Även en passerad väntande finns kvar hos systemet, och dess reservnotis ska ligga kvar.
            val remaining = existing.filter { it.id !in removals }
            val safe = reminderPlan(state, remaining, placedOut, systemAllows)
            applyNotifications(state, safe.notifications, removing = false)
        }

        val notStarted = mutableListOf<PlannedLiveActivity>()
        var startFailed = false
        for (action in actions) {
            when (action) {
                is LiveActivityAction.Remove, is LiveActivityAction.End -> {}
                is LiveActivityAction.Update -> liveActivities.update(action.id, action.content)
                is LiveActivityAction.Start -> {
                    val activity = action.activity
                    try {
                        liveActivities.start(activity)
                        // En direktstart syns med en gång, och är bevis för att tömningen har visats.
                        if (activity.startMode(current) == StartMode.Immediately) {
                            try {
                                store.markShown(listOf(PlacedOut(activity.key, activity.pickupDate)), today)
                            } catch (_: Exception) {
                            }
                        }
                    } catch (e: kotlin.coroutines.cancellation.CancellationException) {
                        throw e
                    } catch (_: LiveActivityNotInForeground) {
                        notStarted += activity
                    } catch (_: Exception) {
                        notStarted += activity
                        startFailed = true
                    }
                }
            }
        }
        for (id in removals) {
            // Kunde den nya inte startas är den gamla för samma tömning bättre än ingen.
            val activity = existing.firstOrNull { it.id == id }
            if (notStarted.any { it.key == activity?.key && it.pickupDate == activity.pickupDate }) continue
            removedActivityIds += id
            val content = endings[id]
            if (content != null) liveActivities.end(id, content) else liveActivities.remove(id)
        }
        // En inaktuell räknas inte, och den visas inte längre med rätt innehåll.
        for (item in snapshot) {
            if (item.phase != LiveActivityPhase.Stale) continue
            removedActivityIds += item.activity.id
            liveActivities.remove(item.activity.id)
        }
        if (startFailed) {
            _state.update { it.copy(liveActivityError = LIVE_ACTIVITY_ERROR) }
        } else if (notStarted.isEmpty() && (startingActivities || !settings.liveActivityOn)) {
            _state.update { it.copy(liveActivityError = null) }
        }

        // Det är de Live Updates som faktiskt finns nu som avgör om notisen behövs, inte de som skulle ha startats.
        val remainingNow = liveActivities.current()
            .filter { it.phase.countsAsExisting && it.activity.id !in removedActivityIds }
            .map { it.activity }
        val actual = remainingNow.filter { !LiveActivityDiff.isOverdue(it, current) }
        val own = actual.filter { it.key == primary }
        val handled = placedOut + store.shownActivities() + actual.filter { !it.isPending }.map { PlacedOut(it.key, it.pickupDate) }
        _state.update {
            it.copy(
                currentLiveActivity = own.firstOrNull { a -> !a.isPending } ?: own.minByOrNull { a -> a.start },
                pendingActivityPickups = actual.filter { a -> a.isPending }.map { a -> PlacedOut(a.key, a.pickupDate) }.toSet(),
                handledPickups = handled,
                reserveNotifications = emptyMap(),
            )
        }

        // Utan tillstånd rörs inga notiser: `notificationsOn` är kvar, och när tillståndet kommer tillbaka planeras de igen.
        if (status != NotificationAuthorization.Authorized) return
        // En passerad väntande är inget bevis för en visning, men reservnotisen täcker den med riktig tid.
        val finalInput = plannerInput(state, remainingNow, placedOut, systemAllows)
        val final = ReminderPlanner.plan(finalInput)
        // En reserv som redan väntar och ligger framför står kvar, även när ordinarie tid har passerat och planen saknar den.
        val retained = ReminderPlanner.retainable(finalInput)
        val pendingFireDates = applyNotifications(state, final.notifications, removing = true, retaining = retained.keys)
        val reserves = mutableMapOf<PlacedOut, Instant>()
        for (notification in final.notifications) {
            if (notification.title == ReminderPlanner.FALLBACK_TITLE) reserves[PlacedOut(notification.key, notification.pickupDate)] = notification.fireDate
        }
        // En kvarlämnad notis kallas reserv bara när Live Update är på. Annars är den en ordinarie notis som står kvar efter
        // att tiden ändrats, och raderna ska inte kalla den reserv.
        if (settings.liveActivityOn && systemAllows) {
            for ((id, entry) in retained) {
                if (entry in reserves) continue
                val fireDate = pendingFireDates[id] ?: continue
                if (fireDate > current) reserves[entry] = fireDate
            }
        }
        _state.update { it.copy(reserveNotifications = reserves) }
    }

    /**
     * Sparar vad appen vet om en tömnings Live Update. Pågående är bevis för att den syntes (`shown`) och släcker
     * reservnotisen. Avslutad eller bortsvept efter starten (`ended`) stoppar bara omstarten. Är valet av töms båda listorna,
     * så att samma tömning kan starta när valet slås på igen. Ett skrivfel gör bara att Live Updaten kan startas igen.
     */
    private fun recordShown(snapshot: List<SystemActivity>, now: Instant, today: DayDate, liveActivityOn: Boolean) {
        try {
            if (!liveActivityOn) {
                store.clearShown()
                store.clearEnded()
                return
            }
            val candidates = snapshot.filter { it.activity.id !in removedActivityIds }
            val shown = candidates.filter { it.phase == LiveActivityPhase.Active }
            val ended = candidates.filter {
                (it.phase == LiveActivityPhase.Ended || it.phase == LiveActivityPhase.Dismissed) && it.activity.start <= now
            }
            // Även utan nya poster, så att passerade rensas.
            store.markShown(shown.map { PlacedOut(it.activity.key, it.activity.pickupDate) }, today)
            store.markEnded(ended.map { PlacedOut(it.activity.key, it.activity.pickupDate) }, today)
        } catch (_: Exception) {
        }
    }

    private fun plannerInput(state: AppState, existing: List<ExistingActivity>, placedOut: Set<PlacedOut>, activitiesAllowed: Boolean) = PlannerInput(
        addresses = state.addresses.map { PlannerAddress(it, state.schedules[it.key]) },
        settings = state.settings,
        placedOut = placedOut,
        now = now(),
        liveActivitiesAllowed = activitiesAllowed,
        existingActivities = existing.map { PlacedOut(it.key, it.pickupDate) }.toSet(),
        // En pågående Live Update syns, och en tidigare visad är sparad. Då behövs ingen reservnotis.
        shownActivities = store.shownActivities().toSet() + existing.filter { !it.isPending }.map { PlacedOut(it.key, it.pickupDate) },
        activityStarts = existing.groupBy { PlacedOut(it.key, it.pickupDate) }.mapValues { (_, list) -> list.minOf { it.start } },
    )

    private fun reminderPlan(state: AppState, existing: List<ExistingActivity>, placedOut: Set<PlacedOut>, activitiesAllowed: Boolean): ReminderPlan =
        ReminderPlanner.plan(plannerInput(state, existing, placedOut, activitiesAllowed))

    /**
     * Ändrar bara skillnaden mot de väntande notiserna. Med [removing] falskt läggs de bara in, och ingen tas bort. Svarar
     * med de väntande notisernas tider efter ändringen, per identifierare.
     */
    private suspend fun applyNotifications(
        state: AppState,
        desired: List<PlannedNotification>,
        removing: Boolean,
        retaining: Set<String> = emptySet(),
    ): Map<String, Instant> {
        // Bara notiser som appen själv lagt in räknas, även om schemaläggaren skulle lämna fler.
        val pending = notifications.pending().filter { NotificationDiff.isOwn(it.identifier) }
        val pendingDates = pending.mapNotNull { p -> p.fireDate?.let { p.identifier to it } }.toMap()
        val changes = NotificationDiff.diff(
            desired = desired,
            pendingIds = pending.map { it.identifier }.toSet(),
            pendingFireDates = pendingDates,
            pendingBodies = pending.associate { it.identifier to it.body },
            retain = if (removing) retaining else emptySet(),
            now = now(),
        )
        if (removing) {
            // En adress med påminnelser på men utan läsbart schema behåller sina väntande notiser tills ett schema finns.
            val protected = state.addresses.filter { it.notificationsOn && state.schedules[it.key]?.response == null }.map { "${it.key.fileName}-" }
            // En ersatt notis läggs in med samma identifierare, som ersätter den gamla. Den tas därför inte bort först.
            val replaced = changes.add.map { it.identifier }.toSet()
            val removals = changes.removeIds.filter { id -> id !in replaced && protected.none { id.startsWith(it) } }
            if (removals.isNotEmpty()) notifications.cancel(removals)
        }
        val failed = if (changes.add.isEmpty()) emptyList() else notifications.schedule(changes.add)
        _state.update { it.copy(reminderError = if (failed.isEmpty()) null else REMINDER_ERROR) }
        val dates = pendingDates.toMutableMap()
        for (id in changes.removeIds) if (changes.add.none { it.identifier == id }) dates.remove(id)
        for (notification in changes.add) if (notification.identifier !in failed) dates[notification.identifier] = notification.fireDate
        return dates
    }

    // MARK: Meddelanden från källan

    /** Stänger kortet. Går minnet inte att läsa stängs det bara tills appen startas om, och filen skrivs inte över. */
    fun dismissSourceMessage(item: ActiveSourceMessage) {
        val memory = current.sourceMessageMemory.dismiss(item.key)
        _state.update { it.copy(sourceMessageMemory = memory) }
        if (!sourceMessageMemoryKnown) return
        try {
            store.setSourceMessageMemory(memory)
        } catch (_: Exception) {
        }
    }

    private fun loadSourceMessageMemory() {
        when (val read = store.sourceMessageMemoryState()) {
            is StoreRead.Value -> {
                sourceMessageMemoryKnown = true
                _state.update { it.copy(sourceMessageMemory = read.value) }
            }
            StoreRead.Missing -> {
                sourceMessageMemoryKnown = true
                _state.update { it.copy(sourceMessageMemory = SourceMessageMemory()) }
            }
            StoreRead.Unreadable, StoreRead.Unavailable -> sourceMessageMemoryKnown = false
        }
    }

    /**
     * Körs efter varje uppdatering. Meddelanden som inte är sedda räknas som sedda, och i bakgrunden ges först en notis per
     * meddelande. Går minnet inte att läsa händer ingenting, så att ingen får samma notis två gånger.
     */
    private suspend fun noteSourceMessages(context: RefreshContext) {
        if (!sourceMessageMemoryKnown) loadSourceMessageMemory()
        fetchMissingSourceNames()
        if (!sourceMessageMemoryKnown) return
        val today = StockholmClock.today(now())
        val fresh = SourceMessages.unseen(current.activeSourceMessages(today), current.sourceMessageMemory)
        if (fresh.isEmpty()) return
        // Sett först, så att en notis aldrig skickas för ett meddelande som inte gick att spara som sett.
        val updated = current.sourceMessageMemory.markSeen(fresh.map { it.key })
        try {
            store.setSourceMessageMemory(updated)
        } catch (_: Exception) {
            return
        }
        _state.update { it.copy(sourceMessageMemory = updated) }
        if (context != RefreshContext.Background || !current.settings.sourceMessagesOn) return
        if (notifications.authorization() != NotificationAuthorization.Authorized) return
        for (item in fresh) {
            notifications.deliverNow(
                identifier = SourceMessages.notificationId(item.key),
                title = sourceName(item.source) ?: SOURCE_MESSAGE_FALLBACK_TITLE,
                body = item.message.title,
            )
        }
    }

    /**
     * Länken ("Läs mer hos …") och notisens rubrik behöver källans namn, som bara finns i källistan. Den hämtas när ett
     * meddelande som gäller saknar namnet, högst en gång i timmen, och sparas av `sourceList()` i ett dygn.
     */
    private suspend fun fetchMissingSourceNames() {
        val today = StockholmClock.today(now())
        if (current.activeSourceMessages(today).none { sourceName(it.source) == null }) {
            _state.update { it.copy(sourceNames = readSourceNames()) }
            return
        }
        val last = sourceNamesFetchedAt
        if (last != null && Duration.between(last, now()) < SOURCES_RETRY_AFTER) return
        sourceNamesFetchedAt = now()
        sourceList()
        _state.update { it.copy(sourceNames = readSourceNames()) }
    }

    companion object {
        /** Rubriken på notisen när källans namn inte är känt. */
        const val SOURCE_MESSAGE_FALLBACK_TITLE = "Sophämtning"

        internal const val REMINDER_ERROR = "Några påminnelser kunde inte läggas in. Appen försöker igen nästa gång den öppnas."
        internal const val LIVE_ACTIVITY_ERROR = "Live Update kunde inte läggas in. Appen försöker igen nästa gång den öppnas."

        private val SOURCES_MAX_AGE: Duration = Duration.ofHours(24)
        private val SOURCES_RETRY_AFTER: Duration = Duration.ofHours(1)
    }
}
