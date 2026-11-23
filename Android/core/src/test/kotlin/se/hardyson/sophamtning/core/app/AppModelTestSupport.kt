package se.hardyson.sophamtning.core.app

import java.time.Instant
import java.util.concurrent.atomic.AtomicReference
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.reminders.ExistingActivity
import se.hardyson.sophamtning.core.reminders.LiveActivityPhase
import se.hardyson.sophamtning.core.reminders.LiveActivityScheduling
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.NotificationScheduling
import se.hardyson.sophamtning.core.reminders.PendingNotification
import se.hardyson.sophamtning.core.reminders.PickupActivityContent
import se.hardyson.sophamtning.core.reminders.PlannedLiveActivity
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.reminders.ReminderPlanner
import se.hardyson.sophamtning.core.reminders.SystemActivity

/** Ett API där bara det som testet anropar svarar. Allt annat är ett fel i testet. */
internal open class UnusedApi : SoporApi {
    override suspend fun search(query: String, source: String?): SearchResponse = error("Används inte")
    override suspend fun areas(place: String): SearchResponse = error("Används inte")
    override suspend fun areas(place: String, lastEmptied: DayDate): SearchResponse = error("Används inte")
    override suspend fun address(url: String): AddressResponse = error("Används inte")
    override suspend fun sources(): SourcesResponse = error("Används inte")
}

/** En klocka som testet kan flytta. */
internal class TestClock(start: Instant) {
    private val value = AtomicReference(start)
    val now: Instant get() = value.get()
    fun set(new: Instant) = value.set(new)
    fun advance(seconds: Long) = value.updateAndGet { it.plusSeconds(seconds) }
}

/** Händelser i ordning, gemensam för notiser och Live Updates, så att testerna kan se vad som kom först. */
internal class Log {
    private val items = mutableListOf<String>()
    fun add(item: String) = synchronized(items) { items += item }
    val all: List<String> get() = synchronized(items) { items.toList() }
    fun clear() = synchronized(items) { items.clear() }
}

/**
 * Notiser i minnet, som `FakeScheduler` och `FakeNotifications` i testerna på iOS. Med [foreign] ger `pending()` också en
 * notis som inte är appens egen, som aldrig ska röras.
 */
internal class FakeNotifications(
    status: NotificationAuthorization = NotificationAuthorization.Authorized,
    /** Svaret på frågan om tillstånd. */
    private val answer: Boolean = true,
    private val foreign: Boolean = false,
    val log: Log = Log(),
) : NotificationScheduling {
    data class Delivered(val id: String, val title: String, val body: String)

    @Volatile var status: NotificationAuthorization = status
    private val store = linkedMapOf<String, PlannedNotification>()
    private var failing = emptySet<String>()
    val foreignId = "annan-app-notis"
    val delivered = mutableListOf<Delivered>()
    val cancelled = mutableListOf<String>()
    var requests = 0
        private set
    var scheduleCalls = 0
        private set

    /** Hur ofta tillståndet har lästs, alltså ungefär hur ofta påminnelserna har planerats. */
    var authorizationReads = 0
        private set

    override suspend fun authorization(): NotificationAuthorization {
        authorizationReads++
        return status
    }

    override suspend fun requestAuthorization(): Boolean {
        requests++
        status = if (answer) NotificationAuthorization.Authorized else NotificationAuthorization.Denied
        return answer
    }

    override suspend fun pending(): List<PendingNotification> = synchronized(store) {
        store.values.map { PendingNotification(it.identifier, it.fireDate, it.body) } +
            if (foreign) listOf(PendingNotification(foreignId, null, "Annat")) else emptyList()
    }

    override suspend fun schedule(notifications: List<PlannedNotification>): List<String> {
        scheduleCalls++
        val failed = mutableListOf<String>()
        for (n in notifications) {
            if (n.identifier in failing) failed += n.identifier else synchronized(store) { store[n.identifier] = n }
        }
        for (n in notifications) if (n.identifier !in failing) log.add("notis+ ${n.pickupDate.iso}")
        return failed
    }

    override suspend fun cancel(identifiers: List<String>) {
        cancelled += identifiers
        synchronized(store) { identifiers.forEach { store.remove(it) } }
        for (id in identifiers) log.add("notis- ${id.takeLast(10)}")
    }

    override suspend fun deliverNow(identifier: String, title: String, body: String) {
        delivered += Delivered(identifier, title, body)
    }

    fun failAll(on: Boolean, ids: List<String>) {
        failing = if (on) ids.toSet() else emptySet()
    }

    fun resetCalls() {
        cancelled.clear()
        scheduleCalls = 0
    }

    /** De väntande notiserna i tidsordning. */
    val planned: List<PlannedNotification> get() = synchronized(store) { store.values.sortedBy { it.fireDate } }

    val dates: List<String> get() = synchronized(store) { store.values.map { it.pickupDate.iso }.sorted() }

    /** Den väntande notisen för tömningen, om det finns någon. */
    fun notification(iso: String): PlannedNotification? = synchronized(store) { store.values.firstOrNull { it.pickupDate.iso == iso } }

    /** Sant när notisen är reservnotisen. */
    fun isFallback(iso: String) = notification(iso)?.title == ReminderPlanner.FALLBACK_TITLE
}

internal class StartFailed : Exception()

/** Systemets Live Updates i minnet, som `FakeActivities` i testerna på iOS. */
internal class FakeActivities(val log: Log = Log(), enabled: Boolean = true) : LiveActivityScheduling {
    private val list = mutableListOf<SystemActivity>()
    private var counter = 0
    private var failure: Exception? = null
    @Volatile var enabled = enabled

    /** Systemet listar en Live Update en stund till efter att appen avslutat den. */
    var keepsRemoved = false
    val starts = mutableListOf<PlannedLiveActivity>()
    val updates = mutableListOf<String>()

    /** Live Updates som avslutats med bocken för Utställt. */
    val endedWithPlacedOut = mutableListOf<String>()

    override suspend fun areEnabled() = enabled

    override suspend fun current(): List<SystemActivity> = synchronized(list) { list.toList() }

    override suspend fun start(activity: PlannedLiveActivity) {
        failure?.let { throw it }
        synchronized(list) {
            counter += 1
            starts += activity
            list += SystemActivity(
                ExistingActivity("a$counter", activity.key, activity.pickupDate, activity.content, !activity.startsImmediately, activity.start),
                if (activity.startsImmediately) LiveActivityPhase.Active else LiveActivityPhase.Pending,
            )
        }
        log.add("start ${activity.pickupDate.iso}")
    }

    override suspend fun update(id: String, content: PickupActivityContent) {
        synchronized(list) {
            updates += id
            list.replaceAll { if (it.activity.id == id) it.copy(activity = it.activity.copy(content = content)) else it }
        }
        log.add("update $id")
    }

    override suspend fun remove(id: String) {
        synchronized(list) {
            if (keepsRemoved) {
                list.replaceAll { if (it.activity.id == id) it.copy(phase = LiveActivityPhase.Dismissed) else it }
            } else {
                list.removeAll { it.activity.id == id }
            }
        }
        log.add("remove $id")
    }

    override suspend fun end(id: String, content: PickupActivityContent) {
        synchronized(list) {
            if (content.placedOut) endedWithPlacedOut += id
            list.removeAll { it.activity.id == id }
        }
        log.add("end $id")
    }

    fun setFailing(on: Boolean, error: Exception = StartFailed()) {
        failure = if (on) error else null
    }

    /** Användaren sveper bort Live Updaten, eller systemet avslutar den. */
    fun setPhase(phase: LiveActivityPhase, id: String) = synchronized(list) {
        list.replaceAll { if (it.activity.id == id) it.copy(phase = phase) else it }
    }

    fun insert(item: SystemActivity) = synchronized(list) { list += item }

    fun clearAll() = synchronized(list) { list.clear() }

    /** Alarmet går, och den väntande Live Updaten visas. */
    fun promote() = synchronized(list) {
        list.replaceAll { it.copy(activity = it.activity.copy(isPending = false), phase = LiveActivityPhase.Active) }
    }

    val ids: List<String> get() = synchronized(list) { list.map { it.activity.id } }
    val activities: List<ExistingActivity> get() = synchronized(list) { list.map { it.activity } }
}

internal fun hit(id: String, source: String = "orebro", locality: String = "Örebro", kommun: String = "Örebro") = SearchHit(
    id = id, street = "Storgatan $id", locality = locality, kommun = kommun, source = source, detail = null, selection = "address",
    notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/$source/$id",
)
