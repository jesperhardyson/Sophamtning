package se.hardyson.sophamtning.core.kommun

import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.api.SourceContact

/**
 * En länk i kortet "Ansvarar för hämtningen", i kortet Kalender och på sidan Datakällor. Bara det som har ett giltigt
 * värde visas. Ikonerna väljs i appen.
 */
data class SourceLink(
    val kind: Kind,
    /** "Webbplats", "018-727 94 00" eller "kundservice@uppsalavatten.se". */
    val title: String,
    val url: String,
) {
    enum class Kind {
        /** Källans webbplats, i appens webbvy. */
        Website,

        /** Adressens sida hos kommunen eller bolaget (`links.web`), i appens webbvy. */
        KommunInfo,

        /** Ett tryck ringer. */
        Phone,

        /** Ett tryck öppnar ett nytt mejl. */
        Email,

        /** Källans kontaktsida, i appens webbvy. */
        ContactPage,

        /** Adressens schema i Google Kalender, som prenumeration på `webcal://`-adressen. */
        Calendar,
    }

    val id: Kind get() = kind

    /**
     * Länkar som öppnas i appens webbvy. Telefon och e-post öppnas av systemet. Telefonnumret står i accentfärg,
     * eftersom det oftast är det man vill använda. Övriga länkar står i vanlig textfärg.
     */
    val isPrimaryAction: Boolean get() = kind == Kind.Phone

    /** Sidor som öppnas i appens webbvy får en pil. Telefon och e-post öppnas av systemet. */
    val showsChevron: Boolean get() = webLink != null

    val webLink: WebLink?
        get() = when (kind) {
            Kind.Website, Kind.KommunInfo, Kind.ContactPage -> WebLink(url)
            Kind.Phone, Kind.Email, Kind.Calendar -> null
        }

    /** Det TalkBack läser: vad som händer, och numret eller adressen. */
    val accessibilityLabel: String
        get() = when (kind) {
            Kind.Phone -> "Ring $title"
            Kind.Email -> "Mejla $title"
            Kind.Website, Kind.KommunInfo, Kind.ContactPage, Kind.Calendar -> title
        }

    companion object {
        /** Raden i adressvyns eget kort Kalender, med länken från [CalendarLink]. */
        fun calendar(url: String) = SourceLink(Kind.Calendar, CalendarLink.TITLE, url)

        /** Webbplats, kommunens information och kontakten, i den ordningen. [kommunInfo] saknas på Datakällor. */
        fun links(source: Source?, kommunInfo: String?): List<SourceLink> {
            val links = mutableListOf<SourceLink>()
            source?.url?.let { if (WebLink(it) != null) links += SourceLink(Kind.Website, "Webbplats", it) }
            kommunInfo?.let { if (WebLink(it) != null) links += SourceLink(Kind.KommunInfo, "Kommunens information", it) }
            val contact = source?.contact
            contact?.phone?.let(::phoneLink)?.let(links::add)
            contact?.email?.let(::emailLink)?.let(links::add)
            contact?.page?.let { if (WebLink(it) != null) links += SourceLink(Kind.ContactPage, "Kontaktsida", it) }
            return links
        }

        /** `tel:` med numret, bara plus och siffror. Utan nummer går det inte att ringa, och raden visas inte. */
        private fun phoneLink(phone: SourceContact.Phone): SourceLink? {
            val number = phone.number.orEmpty().filter { it in '0'..'9' || it == '+' }
            if (number.none { it in '0'..'9' }) return null
            val shown = phone.display?.trim(Char::isWhitespace).orEmpty()
            return SourceLink(Kind.Phone, title = shown.ifEmpty { number }, url = "tel:$number")
        }

        private fun emailLink(email: String): SourceLink? {
            val address = email.trim(Char::isWhitespace)
            val parts = address.split("@")
            if (parts.size != 2 || parts[0].isEmpty() || !parts[1].contains(".") || address.any(Char::isWhitespace)) return null
            val url = "mailto:$address"
            if (!ApiDecoding.isValidUrl(url)) return null
            return SourceLink(Kind.Email, title = address, url = url)
        }
    }
}
