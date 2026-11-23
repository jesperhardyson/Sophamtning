package se.hardyson.sophamtning.core.reminders

import se.hardyson.sophamtning.core.storage.SavedAddress

/** Texterna under korten Notiser, Live Update och Huvudadress i Inställningar, och under adresserna på sidan Notiser. */
object ReminderSettingsTexts {
    /** Adresserna i hemskärmens ordning: huvudadressen först, sedan de andra som de sparades. */
    fun homeOrder(addresses: List<SavedAddress>): List<SavedAddress> = addresses.filter { it.isPrimary } + addresses.filter { !it.isPrimary }

    /** Under kortet Notiser: vilka adresser som får notiser, i hemskärmens ordning. */
    fun notificationsFooter(addresses: List<String>): String {
        val last = addresses.lastOrNull() ?: return "Ingen adress har notiser på. Slå på Påminn mig i adressen."
        val names = if (addresses.size == 1) last else addresses.dropLast(1).joinToString(", ") + " och " + last
        return "Gäller $names. Slå på eller av i varje adress."
    }

    /** Under kortet Live Update, när det finns en huvudadress. */
    fun liveActivityFooter(primary: String) = "Visas för huvudadressen, $primary."

    /** Under kortet Huvudadress. Android har ingen Siri, men rutan i snabbinställningarna gäller huvudadressen. */
    const val PRIMARY_FOOTER = "Används av Live Update, widgetar och snabbinställningar."

    /** Under adresserna på sidan Notiser. */
    const val ADDRESSES_FOOTER = "Samma som Påminn mig i varje adress. Stäng av alla för att inte få några notiser."

    /** Under reglaget Meddelanden från källan. */
    fun sourceMessagesFooter(authorized: Boolean): String {
        val base = "Notis när källan har ett viktigt besked, till exempel att hämtrutterna läggs om. Skilt från påminnelserna."
        return if (authorized) base else "$base Notiser är avstängda för appen."
    }
}
