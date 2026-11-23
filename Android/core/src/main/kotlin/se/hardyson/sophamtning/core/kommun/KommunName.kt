package se.hardyson.sophamtning.core.kommun

import java.text.Normalizer
import java.util.Locale

private val swedish = Locale.forLanguageTag("sv-SE")

/**
 * "Avesta kommun" blir "Avesta". Namn utan ordet "kommun" lämnas som de är.
 * Bara för det som skickas till API:t, till exempel `/omraden?plats=`. Det som visas använder [kommunDisplayName].
 */
fun shortKommunName(name: String): String = if (name.endsWith(" kommun")) name.dropLast(" kommun".length) else name

/** Kommunen som den visas: hela namnet från API:t, "Säters kommun". Samma överallt där kommunen står i appen. */
fun kommunDisplayName(name: String): String = name.trim(Char::isWhitespace)

/** Jämför utan hänsyn till skiftläge, med svenska regler, som `compare(_:options: .caseInsensitive, locale:)` på iOS. */
private fun sameIgnoringCase(a: String, b: String): Boolean {
    fun fold(text: String) = Normalizer.normalize(text, Normalizer.Form.NFC).lowercase(swedish)
    return fold(a) == fold(b)
}

/**
 * Sant när kommunens namn bara upprepar orten: "Uppsala kommun" och "Uppsala", "Säters kommun" och "Säter",
 * "Stockholms kommun" och "Stockholm", "Falu kommun" och "Falun". Utan hänsyn till skiftläge.
 */
fun kommunRepeatsLocality(kommun: String, locality: String): Boolean {
    val short = shortKommunName(kommunDisplayName(kommun))
    val place = locality.trim(Char::isWhitespace)
    if (short.isEmpty() || place.isEmpty()) return false
    // Orten, orten i genitiv och Falun, vars kommun heter Falu.
    if (sameIgnoringCase(short, place) || sameIgnoringCase(short, place + "s")) return true
    return sameIgnoringCase(short, "Falu") && sameIgnoringCase(place, "Falun")
}

/**
 * Orten och kommunen på en rad, med samma regel som kortens rad för platsen: "Uppsala", "Krylbo · Avesta kommun".
 * Kommunen döljs när den bara upprepar orten. Utan ort står bara kommunen. Hårt mellanslag före mittpunkten.
 */
fun localityAndKommun(locality: String, kommun: String): String {
    val place = locality.trim(Char::isWhitespace)
    val name = kommunDisplayName(kommun)
    if (place.isEmpty()) return name
    if (name.isEmpty() || kommunRepeatsLocality(name, place)) return place
    return "$place · $name"
}
