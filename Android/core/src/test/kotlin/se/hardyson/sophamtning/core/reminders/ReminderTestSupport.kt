package se.hardyson.sophamtning.core.reminders

import java.time.Instant
import java.time.LocalDateTime
import se.hardyson.sophamtning.core.api.Address
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.Links
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.SavedAddress

/** "2026-11-08T20:00" som väggklocka i Europe/Stockholm. */
internal fun stockholm(text: String): Instant = LocalDateTime.parse(text).atZone(StockholmClock.zone).toInstant()

internal fun utc(iso: String): Instant = Instant.parse(iso)

internal fun event(iso: String, fractions: List<String>, estimated: Boolean = false, warning: String? = null) =
    PickupEvent(date = day(iso), fractions = fractions, estimated = estimated, deviation = null, warning = warning, labels = emptyMap())

internal fun event(date: DayDate, fractions: List<String> = listOf("rest")) =
    PickupEvent(date = date, fractions = fractions, estimated = false, deviation = null, warning = null, labels = emptyMap())

/** Ett svar för adressen med givna händelser och fraktioner. */
internal fun response(
    key: AddressKey,
    events: List<PickupEvent>,
    fractions: Map<String, FractionInfo>,
    street: String = "Gatan 1",
    locality: String = "Orten",
    kommun: String = "Kommunen",
) = AddressResponse(
    today = day("2026-11-06"),
    address = Address(id = key.id, street = street, locality = locality, kommun = kommun, source = key.source, detail = null, selection = "address", notice = null),
    next = emptyList(),
    summary = "",
    events = events,
    bins = emptyList(),
    fractions = fractions,
    links = Links(ics = "https://example.com/a.ics", web = "https://example.com/a"),
    updatedAt = day("2026-11-06"),
)

internal fun cached(response: AddressResponse, fetchedAt: Instant = utc("2026-11-06T10:00:00Z")) =
    CachedSchedule(response = response, fetchedAt = fetchedAt)

internal fun address(
    key: AddressKey,
    name: String,
    primary: Boolean,
    notifications: Boolean = false,
    street: String = "Gatan 1",
    locality: String = "Orten",
    kommun: String = "Kommunen",
    addedAt: Instant = Instant.ofEpochSecond(1_700_000_000),
) = SavedAddress(
    key = key, url = "https://example.com/${key.fileName}", street = street, locality = locality, kommun = kommun,
    detail = null, selection = "address", displayName = name, isPrimary = primary, notificationsOn = notifications, addedAt = addedAt,
)
