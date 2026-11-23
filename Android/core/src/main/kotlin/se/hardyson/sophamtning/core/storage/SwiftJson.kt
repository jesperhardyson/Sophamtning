package se.hardyson.sophamtning.core.storage

import java.time.Instant
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder

/** JSON för de sparade filerna. Okända fält, till exempel från en senare version, ignoreras. */
internal val storeJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
}

/**
 * Tidpunkter kodas som `JSONEncoder` på iOS gör som standard: sekunder sedan 1 januari 2001 UTC, som decimaltal.
 * Så blir filerna i samma format som iOS-appens.
 */
object SwiftDateSerializer : KSerializer<Instant> {
    private val reference: Instant = Instant.parse("2001-01-01T00:00:00Z")

    override val descriptor = PrimitiveSerialDescriptor("SwiftDate", PrimitiveKind.DOUBLE)

    override fun serialize(encoder: Encoder, value: Instant) {
        val nanos = java.time.Duration.between(reference, value).toNanos()
        encoder.encodeDouble(nanos / 1_000_000_000.0)
    }

    override fun deserialize(decoder: Decoder): Instant {
        val seconds = decoder.decodeDouble()
        if (!seconds.isFinite()) throw SerializationException("Ogiltig tid")
        return reference.plusNanos(Math.round(seconds * 1_000_000_000.0))
    }
}

/** Grund för typer som läses och skrivs för hand som JSON-träd, med samma förlåtande regler som `init(from:)` på iOS. */
internal abstract class JsonTreeSerializer<T>(name: String) : KSerializer<T> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor(name)

    abstract fun read(element: JsonElement): T
    abstract fun write(value: T): JsonElement

    override fun deserialize(decoder: Decoder): T {
        val json = decoder as? JsonDecoder ?: throw SerializationException("Bara JSON")
        return try {
            read(json.decodeJsonElement())
        } catch (e: SerializationException) {
            throw e
        } catch (e: Exception) {
            throw SerializationException(e.message ?: "Går inte att läsa")
        }
    }

    override fun serialize(encoder: Encoder, value: T) {
        val json = encoder as? JsonEncoder ?: throw SerializationException("Bara JSON")
        json.encodeJsonElement(write(value))
    }
}
