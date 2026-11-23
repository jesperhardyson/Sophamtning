package se.hardyson.sophamtning.core.dates

import java.time.LocalDate
import java.util.Locale
import java.time.temporal.ChronoUnit
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** Ett kalenderdatum utan klockslag, kodat som "YYYY-MM-DD". */
@Serializable(with = DayDateSerializer::class)
data class DayDate(val year: Int, val month: Int, val day: Int) : Comparable<DayDate> {
    val iso: String get() = String.format(Locale.ROOT, "%04d-%02d-%02d", year, month, day)

    fun plusDays(days: Int): DayDate = from(toLocalDate().plusDays(days.toLong()))

    /** Antal dagar från detta datum till [other]. Negativt om [other] ligger före. */
    fun daysUntil(other: DayDate): Int = ChronoUnit.DAYS.between(toLocalDate(), other.toLocalDate()).toInt()

    override fun compareTo(other: DayDate): Int = compareValuesBy(this, other, { it.year }, { it.month }, { it.day })

    internal fun toLocalDate(): LocalDate = LocalDate.of(year, month, day)

    companion object {
        private val pattern = Regex("""^[0-9]{4}-[0-9]{2}-[0-9]{2}$""")

        /** Tolkar exakt "YYYY-MM-DD". Ogiltiga datum, som 30 februari, ger `null`. */
        fun parse(iso: String): DayDate? {
            if (!pattern.matches(iso)) return null
            val (year, month, day) = iso.split("-").map(String::toInt)
            return runCatching { from(LocalDate.of(year, month, day)) }.getOrNull()
        }

        internal fun from(date: LocalDate) = DayDate(date.year, date.monthValue, date.dayOfMonth)
    }
}

object DayDateSerializer : KSerializer<DayDate> {
    override val descriptor = PrimitiveSerialDescriptor("DayDate", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: DayDate) = encoder.encodeString(value.iso)

    override fun deserialize(decoder: Decoder): DayDate {
        val text = decoder.decodeString()
        return DayDate.parse(text) ?: throw SerializationException("Ogiltigt datum: $text")
    }
}
