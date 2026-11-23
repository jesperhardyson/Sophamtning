package se.hardyson.sophamtning.core.messages

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import se.hardyson.sophamtning.core.api.SourceMessage
import se.hardyson.sophamtning.core.dates.DayDate

/** Ett meddelande hos en källa. `id` är bara unikt inom källan, så källan ingår i nyckeln. */
data class SourceMessageKey(val source: String, val id: String)

/** Ett meddelande som gäller i dag, med källan det hör till. */
data class ActiveSourceMessage(val source: String, val message: SourceMessage) {
    val key: SourceMessageKey get() = SourceMessageKey(source, message.id)
    val id: String get() = "$source/${message.id}"
}

object SourceMessages {
    /**
     * Meddelandena som gäller [today], från de sparade adressernas svar, som par av källa och meddelanden. Samma
     * meddelande hos flera adresser blir ett. Ordningen är `validFrom` och sedan `id`, som i API:t, och källan när två
     * källor har samma. Datumen räknas om här, eftersom ett sparat svar kan vara äldre än meddelandets sista dag.
     */
    fun active(sources: List<Pair<String, List<SourceMessage>>>, today: DayDate): List<ActiveSourceMessage> {
        val seen = mutableSetOf<SourceMessageKey>()
        val result = mutableListOf<ActiveSourceMessage>()
        for ((source, messages) in sources) {
            for (message in messages) {
                if (message.validFrom > today || today > message.validTo) continue
                val item = ActiveSourceMessage(source, message)
                if (seen.add(item.key)) result += item
            }
        }
        return result.sortedWith(compareBy<ActiveSourceMessage> { it.message.validFrom }.thenBy { it.message.id }.thenBy { it.source })
    }

    /** De som inte är sedda än, i samma ordning. */
    fun unseen(active: List<ActiveSourceMessage>, memory: SourceMessageMemory): List<ActiveSourceMessage> =
        active.filter { !memory.isSeen(it.key) }

    /** Identifieraren för notisen, som på iOS. Notisens heltals-id på Android räknas fram av den. */
    fun notificationId(key: SourceMessageKey): String = "kalla.${key.source}.${key.id}"
}

/**
 * Sedda och stängda meddelanden, sparade i `source-messages.json` som `{ "<källa>": { "seen": [], "dismissed": [] } }`,
 * som på iOS. Sett betyder att meddelandet inte ska ge någon notis. Stängt betyder att kortet inte visas. Inget tas bort,
 * eftersom ett `id` aldrig återanvänds och filen förblir liten. Värdet ändras inte, utan [markSeen] och [dismiss] ger ett nytt.
 */
@Serializable(with = SourceMessageMemorySerializer::class)
class SourceMessageMemory internal constructor(internal val sources: Map<String, Entry>) {
    constructor() : this(emptyMap())

    @Serializable
    internal data class Entry(val seen: List<String>, val dismissed: List<String>)

    fun isSeen(key: SourceMessageKey): Boolean = sources[key.source]?.seen?.contains(key.id) ?: false

    fun isDismissed(key: SourceMessageKey): Boolean = sources[key.source]?.dismissed?.contains(key.id) ?: false

    fun markSeen(keys: List<SourceMessageKey>): SourceMessageMemory {
        var result = this
        for (key in keys) {
            if (result.isSeen(key)) continue
            result = result.changing(key.source) { it.copy(seen = it.seen + key.id) }
        }
        return result
    }

    fun dismiss(key: SourceMessageKey): SourceMessageMemory {
        if (isDismissed(key)) return this
        return changing(key.source) { it.copy(dismissed = it.dismissed + key.id) }
    }

    private fun changing(source: String, change: (Entry) -> Entry): SourceMessageMemory =
        SourceMessageMemory(sources + (source to change(sources[source] ?: Entry(seen = emptyList(), dismissed = emptyList()))))

    override fun equals(other: Any?) = other is SourceMessageMemory && other.sources == sources

    override fun hashCode() = sources.hashCode()

    override fun toString() = "SourceMessageMemory($sources)"
}

/** Kodar minnet som en ordbok med källan som nyckel, utan omslutande fält, som `singleValueContainer` på iOS. */
internal object SourceMessageMemorySerializer : KSerializer<SourceMessageMemory> {
    private val map = MapSerializer(String.serializer(), SourceMessageMemory.Entry.serializer())

    override val descriptor = map.descriptor

    override fun serialize(encoder: Encoder, value: SourceMessageMemory) = map.serialize(encoder, value.sources)

    override fun deserialize(decoder: Decoder) = SourceMessageMemory(map.deserialize(decoder))
}
