package se.hardyson.sophamtning.core.api

import java.net.URI
import java.net.URISyntaxException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import se.hardyson.sophamtning.core.dates.DayDate

/** Ett svar eller fält som inte går att tolka. */
class DecodeException(message: String) : Exception(message)

/**
 * Avkodning av API:ts svar med samma regler som `init(from:)` i APIModels.swift. Ett obligatoriskt fält som saknas eller
 * är fel fäller sitt objekt. Där iOS använder `try?` eller `Lenient` blir ett trasigt fält sitt standardvärde, och ett
 * trasigt element i en lista tas bort. Okända fält ignoreras.
 */
object ApiDecoding {
    val json = Json { ignoreUnknownKeys = true }

    fun addressResponse(text: String): AddressResponse = addressResponse(parse(text))
    fun searchResponse(text: String): SearchResponse = searchResponse(parse(text))
    fun sourcesResponse(text: String): SourcesResponse = sourcesResponse(parse(text))

    private fun parse(text: String): JsonObject =
        runCatching { json.parseToJsonElement(text) }.getOrNull() as? JsonObject ?: throw DecodeException("Inte ett JSON-objekt")

    // MARK: Svaren

    fun addressResponse(e: JsonElement): AddressResponse = with(obj(e)) {
        AddressResponse(
            today = day("today"),
            address = address(req("address")),
            next = list("next", ::nextPickup),
            summary = string("summary"),
            events = list("events", ::pickupEvent),
            bins = list("bins", ::bin),
            fractions = map("fractions", ::fractionInfo),
            links = links(req("links")),
            updatedAt = day("updatedAt"),
            // Saknas, `null` eller trasigt: ingen rad om hur långt schemat gäller. Schemat visas ändå.
            schedule = lenient { optional("schedule")?.let(::schedulePeriod) },
            // Saknas, `null` eller trasigt: inga meddelanden. Ett trasigt meddelande fäller inte de andra.
            messages = lenientList("messages", ::sourceMessage),
        )
    }

    fun searchResponse(e: JsonElement): SearchResponse = with(obj(e)) {
        SearchResponse(
            addresses = list("addresses", ::searchHit),
            failed = list("failed", ::string),
            dateCovered = optional("dateCovered")?.let(::bool),
            // En trasig källa tas bort, och ett trasigt fält ger inga källor.
            sources = lenientList("sources", ::areaSource),
        )
    }

    fun sourcesResponse(e: JsonElement): SourcesResponse = with(obj(e)) {
        SourcesResponse(sources = list("sources", ::source), fractions = map("fractions", ::fractionInfo))
    }

    // MARK: Delarna

    private fun searchHit(e: JsonElement) = with(obj(e)) {
        SearchHit(
            id = string("id"), street = string("street"), locality = string("locality"), kommun = string("kommun"),
            source = string("source"), detail = optString("detail"),
            selection = optString("selection") ?: "address",
            notice = optString("notice"),
            // Ett trasigt värde (tom sträng, fel typ) ger ingen länk. Det får inte fälla hela sökresultatet.
            areasUrl = lenient { optString("areasUrl") }?.trim()?.takeIf { it.isNotEmpty() && isValidUrl(it) },
            url = url("url"),
            // Trasiga tömningsdatum ger en träff utan datum.
            pickups = lenient { optional("pickups")?.let(::pickups) },
            // Trasiga detaljer ger dagens visning med `detail`.
            area = lenient { optional("area")?.let(::areaDetails) },
        )
    }

    private fun areaDetails(e: JsonElement) = with(obj(e)) {
        AreaDetails(
            day = lenient { optString("day") } ?: "",
            label = lenient { optString("label") },
            places = lenient { optional("places")?.let { list(it, ::string) } } ?: emptyList(),
            otherDays = lenient { optional("otherDays")?.let { list(it, ::string) } } ?: emptyList(),
            searchTerms = lenient { optional("searchTerms")?.let { list(it, ::string) } } ?: emptyList(),
        )
    }

    private fun areaSource(e: JsonElement) = with(obj(e)) {
        AreaSource(
            id = string("id"),
            name = lenient { optString("name") } ?: "",
            explanation = lenient { optString("explanation") },
            help = lenient { optString("help") },
        )
    }

    private fun schedulePeriod(e: JsonElement) = with(obj(e)) {
        SchedulePeriod(until = day("until"), reason = lenient { optString("reason") })
    }

    private fun pickups(e: JsonElement) = with(obj(e)) {
        Pickups(previous = list("previous", ::day), next = optional("next")?.let(::day))
    }

    private fun address(e: JsonElement) = with(obj(e)) {
        Address(
            id = string("id"), street = string("street"), locality = string("locality"), kommun = string("kommun"),
            source = string("source"), detail = optString("detail"),
            selection = optString("selection") ?: "address",
            notice = optString("notice"),
            // Trasiga detaljer ger ingen ruta. De får inte fälla hela adressvaret.
            area = lenient { optional("area")?.let(::areaDetails) },
        )
    }

    private fun nextPickup(e: JsonElement) = with(obj(e)) {
        NextPickup(
            fraction = string("fraction"), name = string("name"), color = string("color"), date = day("date"),
            estimated = bool(req("estimated")), warning = optString("warning"),
        )
    }

    private fun deviation(e: JsonElement) = with(obj(e)) {
        Deviation(originalDate = optional("originalDate")?.let(::day), reason = string("reason"))
    }

    private fun pickupEvent(e: JsonElement) = with(obj(e)) {
        PickupEvent(
            date = day("date"),
            fractions = list("fractions", ::string),
            estimated = bool(req("estimated")),
            deviation = optional("deviation")?.let(::deviation),
            warning = optString("warning"),
            labels = optional("labels")?.let { map(it, ::string) } ?: emptyMap(),
        )
    }

    private fun bin(e: JsonElement) = with(obj(e)) {
        Bin(
            fraction = string("fraction"),
            sizeLiters = optional("sizeLiters")?.let(::int),
            pickupsPerYear = optional("pickupsPerYear")?.let(::int),
            frequencyText = optString("frequencyText"),
        )
    }

    private fun fractionInfo(e: JsonElement) = with(obj(e)) {
        FractionInfo(name = string("name"), short = string("short"), color = string("color"), icon = string("icon"))
    }

    private fun links(e: JsonElement) = with(obj(e)) { Links(ics = url("ics"), web = url("web")) }

    private fun sourceMessage(e: JsonElement) = with(obj(e)) {
        SourceMessage(
            id = string("id"), title = string("title"), text = string("text"),
            // En länk som inte går att tolka tas bort, men meddelandet visas ändå.
            url = lenient { optString("url") }?.takeIf(::isValidUrl),
            validFrom = day("validFrom"), validTo = day("validTo"),
        )
    }

    private fun kommun(e: JsonElement) = with(obj(e)) { Kommun(code = string("code"), name = string("name")) }

    private fun source(e: JsonElement) = with(obj(e)) {
        Source(
            id = string("id"), name = string("name"), url = url("url"),
            kommuner = list("kommuner", ::kommun),
            testData = bool(req("testData")),
            // Saknas, `null` eller trasig: ingen kontakt. Källan visas ändå.
            contact = lenient { optional("contact")?.let(::sourceContact) },
        )
    }

    /** En trasig del ger bara att den delen saknas. Den får aldrig fälla källan eller listan. */
    private fun sourceContact(e: JsonElement) = with(obj(e)) {
        SourceContact(
            phone = lenient { optional("phone")?.let(::phone) },
            email = lenient { optString("email") },
            page = lenient { optString("page") }?.takeIf(::isValidUrl),
            checkedAt = lenient { optional("checkedAt")?.let(::day) },
            checkedUrl = lenient { optString("checkedUrl") }?.takeIf(::isValidUrl),
        )
    }

    private fun phone(e: JsonElement) = with(obj(e)) {
        SourceContact.Phone(number = lenient { optString("number") }, display = lenient { optString("display") })
    }

    // MARK: Byggstenar

    private fun fail(what: String): Nothing = throw DecodeException(what)

    private fun obj(e: JsonElement) = e as? JsonObject ?: fail("Väntade ett objekt")

    private fun JsonObject.req(key: String): JsonElement = this[key]?.takeIf { it !is JsonNull } ?: fail("$key saknas")

    /** Som `decodeIfPresent`: saknas eller `null` ger `null`, men ett värde av fel typ fäller. */
    private fun JsonObject.optional(key: String): JsonElement? = this[key]?.takeIf { it !is JsonNull }

    private fun string(e: JsonElement) = (e as? JsonPrimitive)?.takeIf { it.isString }?.content ?: fail("Väntade text")
    private fun bool(e: JsonElement) = (e as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: fail("Väntade sant eller falskt")
    /** Som `Int` i JSONDecoder: ett decimaltal utan decimaler (140.0) godtas, men inte 140.5. */
    private fun int(e: JsonElement): Int {
        val number = (e as? JsonPrimitive)?.takeIf { !it.isString } ?: fail("Väntade ett heltal")
        number.intOrNull?.let { return it }
        val value = number.doubleOrNull ?: fail("Väntade ett heltal")
        return value.toInt().takeIf { it.toDouble() == value } ?: fail("Väntade ett heltal")
    }
    private fun day(e: JsonElement) = DayDate.parse(string(e)) ?: fail("Ogiltigt datum")

    private fun JsonObject.string(key: String) = string(req(key))
    private fun JsonObject.optString(key: String) = optional(key)?.let(::string)
    private fun JsonObject.day(key: String) = day(req(key))
    private fun JsonObject.url(key: String) = string(key).takeIf(::isValidUrl) ?: fail("Ogiltig adress i $key")

    private fun <T> list(e: JsonElement, item: (JsonElement) -> T) = (e as? JsonArray ?: fail("Väntade en lista")).map(item)
    private fun <T> JsonObject.list(key: String, item: (JsonElement) -> T) = list(req(key), item)
    private fun <T> map(e: JsonElement, value: (JsonElement) -> T) = obj(e).mapValues { value(it.value) }
    private fun <T> JsonObject.map(key: String, value: (JsonElement) -> T) = map(req(key), value)

    /** Som `try?` på iOS: ett fel blir `null`. */
    private inline fun <T> lenient(block: () -> T?): T? = try { block() } catch (_: DecodeException) { null }

    /** Som `[Lenient<T>]` på iOS: ett trasigt fält ger en tom lista, och trasiga element tas bort. */
    private fun <T : Any> JsonObject.lenientList(key: String, item: (JsonElement) -> T): List<T> =
        (optional(key) as? JsonArray)?.mapNotNull { lenient { item(it) } } ?: emptyList()

    /** En absolut adress med schema, som `URL(string:)` godtar. Mellanslag och andra otillåtna tecken ger `false`. */
    internal fun isValidUrl(text: String): Boolean =
        try { URI(text).let { it.isAbsolute && !it.scheme.isNullOrEmpty() } } catch (_: URISyntaxException) { false }
}
