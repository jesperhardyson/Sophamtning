package se.hardyson.sophamtning.core.home

import java.time.Instant
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.Deviation
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.api.SchedulePeriod
import se.hardyson.sophamtning.core.capitalizedFirst
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.kommun.CalendarLink
import se.hardyson.sophamtning.core.placedout.PlacedOutLine
import se.hardyson.sophamtning.core.reminders.ReminderTime
import se.hardyson.sophamtning.core.reminders.missedText
import se.hardyson.sophamtning.core.schedule.ScheduleEnding
import se.hardyson.sophamtning.core.schedule.ScheduleLogic
import se.hardyson.sophamtning.core.search.OtherDaysNote
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.trimmedNonEmpty

/**
 * Adressvyns innehåll, räknat från den sparade adressen och schemat och given tid. Som [HomeContent] räknas allt lokalt, och
 * sparade `daysUntil`, `isToday` och `text` används aldrig.
 */
data class AddressDetail(
    val key: AddressKey,
    val title: String,
    /** Adressen och platsen under rubriken, på var sin rad. Rubriken är adressens namn. */
    val lines: HomeContent.AddressLines,
    /** Namnet, adressen och platsen, för Hela schemat, där rubriken inte är adressens namn. */
    val namedLines: HomeContent.AddressLines,
    val mode: Mode,
    val notice: Notice?,
    val next: HomeContent.Pickup?,
    /** Varning för nästa hämtning, som visas i en egen ruta. */
    val nextWarning: String?,
    val bins: List<Bin>,
    /** Hela det kommande schemat, en rad per datum. */
    val rows: List<Row>,
    /** "Schemat gäller till 10 januari 2027." med källans orsak. `null` för live-källor och när perioden har passerat. */
    val schedulePeriod: SchedulePeriodLine?,
    /**
     * Rutan när schemat tar slut inom 14 dagar. Bara med kommande hämtningar: utan dem säger meddelandet nedan hur långt
     * schemat gäller. `null` för live-källor och efter att perioden har passerat.
     */
    val scheduleEnding: ScheduleEnding?,
    /** Rutan "Vissa gator har en annan hämtdag" för ett område med avvikande gator. `null` när raderna saknas. */
    val otherDays: OtherDaysNote?,
    /** Meddelandet i läget `NoUpcoming`. Har källans period passerat säger det att nästa period inte är publicerad än. */
    val noUpcomingMessage: NoUpcomingMessage,
    /** "Hämtat i dag 09:12", längst ned i kortet för källan, eller `null` när schemat aldrig hämtats. */
    val fetchedText: String?,
    /** Kommunens eller bolagets sida för adressen (`links.web`). */
    val webLink: String?,
    /**
     * Google Kalenders länk för att prenumerera på adressens schema ([CalendarLink.googleCalendar]), eller `null` utan
     * `links.ics`. På iOS är det `webcal://`-adressen.
     */
    val calendarLink: String?,
    /** Raden under reglaget "Påminn mig". */
    val reminderText: String,
    val liveActivityText: String,
    val isPrimary: Boolean,
    /**
     * Delen Påminnelser visas när det finns hämtningar. Utan hämtningar visas den bara när en påminnelse redan är på (notisen
     * för adressen, eller Live Update för huvudadressen), så att den går att stänga av.
     */
    val showsReminders: Boolean,
    /** "Tömning i morgon. Påminnelsen för i kväll har redan passerat." när notiser är på och tiden redan passerat. */
    val missedReminder: String?,
    /** Raden för Ställ ut kärlen och Utställt, för varje läge. `null` när det inte finns något att visa. */
    val placedOut: PlacedOutLine?,
) {
    enum class Mode {
        /** Schemat har inte hämtats än. */
        Loading,

        /** Det finns kommande hämtningar. */
        Schedule,

        /** Schemat finns men har inga hämtningar från och med i dag. */
        NoUpcoming,

        /** Inget sparat schema och hämtningen misslyckades. */
        Unavailable,
    }

    /** Meddelandet högst upp, vid fel. */
    sealed interface Notice {
        /** Ett sparat schema visas fast det senaste försöket misslyckades. [fetched] är texten "Hämtat i går 18:40." */
        data class SavedShown(val fetched: String?) : Notice

        /** 502, nätfel eller timeout utan sparat schema. Det betyder inte att adressen saknas. */
        data object SourceUnavailable : Notice

        /** 404: källan känner inte längre igen adressen. Adressen behålls. */
        data object NotFound : Notice

        /** 400: källan godtog inte förfrågan. Det är varken ett nätfel eller en adress som saknas. */
        data object BadRequest : Notice

        /** Schemat hämtades men gick inte att spara på telefonen. */
        data object StorageFailed : Notice
    }

    /** Nästa hämtning per fraktion, med datum och dagar kvar. */
    data class Bin(
        val id: String,
        val info: FractionInfo,
        /** "Mån 9 nov", eller "ca tors 12 nov" när datumet är beräknat. */
        val dateText: String,
        /** "om 3 dagar", "i övermorgon", "i morgon" eller "i dag". */
        val daysText: String,
    ) {
        /** Kortet för kärlet läses som en enhet: "Restavfall, om 3 dagar, Mån 9 nov". */
        val accessibilityLabel: String get() = listOf(info.name, daysText, dateText).joinToString(", ")
    }

    /** Raden om hur långt schemat gäller, nära de kommande tömningarna. */
    data class SchedulePeriodLine(
        /** "Schemat gäller till 10 januari 2027." */
        val text: String,
        /** Källans förklaring i mindre text, som källan skrev den, eller `null`. */
        val reason: String?,
    )

    /** Meddelandet när schemat inte har några hämtningar från och med i dag. */
    data class NoUpcomingMessage(val title: String, val message: String)

    /** En dag i schemat. Flera fraktioner samma dag visas som chips. */
    data class Row(
        val date: DayDate,
        val dateText: String,
        /** Datumbrickan: "11" och "NOV". */
        val dayNumber: String,
        val month: String,
        /** "om 5 dagar", "i övermorgon", "i morgon" eller "i dag", med "ca" först när datumet är beräknat. Räknat från i dag. */
        val daysText: String,
        /** Kort form för raden: "om 5 d", "i morgon" eller "i dag", med "ca" först när datumet är beräknat. */
        val shortDaysText: String,
        val fractions: List<HomeContent.FractionItem>,
        /** "Flyttad från mån 16 nov", eller källans orsak när ursprungsdatumet saknas. */
        val deviation: String?,
        val warning: String?,
    ) {
        val id: DayDate get() = date

        val accessibilityLabel: String
            get() = (listOf("$dateText, $daysText", fractions.joinToString(", ") { it.info.name }) + listOfNotNull(deviation, warning)).joinToString(". ")
    }

    /**
     * De närmaste datumen under "Kommande", efter nästa tömning. Nästa tömning står redan i kortet ovanför, med sin varning
     * ([nextWarning]) och avvikelse ([nextDeviation]). Tom när det inte finns fler datum.
     */
    val upcoming: List<Row> get() = rows.filter { it.date != next?.date }.take(UPCOMING_COUNT)

    /** Länken "Hela schemat" visas bara när det finns fler datum än de som redan står på sidan. */
    val hasFullSchedule: Boolean get() = rows.size > UPCOMING_COUNT + (if (next == null) 0 else 1)

    /** "Flyttad från sön 8 nov" för nästa tömning, som står i kortet eftersom raden inte finns under "Kommande". */
    val nextDeviation: String? get() = rows.firstOrNull { it.date == next?.date }?.deviation

    companion object {
        /** Hur många datum som visas under "Kommande". */
        const val UPCOMING_COUNT = 3

        /** Raden under reglagen när adressen inte har några kommande hämtningar. */
        internal const val NOTHING_TO_REMIND_TEXT = "Inga hämtningar att påminna om just nu."

        /**
         * [placedOutTimes] är när kärlen ställdes ut, för raden Utställt. Hushållet finns inte på Android, så raden gäller
         * bara de egna utställda i [ownPlacedOut].
         */
        fun make(
            address: SavedAddress,
            schedule: CachedSchedule?,
            settings: ReminderSettings,
            sourceName: String?,
            now: Instant,
            remindersOn: Boolean = false,
            reserveAt: Instant? = null,
            ownPlacedOut: Set<PlacedOut> = emptySet(),
            placedOutTimes: Map<PlacedOut, Instant> = emptyMap(),
        ): AddressDetail {
            val today = StockholmClock.today(now)
            // Live Update gäller bara huvudadressen, så den ger knappen Ställ ut kärlen bara där.
            val entrySettings = settings.copy(liveActivityOn = settings.liveActivityOn && address.isPrimary)
            val entry = HomeContent.make(
                listOf(address.copy(isPrimary = true)), schedule?.let { mapOf(address.key to it) } ?: emptyMap(), entrySettings, now,
                ownPlacedOut = ownPlacedOut, placedOutTimes = placedOutTimes,
            ).primary!!
            val response = schedule?.response

            val status = entry.status
            val mode = when (status) {
                HomeContent.Status.Loading -> Mode.Loading
                HomeContent.Status.NoUpcoming -> Mode.NoUpcoming
                is HomeContent.Status.Failed -> Mode.Unavailable
                is HomeContent.Status.Upcoming -> Mode.Schedule
            }
            val next = (status as? HomeContent.Status.Upcoming)?.pickup

            val fetched = fetchedText(schedule?.fetchedAt, sourceName, now)
            val notice = when (schedule?.lastError) {
                null -> null
                ApiError.NotFound -> Notice.NotFound
                ApiError.BadRequest -> Notice.BadRequest
                // Ett misslyckat sparande markeras av appen med `Unexpected(0)`.
                ApiError.Unexpected(0) -> Notice.StorageFailed
                else -> if (response == null) Notice.SourceUnavailable else Notice.SavedShown(fetched)
            }

            val liveActivityOn = settings.liveActivityOn && address.isPrimary
            val showsReminders = mode == Mode.Schedule || (mode == Mode.NoUpcoming && (address.notificationsOn || liveActivityOn))
            // Utan hämtningar står samma rad under båda reglagen, eftersom det inte finns någon tid att visa.
            val nothingToRemind = if (mode == Mode.NoUpcoming) NOTHING_TO_REMIND_TEXT else null

            val scheduleRows = response?.let { rows(it, today) } ?: emptyList()
            val bins = response?.let { r ->
                ScheduleLogic.nextByFraction(r.events, today).map { pickup ->
                    Bin(
                        id = pickup.fraction,
                        info = ScheduleLogic.displayInfo(pickup.fraction, r.fractions),
                        dateText = dateText(pickup.date, pickup.estimated),
                        daysText = SwedishFormat.relative(pickup.daysUntil),
                    )
                }
            } ?: emptyList()

            return AddressDetail(
                key = address.key,
                title = address.displayName,
                lines = entry.lines,
                namedLines = HomeContent.namedLines(address),
                mode = mode,
                notice = notice,
                next = next,
                nextWarning = scheduleRows.firstOrNull { it.date == next?.date }?.warning,
                bins = bins,
                rows = scheduleRows,
                schedulePeriod = periodLine(response?.schedule, mode, today),
                scheduleEnding = if (mode == Mode.Schedule) ScheduleEnding.make(response?.schedule, today) else null,
                otherDays = OtherDaysNote.make(response?.address?.area),
                noUpcomingMessage = noUpcomingMessage(response?.schedule, today, afterError = notice != null, sourceName = sourceName),
                fetchedText = fetchedTime(schedule?.fetchedAt, now),
                webLink = response?.links?.web,
                calendarLink = response?.links?.ics?.let(CalendarLink::googleCalendar),
                reminderText = nothingToRemind
                    ?: rowText(response?.events ?: emptyList(), settings, now, reserveAt, HomeContent.skippedDays(address.key, ownPlacedOut)),
                liveActivityText = nothingToRemind ?: liveActivityText(settings),
                isPrimary = address.isPrimary,
                showsReminders = showsReminders,
                missedReminder = if (remindersOn) missedReminder(response?.events ?: emptyList(), settings, now) else null,
                placedOut = entry.placedOut,
            )
        }

        /**
         * Raden visas när källan anger en period som inte har passerat och det finns kommande hämtningar. Utan kommande
         * hämtningar står perioden i meddelandet i stället, så att texterna inte motsäger varandra. Live-källor har ingen period.
         */
        internal fun periodLine(period: SchedulePeriod?, mode: Mode, today: DayDate): SchedulePeriodLine? {
            if (period == null || period.until < today || mode != Mode.Schedule) return null
            return SchedulePeriodLine("Schemat gäller till ${SwedishFormat.dayMonthYear(period.until)}.", period.reason?.trimmedNonEmpty())
        }

        /**
         * Utan kommande hämtningar. Gäller perioden fortfarande finns inga fler hämtningar i det publicerade schemat. Har den
         * passerat har källan inte publicerat nästa period än. Källans orsak står med. Det säger aldrig att adressen saknas.
         * Visas ett sparat schema efter ett fel ([afterError]) står bara vad det senast hämtade schemat säger. En live-källa
         * har ingen period, och ett tomt svar från den betyder oftast att adressen saknar abonnemang, så texten hänvisar till källan.
         */
        internal fun noUpcomingMessage(period: SchedulePeriod?, today: DayDate, afterError: Boolean = false, sourceName: String? = null): NoUpcomingMessage {
            val title = "Inga kommande hämtningar"
            if (period == null) {
                val message = if (afterError) {
                    "Det senast hämtade schemat har inga fler hämtningar."
                } else {
                    "Källan visar inga hämtningar för adressen just nu. Stämmer det inte, kontakta ${sourceName?.trimmedNonEmpty() ?: "den som ansvarar för hämtningen"}."
                }
                return NoUpcomingMessage(title, message)
            }
            val until = SwedishFormat.dayMonthYear(period.until)
            val base = when {
                period.until >= today -> "Inga fler hämtningar i schemat, som gäller till $until."
                afterError -> "Det senast hämtade schemat gällde till $until."
                else -> "Schemat gällde till $until, och källan har inte publicerat nästa period än."
            }
            return NoUpcomingMessage(title, listOfNotNull(base, period.reason?.trimmedNonEmpty()).joinToString(" "))
        }

        /** Klockslaget för ett ögonblick i svensk tid, "18:45". */
        internal fun clock(date: Instant): String {
            val time = date.atZone(StockholmClock.zone)
            return SwedishFormat.clock(time.hour * 60 + time.minute)
        }

        /**
         * "Söndag kl. 18:45 inför måndagens tömning, om aktiviteten inte syns." eller "Måndag kl. 06:45, samma dag som
         * tömningen, om aktiviteten inte syns." När det är reserven som gäller. Tömningsdagen räknas från reservens klockslag,
         * inte från det som är valt nu: en notis från det andra valet kan stå kvar efter ett byte.
         */
        internal fun reserveText(reserveAt: Instant): String {
            val day = StockholmClock.today(reserveAt)
            val pickup = ReminderTime.pickupDay(reserveAt)
            val timing = if (pickup == day) ReminderTiming.SameMorning else ReminderTiming.EveningBefore
            return "${whenText(day, pickup, clock(reserveAt), timing)}, om aktiviteten inte syns."
        }

        /** "Söndag kl. 18:00 inför måndagens tömning" eller "Måndag kl. 06:00, samma dag som tömningen". */
        private fun whenText(day: DayDate, pickup: DayDate, time: String, timing: ReminderTiming): String {
            val start = "${SwedishFormat.weekdayName(day).capitalizedFirst()} kl. $time"
            return when (timing) {
                ReminderTiming.EveningBefore -> "$start inför ${SwedishFormat.weekdayName(pickup)}ens tömning"
                ReminderTiming.SameMorning -> "$start, samma dag som tömningen"
            }
        }

        /** Det som står bakom knappen Mer om Live Update, en mening per rad. */
        fun liveActivityDetails(): List<String> = listOf(
            "Starten aviseras med ljud.",
            "Den försvinner senast efter 12 timmar.",
            "Öppna appen ibland, så att nästa tömning kommer med.",
            "Med notis vid samma tid får du en reserv om du inte bekräftar.",
        )

        /**
         * Hela tiden Live Updaten syns, högst 12 timmar från starten: "Visas på låsskärmen kl. 21:00 dagen före till 09:00."
         * eller "Visas på låsskärmen kl. 06:00–18:00 samma dag."
         */
        fun liveActivityText(settings: ReminderSettings): String {
            val start = settings.liveActivityStartMinutes
            val from = SwedishFormat.clock(start)
            val to = SwedishFormat.clock((start + 12 * 60) % (24 * 60))
            return when (settings.liveActivityTiming) {
                ReminderTiming.EveningBefore -> "Visas på låsskärmen kl. $from dagen före till $to."
                ReminderTiming.SameMorning -> "Visas på låsskärmen kl. $from–$to samma dag."
            }
        }

        /**
         * Påminnelsetiden i dag har redan passerat för tömningen den gäller, i morgon med kvällen före och i dag med samma
         * morgon. Till exempel efter att tiden ändrats eller notisen slagits på sent.
         */
        fun missedReminder(events: List<PickupEvent>, settings: ReminderSettings, now: Instant): String? {
            val today = StockholmClock.today(now)
            // Det senast påslagna valet avgör: kvällens tid kan ha passerat utan att något är missat, när morgonen kommer.
            val timing = settings.latestTiming
            val pickup = ReminderTime.pickupDay(today, timing)
            if (events.none { it.date == pickup && it.fractions.isNotEmpty() }) return null
            if (ReminderTime.date(pickup, timing, settings) > now) return null
            return timing.missedText
        }

        /**
         * Raden under reglaget: reservnotisen när den är nästa påminnelse, annars nästa påminnelse. Reserven ersätter notisen
         * för Live Updatens val, så den gäller när det är nästa, när den kommer före nästa eller när ingen annan finns.
         */
        internal fun rowText(events: List<PickupEvent>, settings: ReminderSettings, now: Instant, reserveAt: Instant?, skipping: Set<DayDate>): String {
            if (reserveAt != null) {
                val next = ReminderTime.next(events, settings, now, skipping)
                if (next == null || next.timing == settings.liveActivityTiming || reserveAt <= next.date) return reserveText(reserveAt)
            }
            return reminderText(events, settings, now, skipping)
        }

        /**
         * "Söndag kl. 18:00 inför måndagens tömning." eller "Måndag kl. 06:00, samma dag som tömningen." Det är nästa
         * påminnelse av de påslagna valen. Finns ingen kommande tömning står texten för varje påslaget val.
         */
        internal fun reminderText(events: List<PickupEvent>, settings: ReminderSettings, now: Instant, skipping: Set<DayDate> = emptySet()): String {
            ReminderTime.next(events, settings, now, skipping)?.let { next ->
                return "${whenText(StockholmClock.today(next.date), next.pickup, clock(next.date), next.timing)}."
            }
            return settings.enabledTimings.joinToString(" ") { timing ->
                val time = SwedishFormat.clock(settings.minutes(timing))
                when (timing) {
                    ReminderTiming.EveningBefore -> "Kvällen före varje tömning kl. $time."
                    ReminderTiming.SameMorning -> "Samma morgon som varje tömning kl. $time."
                }
            }
        }

        /** "Mån 9 nov", eller "ca tors 12 nov" när datumet är beräknat. */
        internal fun dateText(day: DayDate, estimated: Boolean): String {
            val text = SwedishFormat.shortDate(day)
            return if (estimated) "ca " + text.lowercase() else text
        }

        /** "Hämtat i dag 09:12 från Avesta Vatten och Avfall.", i rutan när ett sparat schema visas efter ett fel. */
        internal fun fetchedText(fetchedAt: Instant?, sourceName: String?, now: Instant): String? {
            val time = fetchedTime(fetchedAt, now) ?: return null
            return "$time${sourceName?.let { " från $it" } ?: ""}."
        }

        /** "Hämtat i dag 09:12", "Hämtat i går 18:40" eller "Hämtat 1 nov 07:00", i svensk tid. */
        internal fun fetchedTime(fetchedAt: Instant?, now: Instant): String? {
            fetchedAt ?: return null
            val day = StockholmClock.today(fetchedAt)
            val whenText = when (day.daysUntil(StockholmClock.today(now))) {
                0 -> "i dag"
                1 -> "i går"
                else -> SwedishFormat.dayMonth(day)
            }
            return "Hämtat $whenText ${clock(fetchedAt)}"
        }

        /** Kommande dagar, en rad per datum. Två händelser samma dag slås ihop, så att ingen fraktion eller varning tappas. */
        private fun rows(response: AddressResponse, today: DayDate): List<Row> {
            class Merged(val fractions: MutableList<String>, var estimated: Boolean, var deviation: Deviation?, val warnings: MutableList<String>)
            val merged = LinkedHashMap<DayDate, Merged>()
            for (event in ScheduleLogic.upcoming(response.events, today)) {
                val warning = event.warning?.trimmedNonEmpty()
                val existing = merged[event.date]
                if (existing != null) {
                    for (id in event.fractions) if (id !in existing.fractions) existing.fractions += id
                    existing.estimated = existing.estimated || event.estimated
                    existing.deviation = existing.deviation ?: event.deviation
                    if (warning != null && warning !in existing.warnings) existing.warnings += warning
                } else {
                    merged[event.date] = Merged(event.fractions.distinct().toMutableList(), event.estimated, event.deviation, listOfNotNull(warning).toMutableList())
                }
            }
            return merged.mapNotNull { (date, entry) ->
                if (entry.fractions.isEmpty()) return@mapNotNull null
                val days = today.daysUntil(date)
                Row(
                    date = date,
                    dateText = dateText(date, entry.estimated),
                    dayNumber = SwedishFormat.dayNumber(date),
                    month = SwedishFormat.monthUppercased(date),
                    daysText = SwedishFormat.estimated(SwedishFormat.relative(days), entry.estimated),
                    shortDaysText = SwedishFormat.estimated(shortRelative(days), entry.estimated),
                    fractions = entry.fractions.map { HomeContent.FractionItem(it, ScheduleLogic.displayInfo(it, response.fractions)) },
                    deviation = entry.deviation?.let(::deviationText),
                    warning = if (entry.warnings.isEmpty()) null else entry.warnings.joinToString(" "),
                )
            }
        }

        /** "om 5 d", "i morgon" eller "i dag". Talet och d hålls ihop med hårt mellanslag, så att de aldrig hamnar på olika rader. */
        private fun shortRelative(days: Int) = if (days > 1) "om $days\u00A0d" else SwedishFormat.relative(days)

        private fun deviationText(deviation: Deviation): String? {
            deviation.originalDate?.let { return "Flyttad från " + SwedishFormat.shortDate(it).lowercase() }
            return deviation.reason.trimmedNonEmpty()
        }
    }
}
