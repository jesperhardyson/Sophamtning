package se.hardyson.sophamtning.core

import java.text.BreakIterator

// Som StringNilIfEmpty.swift på iOS.

/** `null` när texten är tom. */
internal fun String.nilIfEmpty(): String? = ifEmpty { null }

/** Texten utan blanktecken och radbrytningar runt omkring, eller `null` när inget återstår. Källans texter visas så. */
internal fun String.trimmedNonEmpty(): String? = trim(Char::isWhitespace).nilIfEmpty()

/** Antalet tecken som en människa ser dem (grafemkluster), som `String.count` i Swift. */
internal fun String.graphemeCount(): Int {
    if (isEmpty()) return 0
    val iterator = BreakIterator.getCharacterInstance()
    iterator.setText(this)
    var count = 0
    while (iterator.next() != BreakIterator.DONE) count++
    return count
}

/** De första [count] tecknen som en människa ser dem (grafemkluster), som `String.prefix(_:)` i Swift. */
internal fun String.graphemePrefix(count: Int): String {
    if (count <= 0) return ""
    val iterator = BreakIterator.getCharacterInstance()
    iterator.setText(this)
    var end = 0
    repeat(count) {
        val next = iterator.next()
        if (next == BreakIterator.DONE) return this
        end = next
    }
    return substring(0, end)
}

/** Första tecknet med versal, som `prefix(1).uppercased() + dropFirst()` i Swift. */
internal fun String.capitalizedFirst(): String = if (isEmpty()) this else substring(0, 1).uppercase() + substring(1)

/** Första tecknet med gemen, som `prefix(1).lowercased() + dropFirst()` i Swift. */
internal fun String.lowercasedFirst(): String = if (isEmpty()) this else substring(0, 1).lowercase() + substring(1)
