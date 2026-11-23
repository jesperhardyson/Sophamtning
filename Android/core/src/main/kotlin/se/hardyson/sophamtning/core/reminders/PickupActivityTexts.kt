package se.hardyson.sophamtning.core.reminders

import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.lowercasedFirst

// Live Updatens texter, som PickupActivityTexts.swift. De använder datum, aldrig "i morgon", eftersom innehållet inte
// uppdateras under natten.

/** Rubriken: vad som ska göras, eller att det är gjort. */
val PickupActivityContent.title: String
    get() = if (placedOut) PickupActivityContent.PLACED_OUT_TITLE else PickupActivityContent.ALERT_TITLE

/** Raden under rubriken: vem och när när kärlen är utställda och det är känt, annars adressen och datumet. */
val PickupActivityContent.detailLine: String get() = placedOutDetail ?: subtitle

/** "måndag 9 november", eller "ca måndag 9 november". */
private val PickupActivityContent.lowercasedDate: String
    get() = SwedishFormat.estimated(dateText.lowercasedFirst(), estimated)

/** "Hemma: Restavfall och Matavfall töms måndag 9 november." Med "ca" när datumet är beräknat och varningen sist. */
val PickupActivityContent.alertBody: String
    get() {
        var text = "$fractionsLine töms $lowercasedDate."
        warning?.let { text += " $it" }
        return text
    }

/** "Hemma · måndag 9 november". */
val PickupActivityContent.subtitle: String get() = "$addressName · $lowercasedDate"

/** "Mån 9 nov", eller "ca mån 9 nov". */
val PickupActivityContent.shortDate: String
    get() = if (estimated) "ca " + shortDateText.lowercase() else shortDateText

/** "Mån", eller "ca mån". Veckodagen räcker där platsen är liten, eftersom Live Updaten bara lever kvällen före eller samma dag. */
val PickupActivityContent.compactDate: String
    get() {
        val weekday = shortDateText.split(" ").firstOrNull { it.isNotEmpty() } ?: shortDateText
        return if (estimated) "ca " + weekday.lowercase() else weekday
    }

/** "Restavfall, Matavfall och Glas". */
val PickupActivityContent.fractionNames: String
    get() {
        val names = fractions.map { it.name }
        if (names.size < 2) return names.firstOrNull() ?: ""
        return "${names.dropLast(1).joinToString(", ")} och ${names.last()}"
    }

/** "Hemma: Restavfall och Matavfall". */
val PickupActivityContent.fractionsLine: String get() = "$addressName: $fractionNames"

/** Fraktionerna som små chips på högst två rader. Alla får plats, och ingen döljs. Upp till tre ryms på en rad. */
val PickupActivityContent.fractionRows: List<List<ActivityFraction>>
    get() {
        if (fractions.size <= 3) return if (fractions.isEmpty()) emptyList() else listOf(fractions)
        val first = (fractions.size + 1) / 2
        return listOf(fractions.take(first), fractions.drop(first))
    }

/** Fraktionerna går före varningen. Tar de två rader får varningen en, och kapas hellre än att något annat försvinner. */
val PickupActivityContent.warningLineLimit: Int get() = if (fractionRows.size > 1) 1 else 2
