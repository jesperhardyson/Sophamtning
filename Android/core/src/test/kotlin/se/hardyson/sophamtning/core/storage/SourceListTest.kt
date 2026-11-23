package se.hardyson.sophamtning.core.storage

import kotlin.test.Test
import kotlin.test.assertNull

// Från SourceListTests på iOS. De andra testerna där prövar AppModel.sourceList, som skrivs om med appmodellen.
class SourceListTest {
    @Test
    fun gammalSparadListaUtanAppversionAvkodas() {
        val json = """{"response":{"sources":[],"fractions":{}},"fetchedAt":0}"""
        val cached = storeJson.decodeFromString(CachedSources.serializer(), json)
        assertNull(cached.appVersion)
    }
}
