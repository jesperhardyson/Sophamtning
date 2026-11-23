package se.hardyson.sophamtning.core.reminders

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import kotlinx.serialization.builtins.ListSerializer
import se.hardyson.sophamtning.core.graphemeCount
import se.hardyson.sophamtning.core.graphemePrefix
import se.hardyson.sophamtning.core.storage.JsonTreeSerializer
import se.hardyson.sophamtning.core.storage.storeJson

// Delarna av PickupActivityAttributes.swift som planeraren använder, utan ActivityKit.

@Serializable
data class ActivityFraction(val id: String, val name: String, val short: String, val color: String, val icon: String)

/**
 * Innehållet i Live Updaten. Texterna får inte säga "i morgon", eftersom innehållet inte uppdateras under natten.
 *
 * En vanlig klass i stället för `data class`, eftersom varningen kortas och raden om vem bara finns när kärlen är utställda,
 * som i `init` på iOS. Likhet gäller de färdiga värdena.
 */
@Serializable(with = PickupActivityContentSerializer::class)
class PickupActivityContent(
    val addressName: String,
    /** Till exempel "Måndag 9 november". "ca" läggs till av vyerna när [estimated] är sant. */
    val dateText: String,
    /** Till exempel "Mån 9 nov". */
    val shortDateText: String,
    val fractions: List<ActivityFraction>,
    val estimated: Boolean,
    warning: String?,
    /** Sant när Utställt är tryckt. Live Updaten visar då en bock i några sekunder innan den försvinner. */
    val placedOut: Boolean = false,
    placedOutDetail: String? = null,
) {
    val warning: String? = warning?.let { text ->
        if (text.graphemeCount() > MAX_WARNING_LENGTH) text.graphemePrefix(MAX_WARNING_LENGTH - 1) + "…" else text
    }

    /** Vem och när, "av dig · kl. 19:42", när kärlen är utställda och det är känt. Annars visas adressen och datumet. */
    val placedOutDetail: String? = if (placedOut) placedOutDetail else null

    /** Samma innehåll med kärlen utställda, och vem och när om det är känt. */
    fun markedPlacedOut(detail: String? = null) =
        PickupActivityContent(addressName, dateText, shortDateText, fractions, estimated, warning, placedOut = true, placedOutDetail = detail)

    override fun equals(other: Any?): Boolean = other is PickupActivityContent && fields == other.fields

    override fun hashCode(): Int = fields.hashCode()

    override fun toString(): String = "PickupActivityContent$fields"

    private val fields: List<Any?>
        get() = listOf(addressName, dateText, shortDateText, fractions, estimated, warning, placedOut, placedOutDetail)

    companion object {
        /** Längsta varning. Allt innehåll ska rymmas i en notis, och höjden på låsskärmen är begränsad. */
        internal const val MAX_WARNING_LENGTH = 200

        const val ALERT_TITLE = "Ställ ut kärlen"

        /** Rubriken när kärlen är utställda. */
        const val PLACED_OUT_TITLE = "Kärlen är utställda"

        /** Knappen i Live Updaten. TalkBack läser den som [PLACED_OUT_TITLE]. */
        const val DONE_BUTTON = "Klart"
    }
}

/** Äldre innehåll, till exempel en schemalagd Live Update från en tidigare version, saknar `placedOut` och får `false`. */
internal object PickupActivityContentSerializer : JsonTreeSerializer<PickupActivityContent>("PickupActivityContent") {
    private val fractionList = ListSerializer(ActivityFraction.serializer())

    override fun read(element: JsonElement): PickupActivityContent {
        val o = element as? JsonObject ?: fail()
        fun present(key: String) = o[key]?.takeIf { it !is JsonNull }
        fun text(key: String) = (present(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
        fun bool(key: String) = (present(key) as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
        val placedOut = bool("placedOut") ?: false
        return PickupActivityContent(
            addressName = text("addressName") ?: fail(),
            dateText = text("dateText") ?: fail(),
            shortDateText = text("shortDateText") ?: fail(),
            fractions = storeJson.decodeFromJsonElement(fractionList, present("fractions") ?: fail()),
            estimated = bool("estimated") ?: fail(),
            warning = text("warning"),
            placedOut = placedOut,
            placedOutDetail = if (placedOut) text("placedOutDetail") else null,
        )
    }

    override fun write(value: PickupActivityContent) = buildJsonObject {
        put("addressName", value.addressName)
        put("dateText", value.dateText)
        put("shortDateText", value.shortDateText)
        put("fractions", storeJson.encodeToJsonElement(fractionList, value.fractions))
        put("estimated", value.estimated)
        value.warning?.let { put("warning", it) }
        put("placedOut", value.placedOut)
        value.placedOutDetail?.let { put("placedOutDetail", it) }
    }

    private fun fail(): Nothing = throw SerializationException("Innehållet går inte att läsa")
}
