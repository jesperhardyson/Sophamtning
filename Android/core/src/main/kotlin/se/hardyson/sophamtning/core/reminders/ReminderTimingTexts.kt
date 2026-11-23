package se.hardyson.sophamtning.core.reminders

import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.storage.ReminderTiming

// Texterna som följer valet mellan kvällen före och samma morgon, som ReminderTimingTexts.swift.

/** "dagen före" eller "samma morgon", inne i en mening. Inte "kvällen före", eftersom tiderna börjar 15:00. */
internal val ReminderTiming.phrase: String
    get() = when (this) {
        ReminderTiming.EveningBefore -> "dagen före"
        ReminderTiming.SameMorning -> "samma morgon"
    }

/** Valets namn i listan och i inställningens värde. */
val ReminderTiming.title: String
    get() = when (this) {
        ReminderTiming.EveningBefore -> "Kvällen före"
        ReminderTiming.SameMorning -> "Samma morgon"
    }

/** Texten under delen för valet i inställningarna, med den valda tiden: "Dagen före tömningen kl. 18:00." */
fun ReminderTiming.sectionFooter(minutes: Int): String {
    val time = SwedishFormat.clock(minutes)
    return when (this) {
        ReminderTiming.EveningBefore -> "Dagen före tömningen kl. $time."
        ReminderTiming.SameMorning -> "Samma dag som tömningen kl. $time. Minst en påminnelse är på. Notiser slår du av under Adresser."
    }
}

/**
 * Texten under listan med tider för Live Update. Android sätter ingen gräns som iOS, så det är appen som tar bort den
 * efter 12 timmar. Utan hushåll försvinner den bara med Klart eller när den sveps bort.
 */
val ReminderTiming.Companion.liveActivityTimesFooter: String
    get() = "Appen visar en Live Update i högst 12 timmar. Den försvinner tidigare när du trycker Klart eller sveper bort den."

/** Texten under listan med tider: vilka tider som går att välja. */
val ReminderTiming.timesFooter: String
    get() = "Välj en tid mellan ${SwedishFormat.clock(range.first)} och ${SwedishFormat.clock(range.last)}."

/** När tiden för tömningen närmast framför redan har passerat. */
internal val ReminderTiming.missedText: String
    get() = when (this) {
        ReminderTiming.EveningBefore -> "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
        ReminderTiming.SameMorning -> "Tömning i dag. Påminnelsen för i morse har redan passerat."
    }
