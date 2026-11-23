package se.hardyson.sophamtning.ui.bin

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.vector.PathParser

/**
 * Kärlets delar, översatta från SVG:n i Sopors `index.html` (viewBox `60 -110 360 560`), som BinArtwork.swift. Banorna är
 * kopierade ordagrant och ritas i SVG:ns koordinater, med färgerna från SVG:n. De är desamma i ljust och mörkt läge.
 */
object BinArtwork {
    /** SVG:ns viewBox. Koordinaterna i delarna är i SVG:ns enheter. */
    val viewBox = Rect(60f, -110f, 420f, 450f)

    /** Gångjärnet (`.lock { transform-origin: 358px 95px }`) och kroppens vridpunkt (`.kropp { transform-origin: 240px 430px }`). */
    val hinge = Offset(358f, 95f)
    val bodyPivot = Offset(240f, 430f)

    /** Markskuggans ellips (`<ellipse cx="240" cy="428" rx="115" ry="13">`), som följer temats `surface-2`. */
    val shadow = Rect(240f - 115f, 428f - 13f, 240f + 115f, 428f + 13f)

    /** Var trycket gäller: kärlets kropp och lock, x 115 till 375 och y 40 till 441, inte ytan ovanför där fraktionen faller. */
    val tapArea = Rect(115f, 40f, 375f, 441f)

    /** En del av kärlet: en bana eller hjulnavets vridna ellips. */
    sealed interface Part {
        val color: Color
        val isEmpty: Boolean
    }

    /** En bana med `transform="translate(x y)"` och fyllnadsfärg. */
    class PathPart(color: Long, x: Float, y: Float, d: String) : Part {
        override val color = Color(0xFF000000 or color)
        val path: Path = PathParser().parsePathString(d).toPath().apply { translate(Offset(x, y)) }
        override val isEmpty: Boolean get() = path.isEmpty
    }

    /** Ellipsen för hjulnavet, `transform="rotate(5.6 cx cy)"`. */
    class EllipsePart(color: Long, cx: Float, cy: Float, rx: Float, ry: Float, val rotation: Float) : Part {
        override val color = Color(0xFF000000 or color)
        val bounds = Rect(cx - rx, cy - ry, cx + rx, cy + ry)
        override val isEmpty: Boolean get() = bounds.isEmpty
    }

    /** Locket, i SVG:ns ordning (`<g id="karl-lock">`). */
    val lidParts: List<Part> by lazy {
        listOf(
            PathPart(0x179E61, 115.98f, 89.53f, "M0 16.44l0 13.02c0 4.2 5.88 6.36 11.58 6.78l136.38001 9.47999c10.85998 0.66 21.23999-0.06 27.66-2.22l63.78-23.7c2.10001-0.84 3.11999-1.8 3.11999-3.72l0-16.07999-242.52 16.44z"),
            PathPart(0x129258, 115.98f, 61.27f, "M11.22157 37.62c-6.36 1.74-11.04 3.84-11.22 6.72-0.12 2.88001 6.66 4.44 12.95999 4.92l134.27999 7.74c11.28003 0.72 22.08001-0.18001 29.70001-2.76l61.86001-22.26c3.54001-1.43999 4.56-4.25999 2.70002-5.94l-14.52002-11.4-9.60001-9.84c-1.67999-0.84-4.37997-1.14001-7.44-1.32l-14.81998-0.84-120.48001-2.64c-19.44 7.62-43.79999 19.98-55.68001 27.3-4.13998 2.93999-6.11999 7.25999-7.73999 10.32z"),
            PathPart(0x0D7948, 125.62f, 66.43f, "M207.7431 0l-54.6 31.26c-4.55997 2.34-9.9 2.88-16.13999 2.58l-129.65999-6.78c-3.78 2.94-6.48 6.53999-7.26 9.54-0.66 2.22 2.7 3.48001 6.9 3.78l129.23999 8.1c10.98001 0.72 21.18003 0 28.62-2.34l57.36001-20.45999c1.56-0.72 1.97999-2.04 1.62-3.72-2.28-8.94-8.70001-18.78-16.08002-21.96001z"),
            PathPart(0x128351, 343.02f, 75.91f, "M0 0l12.95999 0.54c5.34 0.3 8.04001 5.82 8.04001 13.8 0 7.38001-3 12.78-5.88003 13.56l0-13.14001c-0.23999-2.09999-1.73999-2.75999-4.38001-2.57999l-4.13998 0.36c-0.95999-4.62-3.66-9.18-6.59998-12.54z"),
            PathPart(0x0D643D, 349.38f, 76.62f, "M7.56 0.00732c-4.62-0.24-7.20001 5.46-7.56 10.8l3.95999-0.12c2.76001-1.02 5.34 0.66 5.4 3.48001l0 12.47999c3.29999-1.02001 5.28003-6.78 5.28003-13.02 0-7.8-2.88004-13.37999-7.08002-13.62z"),
            PathPart(0x128D57, 190.5f, 40.69f, "M11.34 0.00061c-7.61999-0.06-11.34 4.32-11.34 10.38l0 11.34c5.03999 1.5 15.06 2.34 16.44-0.3l0-6.84c0-1.74 1.13998-2.4 2.93999-2.34001l80.82002 3.72001c2.33997 0.18 3.53998 1.32 3.71997 3.24l0.78003 7.74c6.41999 1.02 15.35999 1.56 16.25998-1.26l-1.38-11.52c-0.78-6.72-5.51999-10.08-12.29999-10.38l-95.94-3.78z"),
            PathPart(0x0D683F, 190.5f, 45.9f, "M0 7.15043l0 9.18c4.98 1.86 14.87999 2.4 16.25998 0.06l0-7.26c0-2.04 1.26002-2.64 3.90002-2.52l79.73999 3.78c2.58002 0.18 3.66001 1.38 3.9 3.42l0.78 7.8c7.02002 1.38001 15.72 1.68 16.02002-1.2l-0.78-6.96c-4.44001 0.96-10.62-0.18-14.16001-3.66-2.28-3.06-6.12002-3.96-10.13998-4.14l-43.50002-2.1c-17.34001-5.04-34.2-4.38-39.66-0.12-3.72002 5.04-9 5.34-12.36 3.72z"),
        )
    }

    /** Kroppen, hjulen och kanten, i SVG:ns ordning. Fraktionen ritas mellan lockets bakre läge och dessa. */
    val bodyParts: List<Part> by lazy {
        listOf(
            PathPart(0x4A4F54, 138.36f, 336.43f, "M17.09999 0c-9.84 4.01999-17.09999 25.61999-17.09999 45.47998 0 22.50003 7.25999 33.84003 16.73999 35.39999 3.84 0.72003 8.10001 0.78003 10.31999 0.54004l-6.11998-81.42001-3.84001 0z"),
            PathPart(0x31373B, 152.7f, 354.31f, "M4.86 0c-3.23999 7.91998-4.86 19.97998-4.86 30.54001 0 19.07999 5.87999 30.95996 12.17999 32.64001l-7.31999-63.18002z"),
            PathPart(0x179E61, 134.64f, 110.53f, "M2.52 37.86l26.64 266.28001c0.71999 6.35999 5.27998 10.56 10.98 11.76001 26.04001 5.64002 70.13998 11.87995 88.20001 12.83997 5.27997 0.30005 9.95999-0.83997 13.62-3.23999l31.07998-21.29999 20.45999-74.52 20.46003-229.68001-57.96003 22.14-155.99998-6.65999 2.52 22.37999z"),
            PathPart(0x0E824C, 269.16f, 110.53f, "M22.86002 23.16l-20.46003 299.28c-0.12 2.52002-1.07999 4.44-2.39999 5.52002 2.75998-0.36004 5.45999-1.20001 7.44-2.46002l31.07999-21.29999 20.45999-74.52 20.46002-229.68001-56.57998 23.16z"),
            PathPart(0x4A4F54, 302.64f, 339.78f, "M23.39999 0.00714c-12.78-0.42001-23.39999 24.96002-23.39999 49.5 0 22.14001 6.72 32.64001 16.07999 34.56003 4.20001 0.89999 9.54001 1.14001 12.90002 0.83996 12-0.89999 21.72-25.01996 21.72-49.67999 0-19.32001-5.81998-30.95999-13.31997-33.65997-4.26004-1.32001-9.54001-1.62003-13.98005-1.56003z"),
            PathPart(0x31373B, 317.76f, 341.65f, "M19.74002 0c-10.62 1.73999-19.74002 25.38001-19.74002 49.13998 0 20.46002 6 32.51999 13.56003 33.72 12.59998-0.11999 22.01999-25.20001 22.01999-49.49999 0-20.57999-6.78-33.17999-15.84-33.35999z"),
            EllipsePart(0x62686C, cx = 338.33f, cy = 382.16f, rx = 9.49f, ry = 25.08f, rotation = 5.6f),
            PathPart(0x107243, 129.06f, 108.49f, "M0 17.52l7.67999 22.14c1.2 3.23999 7.5 3.48 8.04001 0.41999l2.34-13.37999 122.63998 8.22 4.68002 14.64c0.96 2.82001 7.91999 2.64 8.51999-0.06l4.68-16.56 43.14001-15.72 0.9 14.81999c0.30001 3.3 6.30001 2.58 6.89999-1.01999l4.20001-23.16 5.75998-4.62 0.42001-3.24-60.05999 24.84-25.68003 1.91999-134.15997-9.23999z"),
            PathPart(0x0D5E39, 291.78f, 120.49f, "M0.06 12.42l-0.06 7.92 38.82001-15.48 0.05999-4.86-38.82 12.42z"),
            PathPart(0x0D5E39, 341.46f, 112.09f, "M0.36002 3.42001l-0.36002 7.44001 5.88-4.44001 1.01999-6.42001-6.53997 3.42001z"),
        )
    }
}
