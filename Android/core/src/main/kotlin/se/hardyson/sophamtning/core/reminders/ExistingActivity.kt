package se.hardyson.sophamtning.core.reminders

import java.time.Instant
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.storage.AddressKey

/**
 * En Live Update som finns hos systemet: väntande (ett alarm är satt) eller pågående (notisen visas). Som `ExistingActivity`
 * på iOS. Hur den startas och avslutas på Android bestäms i appen.
 */
data class ExistingActivity(
    val id: String,
    val key: AddressKey,
    val pickupDate: DayDate,
    val content: PickupActivityContent,
    val isPending: Boolean,
    /** Den planerade starten. */
    val start: Instant,
)
