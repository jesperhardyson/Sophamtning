package se.hardyson.sophamtning.core.dates

import java.util.Locale

/** Svenska datumtexter. Namnen är fasta tabeller så att utseendet inte beror på telefonens språkdata. */
object SwedishFormat {
    // Index 0 är måndag, som java.time.DayOfWeek.MONDAY.value - 1.
    private val weekdays = listOf("måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag", "söndag")
    private val shortWeekdays = listOf("mån", "tis", "ons", "tors", "fre", "lör", "sön")
    private val months = listOf(
        "januari", "februari", "mars", "april", "maj", "juni",
        "juli", "augusti", "september", "oktober", "november", "december",
    )
    private val shortMonths = listOf("jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec")

    private fun weekdayIndex(day: DayDate) = day.toLocalDate().dayOfWeek.value - 1

    private fun String.capitalizedFirst() = replaceFirstChar { it.uppercaseChar() }

    /** "måndag 9 november", eller "Måndag 9 november" med versal. */
    fun longDate(day: DayDate, capitalized: Boolean): String {
        val text = "${weekdays[weekdayIndex(day)]} ${day.day} ${months[day.month - 1]}"
        return if (capitalized) text.capitalizedFirst() else text
    }

    /** "Tisdag 27 oktober 2026". */
    fun longDateWithYear(day: DayDate) = "${longDate(day, capitalized = true)} ${day.year}"

    /** "10 januari 2027", utan veckodag. */
    fun dayMonthYear(day: DayDate) = "${day.day} ${months[day.month - 1]} ${day.year}"

    /** Månaden helt utskriven, "januari". */
    fun monthName(day: DayDate) = months[day.month - 1]

    /** "13 okt", utan veckodag. */
    fun dayMonth(day: DayDate) = "${day.day} ${shortMonths[day.month - 1]}"

    /** Veckodagen helt utskriven, "måndag". */
    fun weekdayName(day: DayDate) = weekdays[weekdayIndex(day)]

    /** Dagens nummer i månaden, "9". */
    fun dayNumber(day: DayDate) = day.day.toString()

    /** Månaden kort och i versaler, "NOV". */
    fun monthUppercased(day: DayDate) = shortMonths[day.month - 1].uppercase()

    /** "Mån 9 nov". */
    fun shortDate(day: DayDate) =
        "${shortWeekdays[weekdayIndex(day)].capitalizedFirst()} ${day.day} ${shortMonths[day.month - 1]}"

    /** "i dag", "i morgon", "i övermorgon" och från tre dagar "om 3 dagar". */
    fun relative(days: Int) = when (days) {
        0 -> "i dag"
        1 -> "i morgon"
        2 -> "i övermorgon"
        else -> "om $days dagar"
    }

    /** Sätter "ca" framför en text när tiden är uppskattad. */
    fun estimated(text: String, isEstimated: Boolean) = if (isEstimated) "ca $text" else text

    /** Klockslaget för minuter efter midnatt, "18:00". */
    fun clock(minutes: Int) = String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)
}
