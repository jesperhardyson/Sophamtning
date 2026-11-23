package se.hardyson.sophamtning.core.search

import se.hardyson.sophamtning.core.api.AreaSource
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.trimmedNonEmpty

/**
 * Det som en rad i områdesvalet visar, som på webbens områdessida: namnet, etiketten, dagen, platserna och platser med
 * andra dagar. Saknar träffen detaljer visas dagens rad med `detail`, och inget tyder på att området saknas.
 */
data class AreaRowContent(
    /** Områdets namn, "Askön, Nyhyttan m.fl.". */
    val title: String,
    /** Den lilla etiketten, "Område 1", eller `null`. */
    val label: String?,
    /** "Måndag, udda vecka". Utan detaljer är det API:ts `detail`, "Måndag, udda vecka · Område 1". */
    val day: String?,
    /** Platserna på en kort rad, "Askön, Nyhyttan, Klintbo, Snickarbo m.fl.", eller `null`. */
    val places: String?,
    /** Alla platser, "Askön, Nyhyttan, … och Rutbo", för TalkBack och bekräftelsen. `null` utan platser. */
    val allPlaces: String?,
    /** Platser i området med en annan dag, som källan skrev dem. */
    val otherDays: List<String>,
    /** Hur många platser området har. */
    val placeCount: Int = 0,
    /** Sant när raden kommer från områdets detaljer. Annars är det dagens rad, med `detail` i dess stil. */
    val detailed: Boolean = false,
) {
    /** Sant när den korta raden inte visar alla platser. Då går listan att fälla ut. */
    val hidesPlaces: Boolean get() = placeCount > shortPlaceCount + 1

    /** "Visa alla 18 platser". */
    val showAllPlacesText: String get() = "Visa alla $placeCount platser"

    /** Knappen i bekräftelsen: "Visa alla 18 platser", och "Visa färre platser" när listan är utfälld. */
    fun placesToggleText(expanded: Boolean): String = if (expanded) "Visa färre platser" else showAllPlacesText

    /**
     * Hela raden som en text för TalkBack, med alla platser: "Askön, Nyhyttan m.fl., Område 1, Måndag, udda vecka.
     * Platser: Askön, Nyhyttan och Klintbo."
     */
    val accessibilityLabel: String
        get() {
            val head = listOfNotNull(title, label, day).joinToString(", ")
            val others = if (otherDays.isEmpty()) emptyList() else listOf(otherDaysHeading) + otherDays
            val tail = listOfNotNull(allPlaces?.let { "Platser: $it" }) + others
            return (listOf(head) + tail).joinToString(" ") { if (it.endsWith(".")) it else "$it." }
        }

    companion object {
        /** Så många platser står på den korta raden innan "m.fl.". */
        const val shortPlaceCount = 4

        /** Rubriken över raderna med andra dagar, som på webben. */
        const val otherDaysHeading = "Vissa gator har en annan hämtdag"

        fun make(hit: SearchHit): AreaRowContent {
            val detail = hit.detail?.trimmedNonEmpty()
            val area = hit.area
            val day = area?.day?.trimmedNonEmpty()
            if (area == null || day == null) {
                // Inga detaljer: dagens visning, med namnet och `detail`.
                return AreaRowContent(title = hit.street, label = null, day = detail, places = null, allPlaces = null, otherDays = emptyList())
            }
            val places = area.places.mapNotNull { it.trimmedNonEmpty() }
            return AreaRowContent(
                title = hit.street,
                label = area.label?.trimmedNonEmpty(),
                day = day,
                places = shortPlaces(places),
                allPlaces = if (places.isEmpty()) null else listText(places),
                otherDays = area.otherDays.mapNotNull { it.trimmedNonEmpty() },
                placeCount = places.size,
                detailed = true,
            )
        }

        /** Den korta raden. Fler än en plats till än vad som får plats ger "m.fl.", så att "m.fl." aldrig står för en enda. */
        internal fun shortPlaces(places: List<String>): String? {
            if (places.isEmpty()) return null
            if (places.size <= shortPlaceCount + 1) return places.joinToString(", ")
            return places.take(shortPlaceCount).joinToString(", ") + " m.fl."
        }

        /** "Askön, Nyhyttan och Klintbo". */
        internal fun listText(items: List<String>): String {
            if (items.size <= 1) return items.firstOrNull() ?: ""
            return items.dropLast(1).joinToString(", ") + " och " + items.last()
        }
    }
}

/**
 * En text med länkar på delar av den, i stället för `AttributedString` på iOS. [Link.range] är teckenpositioner i
 * [text], som `String.substring(range)` tar.
 */
data class LinkedText(val text: String, val links: List<Link> = emptyList()) {
    data class Link(val range: IntRange, val url: String)
}

/** Källans förklaring överst i områdesvalet. Texterna visas som källan skrev dem. */
data class AreaSourceNote(
    val id: String,
    /** Källans namn, som bara behövs när flera källor svarade. */
    val name: String,
    val explanation: String?,
    /** Hjälpraden, där ett telefonnummer går att trycka på. */
    val help: LinkedText?,
) {
    companion object {
        /**
         * Ett telefonnummer i löptext: siffror med mellanslag, bindestreck och parenteser emellan, och ett plustecken
         * först. På iOS hittas numren med `NSDataDetector`, som inte finns här.
         */
        private val phonePattern = Regex("""\+?\(?\d[\d  ()-]*\d""")

        /**
         * Ett svenskt telefonnummer börjar med 0 eller +, och har minst sju siffror. Så blir postnummer ("791 83"), datum
         * ("2026-11-23") och öppettider ("08-16") inte länkar, som de inte heller blir på iOS.
         */
        private fun isPhoneNumber(value: String): Boolean {
            val start = value.trimStart('(')
            return (start.startsWith("0") || start.startsWith("+")) && value.count(Char::isDigit) >= 7
        }

        /** En förklaring per källa som har något att säga. Utan källor blir listan tom, och då visas dagens meddelande. */
        fun notes(sources: List<AreaSource>): List<AreaSourceNote> {
            val seen = mutableSetOf<String>()
            return sources.mapNotNull { source ->
                if (!seen.add(source.id)) return@mapNotNull null
                val explanation = source.explanation?.trimmedNonEmpty()
                val help = source.help?.trimmedNonEmpty()
                if (explanation == null && help == null) return@mapNotNull null
                AreaSourceNote(id = source.id, name = source.name, explanation = explanation, help = help?.let(::linkingPhoneNumbers))
            }
        }

        /** Texten med varje telefonnummer som en `tel:`-länk. Hittas inget nummer är texten oförändrad. */
        fun linkingPhoneNumbers(text: String): LinkedText {
            val links = phonePattern.findAll(text).filter { isPhoneNumber(it.value) }.mapNotNull { match ->
                telURL(match.value)?.let { url -> LinkedText.Link(match.range, url) }
            }.toList()
            return LinkedText(text, links)
        }

        /** "0226-64 55 00" blir `tel:0226645500`. Ett plustecken först behålls. */
        internal fun telURL(number: String): String? {
            val digits = number.filter { it in '0'..'9' }
            if (digits.length < 5) return null
            val plus = if (number.trim().startsWith("+")) "+" else ""
            return "tel:$plus$digits"
        }
    }
}

/**
 * Det som varningskortet överst i områdesvalet visar. Källans `explanation` står ordagrant, sedan en mening om att fel
 * område kan göra att man missar tömningen, och sist källans hjälprad. Saknas `explanation` visas `notice` i dess ställe,
 * så att varningen aldrig försvinner, och finns ingen text alls står ändå rubriken och konsekvensen. När `explanation`
 * finns visas inte `notice` här, utan i bekräftelsearket.
 */
data class AreaWarning(
    /** Källans förklaring, eller `notice` när ingen källa har någon förklaring. */
    val explanations: List<Entry>,
    val helps: List<Help>,
) {
    /** En text i kortet. Källans namn behövs bara när flera källor svarade. */
    data class Entry(val id: String, val name: String?, val text: String)

    /** Hjälpraden, där telefonnumret går att trycka på. */
    data class Help(val id: String, val name: String?, val text: LinkedText)

    /**
     * Om meningen om missad tömning ska stå för sig. Den utelämnas när en förklaring (till exempel `notice` som
     * reservtext) redan innehåller den, så att den inte står två gånger.
     */
    val showsConsequence: Boolean get() = explanations.none { it.text.contains(consequence) }

    companion object {
        const val title = "Du väljer området själv"
        const val consequence = "Väljer du fel område kan du missa din tömning."

        /** Kortet finns alltid: saknas förklaring, `notice` och hjälprad står bara rubriken och meningen om missad tömning. */
        fun make(notice: String?, notes: List<AreaSourceNote>): AreaWarning {
            val named = notes.size > 1
            var explanations = notes.mapNotNull { note ->
                note.explanation?.let { Entry(id = note.id, name = if (named) note.name else null, text = it) }
            }
            val trimmedNotice = notice?.trimmedNonEmpty()
            if (explanations.isEmpty() && trimmedNotice != null) {
                explanations = listOf(Entry(id = "notice", name = null, text = trimmedNotice))
            }
            val helps = notes.mapNotNull { note ->
                note.help?.let { Help(id = note.id, name = if (named) note.name else null, text = it) }
            }
            return AreaWarning(explanations, helps)
        }
    }
}
