package se.hardyson.sophamtning.core.api

import se.hardyson.sophamtning.core.kommun.kommunDisplayName

/** Kommunerna källan täcker, med hela namnen: "Avesta kommun, Hedemora kommun och Säters kommun". */
val Source.kommunerText: String
    get() {
        val names = kommuner.map { kommunDisplayName(it.name) }.filter { it.isNotEmpty() }
        if (names.size <= 1) return names.firstOrNull() ?: ""
        return names.dropLast(1).joinToString(", ") + " och " + names.last()
    }
