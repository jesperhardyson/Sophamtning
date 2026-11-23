package se.hardyson.sophamtning.core.kommun

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Locale

/**
 * Länken som lägger in adressens schema som en kalender: `links.ics` med schemat `webcal://`. På Android öppnar raden Google
 * Kalenders länk för att prenumerera, med webcal-adressen som parameter. Appen läser aldrig kalendern. Bara `https://`-länkar
 * görs om.
 */
object CalendarLink {
    /** Rubriken över kortet i adressvyn. */
    const val SECTION = "Kalender"
    const val TITLE = "Lägg till i Google Kalender"

    /** Texten under raden. `links.ics` har ett larm kl. 18 kvällen före varje tömning, och det säger texten. */
    const val FOOTER =
        "Tömningarna läggs in som en egen kalender i Google Kalender, som uppdateras av sig själv. Kalendern påminner kl. 18 kvällen innan, utöver appens notiser."

    private const val GOOGLE_CALENDAR = "https://calendar.google.com/calendar/render?cid="

    /** `links.ics` med schemat `webcal`, eller `null` för allt som inte är `https`. Resten av adressen ändras inte. */
    fun webcal(url: String?): String? {
        url ?: return null
        val colon = url.indexOf(':')
        if (colon < 0 || url.substring(0, colon).lowercase(Locale.ROOT) != "https") return null
        return "webcal" + url.substring(colon)
    }

    /**
     * Google Kalenders länk för att prenumerera på [ics]: `https://calendar.google.com/calendar/render?cid=` och webcal-adressen
     * kodad som en parameter. Ett `%` i adressen kodas också, så att adressen kommer fram oförändrad. `null` utan `https`.
     */
    fun googleCalendar(ics: String): String? {
        val webcal = webcal(ics) ?: return null
        // URLEncoder kodar mellanslag som "+", vilket bara gäller formulär. I en adress är det "%20".
        return GOOGLE_CALENDAR + URLEncoder.encode(webcal, StandardCharsets.UTF_8).replace("+", "%20")
    }
}
