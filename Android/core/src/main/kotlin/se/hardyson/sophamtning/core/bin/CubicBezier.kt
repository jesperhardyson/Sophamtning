package se.hardyson.sophamtning.core.bin

import kotlin.math.abs

/** CSS `cubic-bezier(x1, y1, x2, y2)`: ger framsteget för en andel av tiden. Som `CubicBezier` på iOS. */
internal data class CubicBezier(val x1: Double, val y1: Double, val x2: Double, val y2: Double) {
    fun value(x: Double): Double {
        if (x <= 0) return 0.0
        if (x >= 1) return 1.0
        if (x1 == y1 && x2 == y2) return x
        // Hitta parametern t där bezierns x är `x` (Newton, med halvering som reserv), och ge y.
        var t = x
        for (i in 0 until 8) {
            val error = sample(t, x1, x2) - x
            if (abs(error) < 1e-7) return sample(t, y1, y2)
            val slope = derivative(t, x1, x2)
            if (abs(slope) < 1e-6) break
            t -= error / slope
        }
        var low = 0.0
        var high = 1.0
        t = x
        for (i in 0 until 40) {
            val current = sample(t, x1, x2)
            if (abs(current - x) < 1e-7) break
            if (current < x) low = t else high = t
            t = (low + high) / 2
        }
        return sample(t, y1, y2)
    }

    private fun sample(t: Double, a: Double, b: Double): Double {
        val s = 1 - t
        return 3 * s * s * t * a + 3 * s * t * t * b + t * t * t
    }

    private fun derivative(t: Double, a: Double, b: Double): Double {
        val s = 1 - t
        return 3 * s * s * a + 6 * s * t * (b - a) + 3 * t * t * (1 - b)
    }

    companion object {
        val LINEAR = CubicBezier(0.0, 0.0, 1.0, 1.0)

        /** CSS `ease-in-out`. */
        val EASE_IN_OUT = CubicBezier(0.42, 0.0, 0.58, 1.0)

        /** CSS `ease-out`. */
        val EASE_OUT = CubicBezier(0.0, 0.0, 0.58, 1.0)
    }
}

/** Värdet mellan [from] och [to] när [p] går från [p0] till [p1] längs [curve], med exakta ändpunkter. */
internal fun interpolate(from: Double, to: Double, p: Double, p0: Double, p1: Double, curve: CubicBezier): Double {
    val t = curve.value((p - p0) / (p1 - p0))
    if (t <= 0) return from
    if (t >= 1) return to
    return from + (to - from) * t
}
