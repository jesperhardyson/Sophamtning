package se.hardyson.sophamtning.ui.theme

import androidx.compose.ui.graphics.Color

/** Designens färger, med samma namn och värden som ThemeToken i SophamtningDesign på iOS. */
enum class ThemeToken(light: Long, dark: Long, lightAlpha: Int = 0xFF, darkAlpha: Int = 0xFF) {
    Bg(0xE8F2EA, 0x0C1A12),
    Surface(0xFFFFFF, 0x14241A),
    Surface2(0xDCEBDF, 0x1C2F23),
    Border(0xCCDFD0, 0x28402F),
    Text(0x1B231F, 0xEDF2EE),
    Text2(0x526158, 0xA0B3A6),
    Primary(0x157A46, 0x4CC384),
    OnPrimary(0xFFFFFF, 0x0B2416),
    Brand(0x1FA35C, 0x4CC384),
    BrandSoft(0xCFEBD8, 0x1A3D28),
    BrandText(0x12673B, 0x8FE0B2),
    Earth(0x8A5A2B, 0xD9A06A),
    EarthSoft(0xF3EADF, 0x2E241A),
    Warn(0x9A4A00, 0xF4B56A),
    WarnBg(0xFDEFD9, 0x3A2914),
    FracRest(0x474C48, 0xC3C9C4),
    FracRestBg(0xE9EAE7, 0x2A2F2C),
    FracMat(0x7A4A1E, 0xE0A873),
    FracMatBg(0xF3E6D8, 0x3A2C1F),
    FracPapper(0x2E5E86, 0x8DB6DE),
    FracPapperBg(0xE1EAF3, 0x1C2A38),
    FracPlast(0xA8431F, 0xF0906C),
    FracPlastBg(0xFAE6DD, 0x3D241B),
    FracGlas(0x1F6A7A, 0x72C6D6),
    FracGlasBg(0xDDEFF2, 0x173238),
    FracMetall(0x6B4F7A, 0xC6A9D6),
    FracMetallBg(0xEEE6F1, 0x2E2436),
    // Senapsgul, så att tidningar går att skilja från pappersförpackningar (blå) och glas (turkos).
    FracTidningar(0x6B5A0E, 0xE3C866),
    FracTidningarBg(0xF4EECF, 0x2F2A15),
    CardOverlay(0xFFFFFF, 0x0B2416, lightAlpha = 0x26, darkAlpha = 0x1F),
    // Reglaget som är på, på det gröna huvudkortet. Mörkt i båda lägena.
    ToggleOn(0x0B2416, 0x0B2416),
    ;

    val light = Color((lightAlpha.toLong() shl 24) or light)
    val dark = Color((darkAlpha.toLong() shl 24) or dark)

    fun color(darkTheme: Boolean) = if (darkTheme) dark else light
}
