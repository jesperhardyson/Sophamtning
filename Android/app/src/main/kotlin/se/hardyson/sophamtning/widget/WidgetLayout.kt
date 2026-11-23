package se.hardyson.sophamtning.widget

/**
 * Vad som ryms i widgeten, räknat från höjden innanför kanten och systemets textstorlek. Widgeten kan inte mäta texten,
 * så höjderna är uppskattningar i dp. Rena funktioner, så att det går att testa att inget klipps.
 */
internal object WidgetLayout {
    /** Texterna krymper hellre än att klippas, som `minimumScaleFactor` på iOS, ner till så här. */
    const val MIN_SCALE = 0.6f

    /** Radhöjden i förhållande till textstorleken. */
    const val LINE_HEIGHT = 1.3f

    /** Ikonraden i den lilla widgeten, 40 dp hög med luft ovanför. */
    const val ICON_ROW = 46f

    const val MAX_ROWS = 3
    const val ROW_SPACING = 4f
    const val BUTTON_HEIGHT = 40f
    const val BUTTON_SPACING = 6f
    const val TILE_HEADER = 24f

    /** Höjden en rad text tar, i dp. */
    fun lineHeight(size: Float, fontScale: Float, scale: Float): Float = size * LINE_HEIGHT * fontScale * scale

    /** Den lilla widgeten: textstorleken, vilka rader som visas, och höjden allt tar. */
    data class Small(val scale: Float, val showsName: Boolean, val showsDate: Boolean, val showsPlacedOut: Boolean, val showsEnding: Boolean, val height: Float)

    /** Lägst textstorlek när inget annat hjälper, så att texten hellre blir liten än klipps. */
    const val FLOOR_SCALE = 0.25f

    fun small(inner: Float, fontScale: Float, placedOut: Boolean, ending: Boolean): Small {
        val room = inner - ICON_ROW
        val name = lineHeight(14f, fontScale, 1f)
        val relative = lineHeight(28f, fontScale, 1f)
        val date = lineHeight(16f, fontScale, 1f)
        // Kärlen syns alltid. Ryms inte rubrikerna tas datumet bort först och sedan namnet, som båda läses av TalkBack
        // ändå. Först därefter krymper dagen under den vanliga gränsen.
        val variants = listOf(Triple(true, true, name + relative + date), Triple(true, false, name + relative), Triple(false, false, relative))
        val chosen = variants.firstOrNull { room / it.third >= MIN_SCALE } ?: variants.last()
        val (showsName, showsDate, texts) = chosen
        val scale = (room / texts).coerceIn(FLOOR_SCALE, 1f)
        var used = texts * scale + ICON_ROW
        val placedOutLine = lineHeight(13f, fontScale, scale) + 6
        val showsPlacedOut = placedOut && inner - used >= placedOutLine
        if (showsPlacedOut) used += placedOutLine
        val endingLine = lineHeight(12f, fontScale, scale) + 6
        val showsEnding = ending && inner - used >= endingLine
        if (showsEnding) used += endingLine
        return Small(scale, showsName, showsDate, showsPlacedOut, showsEnding, used)
    }

    /**
     * Den mellanstora widgeten: textstorleken, hur många kärl som står på egna rader, om "+N till" visas, och höjden
     * allt tar. [sameDay] är antalet kärl som töms det datum som står på bladet.
     */
    data class Medium(
        val scale: Float,
        val rows: Int,
        val hidden: Int,
        val showsPlacedOut: Boolean,
        val showsEnding: Boolean,
        /** Höjden till höger, med raderna och knappen. */
        val height: Float,
        /** Höjden till vänster, med brickan och namnet. */
        val tileHeight: Float,
    )

    fun medium(inner: Float, fontScale: Float, sameDay: Int, placeOut: Boolean, placedOut: Boolean, ending: Boolean): Medium {
        // Brickan och namnet under krymper så att de ryms på höjden. Brickans rubrik och luft är fasta.
        val tileFixed = TILE_HEADER + 8
        val tileText = lineHeight(32f, fontScale, 1f) + lineHeight(12f, fontScale, 1f) + lineHeight(13f, fontScale, 1f)
        val scale = ((inner - tileFixed) / tileText).coerceIn(FLOOR_SCALE, 1f)
        val button = if (placeOut) BUTTON_HEIGHT + BUTTON_SPACING else 0f
        val row = maxOf(28f, lineHeight(15f, fontScale, scale)) + ROW_SPACING
        val more = lineHeight(13f, fontScale, scale) + 6
        val top = lineHeight(24f, fontScale, scale) + 6 + button
        // Så många kärl på egna rader som ryms, högst tre, eller två med knappen. Ryms inte alla står resten som "+N till",
        // som tar en rads plats av de tre. Det första kärlet står hellre kvar med "+N till" än att bara "+N till" visas,
        // vilket skiljer sig från iOS. Ryms inga rader alls står bara dagen och knappen kvar, och "+N till" om den ryms.
        val most = if (placeOut) MAX_ROWS - 1 else MAX_ROWS
        var rows = 0
        var hidden = 0
        var used = top
        for (shown in minOf(sameDay, most) downTo 0) {
            val rest = sameDay - shown
            if (rest > 0 && shown > maxOf(most - 1, 1)) continue
            val height = top + shown * row + if (rest > 0) more else 0f
            if (height <= inner) {
                rows = shown
                hidden = rest
                used = height
                break
            }
        }
        val placedOutLine = lineHeight(13f, fontScale, scale) + 6
        val showsPlacedOut = placedOut && inner - used >= placedOutLine
        if (showsPlacedOut) used += placedOutLine
        val endingLine = lineHeight(13f, fontScale, scale) + 6
        val showsEnding = ending && inner - used >= endingLine
        if (showsEnding) used += endingLine
        return Medium(scale, rows, hidden, showsPlacedOut, showsEnding, used, tileFixed + tileText * scale)
    }
}
