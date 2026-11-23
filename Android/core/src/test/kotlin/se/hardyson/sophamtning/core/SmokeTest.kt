package se.hardyson.sophamtning.core

import kotlin.test.Test
import kotlin.test.assertEquals

class SmokeTest {
    @Test
    fun modulenFinns() {
        assertEquals("se.hardyson.sophamtning.core", CoreInfo.PACKAGE)
    }
}
