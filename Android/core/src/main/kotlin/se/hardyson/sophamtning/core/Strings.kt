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
