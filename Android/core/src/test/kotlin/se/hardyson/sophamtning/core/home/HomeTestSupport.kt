package se.hardyson.sophamtning.core.home

import java.time.Instant
import se.hardyson.sophamtning.core.api.Address
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.Links
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.api.SchedulePeriod
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.reminders.ExistingActivity
import se.hardyson.sophamtning.core.reminders.PickupActivityContent
import se.hardyson.sophamtning.core.schedule.day
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.storage.savedAddress

// Hjälpen i HomeContentTests på iOS, som också adressvyns och widgetens tester använder.

internal val homeMonday = day("2026-11-09")
internal val homeToday = day("2026-11-06")

/** Fredag 6 november 2026 klockan 12:00 svensk tid. */
internal val homeNow: Instant = StockholmClock.dateOn(homeToday, 12 * 60)

internal val homeInfo = mapOf(
    "rest" to FractionInfo(name = "Restavfall", short = "Rest", color = "#474C48", icon = "trash-2"),
    "mat" to FractionInfo(name = "Matavfall", short = "Mat", color = "#7A4A1E", icon = "apple"),
    "plast" to FractionInfo(name = "Plastförpackningar", short = "Plast", color = "#A8431F", icon = "cup-soda"),
)

internal fun homeEvent(iso: String, fractions: List<String>, estimated: Boolean = false) =
    PickupEvent(date = day(iso), fractions = fractions, estimated = estimated, deviation = null, warning = null, labels = emptyMap())

internal fun homeSchedule(
    events: List<PickupEvent>,
    savedToday: String = "2026-11-06",
    lastError: ApiError? = null,
    fractions: Map<String, FractionInfo> = homeInfo,
    period: SchedulePeriod? = null,
): CachedSchedule {
    val response = AddressResponse(
        today = day(savedToday),
        address = Address(id = "a", street = "Storgatan 12 B", locality = "Krylbo", kommun = "Avesta", source = "x", detail = null, selection = "address", notice = null),
        next = emptyList(), summary = "Gammal text", events = events, bins = emptyList(), fractions = fractions,
        links = Links(ics = "https://example.com/a.ics", web = "https://example.com/a"),
        updatedAt = day(savedToday),
        schedule = period,
    )
    return CachedSchedule(response = response, fetchedAt = homeNow, lastAttemptAt = homeNow, lastError = lastError)
}

internal fun saved(id: String, name: String, street: String, locality: String, kommun: String = "Avesta kommun", primary: Boolean, notifications: Boolean = false): SavedAddress =
    savedAddress(key = AddressKey(source = "x", id = id), isPrimary = primary)
        .copy(displayName = name, street = street, locality = locality, kommun = kommun, notificationsOn = notifications)

internal val homeAddress = saved("home", name = "Hemma", street = "Storgatan 12 B", locality = "Krylbo", primary = true)
internal val cabinAddress = saved("cabin", name = "Stugan", street = "Bergsvägen 4", locality = "Horndal", primary = false)

internal fun activity(pending: Boolean, start: Instant, key: AddressKey = homeAddress.key, pickupDate: DayDate = homeMonday) = ExistingActivity(
    id = "a", key = key, pickupDate = pickupDate,
    content = PickupActivityContent(addressName = "Hemma", dateText = "Måndag 9 november", shortDateText = "Mån 9 nov", fractions = emptyList(), estimated = false, warning = null),
    isPending = pending, start = start,
)
