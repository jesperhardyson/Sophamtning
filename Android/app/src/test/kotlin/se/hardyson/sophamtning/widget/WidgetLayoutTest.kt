package se.hardyson.sophamtning.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Att inget i widgeten klipps: allt som visas ryms på höjden innanför kanten, vid normal och största textstorlek. */
class WidgetLayoutTest {
    private val heights = listOf(76f, 100f, 150f)
    private val fontScales = listOf(1.0f, 2.0f)

    @Test
    fun litenRymsOchKarlenSynsAlltid() {
        for (inner in heights) for (fontScale in fontScales) for (placedOut in listOf(false, true)) for (ending in listOf(false, true)) {
            val layout = WidgetLayout.small(inner, fontScale, placedOut, ending)
            // Ikonraden är alltid med i höjden, och allt ryms.
            assertTrue("$inner dp, textstorlek $fontScale: $layout", layout.height <= inner + 0.5f)
        }
        // Med plats nog visas allt i full storlek.
        val roomy = WidgetLayout.small(150f, 1.0f, placedOut = false, ending = false)
        assertEquals(1f, roomy.scale)
        assertTrue(roomy.showsName && roomy.showsDate)
    }

    @Test
    fun mellanRymsMedKnappenOchPlusTill() {
        for (inner in heights) for (fontScale in fontScales) for (placeOut in listOf(false, true)) for (sameDay in 1..4) {
            val layout = WidgetLayout.medium(inner, fontScale, sameDay, placeOut, placedOut = false, ending = true)
            val label = "$inner dp, textstorlek $fontScale, knapp $placeOut, $sameDay kärl: $layout"
            assertTrue(label, layout.height <= inner + 0.5f)
            assertTrue(label, layout.tileHeight <= inner + 0.5f)
            // Kärl som inte står på egna rader räknas i "+N till", eller visas inte alls när inte ens den raden ryms.
            assertTrue(label, layout.rows + layout.hidden <= sameDay)
        }
        // Med plats nog står tre kärl på var sin rad.
        val roomy = WidgetLayout.medium(150f, 1.0f, sameDay = 3, placeOut = false, placedOut = false, ending = false)
        assertEquals(3, roomy.rows)
        assertEquals(0, roomy.hidden)
    }
}
