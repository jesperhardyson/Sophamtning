package se.hardyson.sophamtning.core.api

import kotlinx.serialization.Serializable
import se.hardyson.sophamtning.core.dates.DayDate

// Samma typer och fält som APIModels.swift på iOS. Webbadresser är text, och reglerna för ogiltiga adresser och trasiga
// fält står i ApiDecoding. Serialiserarna används bara för att koda, till exempel när ett svar sparas.

/** En träff i sökresultatet: en adress eller ett område. */
@Serializable
data class SearchHit(
    val id: String,
    val street: String,
    val locality: String,
    val kommun: String,
    val source: String,
    val detail: String?,
    /** "address" eller "area". Äldre svar saknar fältet, och då är det en adress. */
    val selection: String,
    val notice: String?,
    val areasUrl: String?,
    /** Adressens schema i API:t. Procentkodad och får inte kodas om. */
    val url: String,
    /** Områdets tömningar kring datumet i `/omraden?tomning=`. `null` när anropet saknar datum. */
    val pickups: Pickups? = null,
    /** Områdets detaljer från `/omraden`. `null` för adresser, i äldre svar och när fältet är trasigt. */
    val area: AreaDetails? = null,
) {
    val isArea: Boolean get() = selection == "area"
}

/** Det som webbens områdessida visar för ett område. Varje del kan saknas eller vara trasig, och då är den tom. */
@Serializable
data class AreaDetails(
    val day: String,
    val label: String?,
    val places: List<String>,
    val otherDays: List<String> = emptyList(),
    val searchTerms: List<String> = emptyList(),
)

/** En källa som svarade i `/omraden`, med varför man väljer område och vart man vänder sig. */
@Serializable
data class AreaSource(val id: String, val name: String, val explanation: String?, val help: String?)

/** Hur långt källans schema gäller. Live-källor har inget sådant. */
@Serializable
data class SchedulePeriod(val until: DayDate, val reason: String?)

/** Tömningarna för ett område kring ett angivet datum. */
@Serializable
data class Pickups(val previous: List<DayDate>, val next: DayDate?)

@Serializable
data class SearchResponse(
    val addresses: List<SearchHit>,
    /** Källor som inte svarade. En delvis sökning behåller ändå träffarna. */
    val failed: List<String>,
    val dateCovered: Boolean? = null,
    val sources: List<AreaSource> = emptyList(),
)

/** Adressen i ett schemasvar. */
@Serializable
data class Address(
    val id: String,
    val street: String,
    val locality: String,
    val kommun: String,
    val source: String,
    val detail: String?,
    val selection: String,
    val notice: String?,
    val area: AreaDetails? = null,
)

/** Nästa hämtning för en fraktion. API:ts `daysUntil`, `isToday`, `isTomorrow` och `text` avkodas inte. */
@Serializable
data class NextPickup(
    val fraction: String,
    val name: String,
    val color: String,
    val date: DayDate,
    val estimated: Boolean,
    val warning: String?,
)

@Serializable
data class Deviation(val originalDate: DayDate?, val reason: String)

@Serializable
data class PickupEvent(
    val date: DayDate,
    /** Fraktions-id. Mängden är öppen, så ett id kan saknas i `fractions`. */
    val fractions: List<String>,
    val estimated: Boolean,
    val deviation: Deviation?,
    val warning: String?,
    val labels: Map<String, String>,
)

@Serializable
data class Bin(val fraction: String, val sizeLiters: Int?, val pickupsPerYear: Int?, val frequencyText: String?)

@Serializable
data class FractionInfo(val name: String, val short: String, val color: String, val icon: String)

@Serializable
data class Links(val ics: String, val web: String)

@Serializable
data class AddressResponse(
    val today: DayDate,
    val address: Address,
    val next: List<NextPickup>,
    val summary: String,
    val events: List<PickupEvent>,
    val bins: List<Bin>,
    val fractions: Map<String, FractionInfo>,
    val links: Links,
    val updatedAt: DayDate,
    val schedule: SchedulePeriod? = null,
    val messages: List<SourceMessage> = emptyList(),
)

/** Ett tillfälligt besked från källan. `id` är unikt inom källan och återanvänds aldrig. */
@Serializable
data class SourceMessage(
    val id: String,
    val title: String,
    val text: String,
    /** Källans egen sida om saken, eller `null`. */
    val url: String?,
    /** Första och sista dagen meddelandet gäller, båda inklusive. */
    val validFrom: DayDate,
    val validTo: DayDate,
)

@Serializable
data class Kommun(val code: String, val name: String)

@Serializable
data class Source(
    val id: String,
    val name: String,
    val url: String,
    val kommuner: List<Kommun>,
    val testData: Boolean,
    val contact: SourceContact? = null,
)

/** Källans kontaktuppgifter från `/kallor`. Varje del kan saknas. `checkedAt` och `checkedUrl` visas inte. */
@Serializable
data class SourceContact(
    val phone: Phone? = null,
    val email: String? = null,
    val page: String? = null,
    val checkedAt: DayDate? = null,
    val checkedUrl: String? = null,
) {
    @Serializable
    data class Phone(val number: String?, val display: String?)
}

@Serializable
data class SourcesResponse(val sources: List<Source>, val fractions: Map<String, FractionInfo>)
