package se.hardyson.sophamtning.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable
import se.hardyson.sophamtning.core.api.AreaSource
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.storage.AddressKey

// Skärmarna i backstacken. Nycklarna sparas när appen dödas, så att backstacken finns kvar när den startas om.

@Serializable
data object Home : NavKey

/**
 * Lägg till adress. [source] begränsar sökningen till en källa, efter kommunfrågan. [replacing] är adressen som källan inte
 * längre känner igen ("Sök igen"), och den ersätts först när den nya är sparad.
 */
@Serializable
data class AddAddress(val source: String? = null, val replacing: AddressKey? = null) : NavKey

/** Finns min kommuns hämtningsschema? */
@Serializable
data object KommunCheck : NavKey

/**
 * Välj område. [place] är platsen som områdena hämtades för. Utan plats finns inte "Vet du inte vilket område?".
 * [sources] är källorna som svarade, med förklaringen överst.
 */
@Serializable
data class AreaPicker(val title: String, val place: String?, val hits: List<SearchHit>, val sources: List<AreaSource>) : NavKey

/** När tömdes ditt kärl senast? */
@Serializable
data class AreaFinder(val place: String) : NavKey

/** Stämmer området? Området sparas först när användaren trycker Spara området. */
@Serializable
data class AreaConfirm(val hit: SearchHit) : NavKey

@Serializable
data class Address(val key: AddressKey) : NavKey

@Serializable
data class FullSchedule(val key: AddressKey) : NavKey

/** Skärmarna i flödet Lägg till adress, som tas bort från backstacken när en adress har sparats. */
val NavKey.isAddFlow: Boolean
    get() = this is AddAddress || this is KommunCheck || this is AreaPicker || this is AreaFinder || this is AreaConfirm

/** Byt namn på adressen, som en helskärmsdialog med fältet och Spara i appfältet. */
@Serializable
data class Rename(val key: AddressKey) : NavKey
