package se.hardyson.sophamtning.core.reminders

import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.PlacedOut

/**
 * Knappen **Utställt** i påminnelsenotisen. Notisen bär adressens nyckel och tömningens datum, så att knappen kan markera
 * tömningen som utställd utan att appen öppnas, på samma sätt som **Klart** i Live Updaten.
 */
object PlacedOutNotification {
    /** Notiskategorin som har knappen. Alla påminnelsenotiser, också reserven, har den. */
    const val CATEGORY_IDENTIFIER = "paminnelse"
    const val ACTION_IDENTIFIER = "utstallt"
    const val ACTION_TITLE = "Utställt"

    private const val SOURCE_KEY = "kalla"
    private const val ID_KEY = "adressId"
    private const val DATE_KEY = "datum"

    /** Det som notisen bär, till exempel som extra data i en `Intent`. Adress-id:t sparas som det är och byggs aldrig om. */
    fun userInfo(key: AddressKey, date: DayDate): Map<String, String> =
        mapOf(SOURCE_KEY to key.source, ID_KEY to key.id, DATE_KEY to date.iso)

    /** Tömningen som notisen gäller, eller `null` för en notis som saknar något av fälten. */
    fun entry(userInfo: Map<String, Any?>): PlacedOut? {
        val source = userInfo[SOURCE_KEY] as? String ?: return null
        val id = userInfo[ID_KEY] as? String ?: return null
        val date = (userInfo[DATE_KEY] as? String)?.let(DayDate::parse) ?: return null
        return PlacedOut(AddressKey(source, id), date)
    }
}
