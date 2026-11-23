package se.hardyson.sophamtning.ui.search

import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.storage.AddressKey

// Delar som kommunfrågan, adressökningen och områdesvalet delar, som FlowComponents.swift på iOS.

/**
 * Sparar adressen och svarar med dess nyckel om det gick. Går det inte visar skärmen sitt eget fel, så modellens
 * lagringsfel rensas för att inte dyka upp en gång till på hemskärmen.
 */
fun AppModel.save(hit: SearchHit): AddressKey? {
    clearStorageError()
    if (!add(hit)) {
        clearStorageError()
        return null
    }
    return AddressKey(hit.source, hit.id)
}

const val SAVE_FAILED_MESSAGE = "Adressen kunde inte sparas. Försök igen."

/** Sidan där man tipsar om sin kommun. */
const val TIP_LINK = "https://sopor.hardyson.se/bidra"

/** Källans namn för ett id, annars id:t med stor bokstav. */
fun sourceName(id: String, sources: List<Source>?): String =
    sources?.firstOrNull { it.id == id }?.name ?: id.replaceFirstChar { it.uppercaseChar() }

fun capitalizedFirst(text: String): String = text.replaceFirstChar { it.uppercaseChar() }
