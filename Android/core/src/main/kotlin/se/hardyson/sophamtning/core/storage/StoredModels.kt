package se.hardyson.sophamtning.core.storage

import java.security.MessageDigest
import java.time.Instant
import kotlinx.serialization.SerialName
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
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.SourcesResponse
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.SwedishFormat

/** Nyckeln till en sparad adress. Id:t sparas som API:t levererade det och tolkas aldrig. */
@Serializable
data class AddressKey(val source: String, val id: String) {
    /** SHA-256 av `source + "\u0000" + id` som hexadecimal text. Säkert som filnamn oavsett tecknen i id:t. */
    val fileName: String
        get() = MessageDigest.getInstance("SHA-256").digest((source + "\u0000" + id).encodeToByteArray())
            .joinToString("") { "%02x".format(java.util.Locale.ROOT, it) }
}

@Serializable
data class SavedAddress(
    val key: AddressKey,
    /** Adressens schema i API:t. Procentkodad och får inte kodas om. */
    val url: String,
    val street: String,
    val locality: String,
    val kommun: String,
    val detail: String? = null,
    val selection: String,
    val displayName: String,
    val isPrimary: Boolean,
    val notificationsOn: Boolean = false,
    @Serializable(with = SwiftDateSerializer::class) val addedAt: Instant,
)

/** Ett av valen för när en påminnelse kommer: kvällen före tömningen eller samma morgon. */
@Serializable
enum class ReminderTiming {
    @SerialName("eveningBefore") EveningBefore,
    @SerialName("sameMorning") SameMorning,
    ;

    /** Förvald tid i minuter efter midnatt: 18:00 eller 06:00. */
    val defaultMinutes: Int get() = if (this == EveningBefore) 1080 else 360

    /** Giltiga tider: 15:00–23:00 eller 05:00–09:00. */
    internal val range: IntRange get() = if (this == EveningBefore) 900..1380 else 300..540

    /** Alla giltiga tider i ordning, i steg om 15 minuter. */
    val times: List<Int> get() = (range step 15).toList()

    internal val raw: String get() = if (this == EveningBefore) "eveningBefore" else "sameMorning"

    companion object {
        internal fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

@Serializable(with = ReminderSettingsSerializer::class)
data class ReminderSettings(
    /** Påminnelse kvällen före tömningen. På från början. */
    val eveningOn: Boolean = true,
    /** Påminnelse samma morgon som tömningen. Av från början. Minst ett av valen är alltid på. */
    val morningOn: Boolean = false,
    /** Kvällstiden, i minuter efter midnatt i Europe/Stockholm. 1080 är 18:00. */
    val reminderMinutes: Int = 1080,
    /** Morgontiden, i minuter efter midnatt i Europe/Stockholm. 360 är 06:00. */
    val morningMinutes: Int = 360,
    /** Vilket val Live Update följer: dagen före eller samma morgon. */
    val liveActivityTiming: ReminderTiming = ReminderTiming.EveningBefore,
    /** Live Updates egen starttid. Utan egen tid får den tiden som notisen för samma val har. */
    val liveActivityMinutes: Int = (if (liveActivityTiming == ReminderTiming.EveningBefore) reminderMinutes else morningMinutes)
        .let { if (isValid(it, liveActivityTiming)) it else liveActivityTiming.defaultMinutes },
    val liveActivityOn: Boolean = false,
    /** Förslaget om påminnelse efter första adressen har visats och besvarats, eller en påminnelse har slagits på. */
    val reminderOfferShown: Boolean = false,
    /** Notis när källan har ett nytt meddelande. På från början, men skickas bara när systemet redan tillåter notiser. */
    val sourceMessagesOn: Boolean = true,
) {
    /** Den sparade tiden för valet. En ogiltig sparad tid ger förvalet. */
    fun minutes(timing: ReminderTiming): Int {
        val minutes = if (timing == ReminderTiming.EveningBefore) reminderMinutes else morningMinutes
        return if (isValid(minutes, timing)) minutes else timing.defaultMinutes
    }

    /** Live Updates starttid. En tid som inte går för valet ger notisens tid för valet. */
    val liveActivityStartMinutes: Int
        get() = if (isValid(liveActivityMinutes, liveActivityTiming)) liveActivityMinutes else minutes(liveActivityTiming)

    /** Notisen för valet kommer vid samma tid som Live Update. Bara då ersätts den av en reserv. */
    fun notificationMatchesLiveActivity(timing: ReminderTiming) =
        timing == liveActivityTiming && isEnabled(timing) && minutes(timing) == liveActivityStartMinutes

    fun isEnabled(timing: ReminderTiming) = if (timing == ReminderTiming.EveningBefore) eveningOn else morningOn

    /** Påslagna val i ordningen kväll, morgon. Aldrig tom: är båda av räknas kvällen. */
    val enabledTimings: List<ReminderTiming>
        get() = ReminderTiming.entries.filter(::isEnabled).ifEmpty { listOf(ReminderTiming.EveningBefore) }

    /** Det sista påslagna valet under dygnet: morgonen när den är på, annars kvällen. */
    val latestTiming: ReminderTiming get() = enabledTimings.last()

    /** Värdet på raden Påminnelse i inställningarna. */
    val settingsValue: String
        get() {
            val timings = enabledTimings
            if (timings.size == 2) {
                return "${SwedishFormat.clock(minutes(ReminderTiming.EveningBefore))} och ${SwedishFormat.clock(minutes(ReminderTiming.SameMorning))}"
            }
            val timing = timings[0]
            val label = if (timing == ReminderTiming.EveningBefore) "Kvällen före" else "Samma morgon"
            return "$label, ${SwedishFormat.clock(minutes(timing))}"
        }

    companion object {
        /** Giltigt är det valdas tider i steg om 15 minuter. */
        fun isValid(minutes: Int, timing: ReminderTiming) = minutes in timing.range && minutes % 15 == 0
    }
}

/**
 * Som `init(from:)` på iOS. Inställningar sparade före `reminderOfferShown` läses som att förslaget inte har visats. Sparade
 * med det gamla enda valet (`timing`) läses valet som det enda påslagna och som Live Update-val. Ett okänt val läses som
 * kvällen före, så att filen inte blir oläslig. Är båda valen av blir kvällen på.
 */
internal object ReminderSettingsSerializer : JsonTreeSerializer<ReminderSettings>("ReminderSettings") {
    override fun read(element: JsonElement): ReminderSettings {
        val o = element as? JsonObject ?: fail()
        fun present(key: String) = o[key]?.takeIf { it !is JsonNull }
        fun int(key: String) = (present(key) as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
        fun bool(key: String) = (present(key) as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
        fun text(key: String) = (present(key) as? JsonPrimitive)?.takeIf { it.isString }?.content
        // Ett fält som finns men har fel typ gör filen oläslig, som decodeIfPresent på iOS.
        fun checked(key: String, value: Any?) = if (present(key) != null && value == null) fail() else value
        val reminderMinutes = checked("reminderMinutes", int("reminderMinutes")) as Int? ?: fail()
        val liveActivityOn = checked("liveActivityOn", bool("liveActivityOn")) as Boolean? ?: fail()
        val offerShown = checked("reminderOfferShown", bool("reminderOfferShown")) as Boolean? ?: false
        val sourceMessagesOn = checked("sourceMessagesOn", bool("sourceMessagesOn")) as Boolean? ?: true
        val morningMinutes = checked("morningMinutes", int("morningMinutes")) as Int? ?: ReminderTiming.SameMorning.defaultMinutes
        val old = ReminderTiming.fromRaw(checked("timing", text("timing")) as String?) ?: ReminderTiming.EveningBefore
        val evening = checked("eveningOn", bool("eveningOn")) as Boolean?
        val morning = checked("morningOn", bool("morningOn")) as Boolean?
        var eveningOn: Boolean
        val morningOn: Boolean
        if (evening == null && morning == null) {
            eveningOn = old == ReminderTiming.EveningBefore
            morningOn = old == ReminderTiming.SameMorning
        } else {
            eveningOn = evening ?: false
            morningOn = morning ?: false
        }
        if (!eveningOn && !morningOn) eveningOn = true
        val liveTiming = ReminderTiming.fromRaw(checked("liveActivityTiming", text("liveActivityTiming")) as String?) ?: old
        val base = ReminderSettings(
            eveningOn = eveningOn, morningOn = morningOn, reminderMinutes = reminderMinutes, morningMinutes = morningMinutes,
            liveActivityTiming = liveTiming, liveActivityOn = liveActivityOn, reminderOfferShown = offerShown,
            sourceMessagesOn = sourceMessagesOn,
        )
        // Sparade före den egna tiden: Live Update behåller tiden den hade, notisens tid för samma val.
        val liveMinutes = checked("liveActivityMinutes", int("liveActivityMinutes")) as Int? ?: base.minutes(liveTiming)
        return base.copy(liveActivityMinutes = liveMinutes)
    }

    override fun write(value: ReminderSettings) = buildJsonObject {
        put("eveningOn", value.eveningOn)
        put("morningOn", value.morningOn)
        put("reminderMinutes", value.reminderMinutes)
        put("morningMinutes", value.morningMinutes)
        put("liveActivityTiming", value.liveActivityTiming.raw)
        put("liveActivityMinutes", value.liveActivityMinutes)
        put("liveActivityOn", value.liveActivityOn)
        put("reminderOfferShown", value.reminderOfferShown)
        put("sourceMessagesOn", value.sourceMessagesOn)
    }

    private fun fail(): Nothing = throw SerializationException("Inställningarna går inte att läsa")
}

@Serializable(with = CachedScheduleSerializer::class)
data class CachedSchedule(
    val response: AddressResponse? = null,
    val fetchedAt: Instant? = null,
    val lastAttemptAt: Instant? = null,
    val lastError: ApiError? = null,
)

/** Svaret läses med samma regler som ett nytt svar (`ApiDecoding`). Felet kodas som Swifts `APIError`. */
internal object CachedScheduleSerializer : JsonTreeSerializer<CachedSchedule>("CachedSchedule") {
    override fun read(element: JsonElement): CachedSchedule {
        val o = element as? JsonObject ?: throw SerializationException("Schemat går inte att läsa")
        fun present(key: String) = o[key]?.takeIf { it !is JsonNull }
        return CachedSchedule(
            response = present("response")?.let(ApiDecoding::addressResponse),
            fetchedAt = present("fetchedAt")?.let { storeJson.decodeFromJsonElement(SwiftDateSerializer, it) },
            lastAttemptAt = present("lastAttemptAt")?.let { storeJson.decodeFromJsonElement(SwiftDateSerializer, it) },
            lastError = present("lastError")?.let(::readError),
        )
    }

    override fun write(value: CachedSchedule) = buildJsonObject {
        value.response?.let { put("response", ApiDecoding.json.encodeToJsonElement(AddressResponse.serializer(), it)) }
        value.fetchedAt?.let { put("fetchedAt", storeJson.encodeToJsonElement(SwiftDateSerializer, it)) }
        value.lastAttemptAt?.let { put("lastAttemptAt", storeJson.encodeToJsonElement(SwiftDateSerializer, it)) }
        value.lastError?.let { put("lastError", writeError(it)) }
    }

    // Swift kodar `enum APIError` som {"network":{}} och {"unexpected":{"_0":500}}.
    private fun readError(e: JsonElement): ApiError {
        val o = e as? JsonObject ?: throw SerializationException("Okänt fel")
        val (name, body) = o.entries.singleOrNull() ?: throw SerializationException("Okänt fel")
        return when (name) {
            "badRequest" -> ApiError.BadRequest
            "notFound" -> ApiError.NotFound
            "sourceUnavailable" -> ApiError.SourceUnavailable
            "network" -> ApiError.Network
            "unexpected" -> ApiError.Unexpected(((body as? JsonObject)?.get("_0") as? JsonPrimitive)?.intOrNull ?: throw SerializationException("Okänt fel"))
            else -> throw SerializationException("Okänt fel")
        }
    }

    private fun writeError(error: ApiError): JsonElement = buildJsonObject {
        when (error) {
            ApiError.BadRequest -> put("badRequest", JsonObject(emptyMap()))
            ApiError.NotFound -> put("notFound", JsonObject(emptyMap()))
            ApiError.SourceUnavailable -> put("sourceUnavailable", JsonObject(emptyMap()))
            ApiError.Network -> put("network", JsonObject(emptyMap()))
            is ApiError.Unexpected -> put("unexpected", buildJsonObject { put("_0", error.status) })
        }
    }
}

/** Att soporna ställts ut för en adress och ett hämtdatum. */
@Serializable
data class PlacedOut(val key: AddressKey, val date: DayDate)

@Serializable(with = CachedSourcesSerializer::class)
data class CachedSources(
    val response: SourcesResponse,
    val fetchedAt: Instant,
    /** Appens version och bygge när listan hämtades. En ny version hämtar listan direkt. */
    val appVersion: String? = null,
)

internal object CachedSourcesSerializer : JsonTreeSerializer<CachedSources>("CachedSources") {
    override fun read(element: JsonElement): CachedSources {
        val o = element as? JsonObject ?: throw SerializationException("Källorna går inte att läsa")
        return CachedSources(
            response = ApiDecoding.sourcesResponse(o["response"] ?: throw SerializationException("response saknas")),
            fetchedAt = storeJson.decodeFromJsonElement(SwiftDateSerializer, o["fetchedAt"] ?: throw SerializationException("fetchedAt saknas")),
            appVersion = (o["appVersion"] as? JsonPrimitive)?.takeIf { it.isString }?.content,
        )
    }

    override fun write(value: CachedSources) = buildJsonObject {
        put("response", ApiDecoding.json.encodeToJsonElement(SourcesResponse.serializer(), value.response))
        put("fetchedAt", storeJson.encodeToJsonElement(SwiftDateSerializer, value.fetchedAt))
        value.appVersion?.let { put("appVersion", it) }
    }
}
