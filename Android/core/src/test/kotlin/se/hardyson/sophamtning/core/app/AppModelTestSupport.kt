package se.hardyson.sophamtning.core.app

import java.time.Instant
import java.util.concurrent.atomic.AtomicReference
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.api.SoporApi
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.storage.PlacedOut

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

/** Påminnelser som minns notiserna som visats direkt och vilka tömningar som avslutats eller tagits bort. */
internal class RecordingReminders(var status: NotificationAuthorization = NotificationAuthorization.Authorized) : ReminderScheduling {
    data class Delivered(val id: String, val title: String, val body: String)

    val delivered = mutableListOf<Delivered>()
    val cancelled = mutableListOf<String>()
    val ended = mutableListOf<PlacedOut>()
    var requests = 0
    var applied = 0
    var cancelledAll = 0
    var grant = false

    override suspend fun authorization() = status
    override suspend fun requestAuthorization(): Boolean {
        requests++
        if (grant) status = NotificationAuthorization.Authorized
        return grant
    }
    override suspend fun apply(request: ReminderRequest) { applied++ }
    override suspend fun cancel(identifiers: List<String>) { cancelled += identifiers }
    override suspend fun cancelAll() { cancelledAll++ }
    override suspend fun endLiveUpdate(entry: PlacedOut) { ended += entry }
    override suspend fun deliverNow(identifier: String, title: String, body: String) { delivered += Delivered(identifier, title, body) }
}

internal fun hit(id: String, source: String = "orebro", locality: String = "Örebro", kommun: String = "Örebro") = SearchHit(
    id = id, street = "Storgatan $id", locality = locality, kommun = kommun, source = source, detail = null, selection = "address",
    notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/$source/$id",
)
