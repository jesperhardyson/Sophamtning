package se.hardyson.sophamtning.core.home

import java.time.Duration
import java.time.Instant
import se.hardyson.sophamtning.core.api.ApiError
import se.hardyson.sophamtning.core.api.FractionInfo
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.capitalizedFirst
import se.hardyson.sophamtning.core.dates.DayDate
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.dates.SwedishFormat
import se.hardyson.sophamtning.core.kommun.localityAndKommun
import se.hardyson.sophamtning.core.placedout.PlacedOutLine
import se.hardyson.sophamtning.core.reminders.ExistingActivity
import se.hardyson.sophamtning.core.reminders.ReminderTime
import se.hardyson.sophamtning.core.schedule.ScheduleEnding
import se.hardyson.sophamtning.core.schedule.ScheduleLogic
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.ReminderSettings
import se.hardyson.sophamtning.core.storage.SavedAddress

private const val NBSP = " "
private val spaceBeforeNumber = Regex(" (?=\\d)")

/**
 * Hemskärmens innehåll, räknat från sparade adresser och scheman och given tid. Allt räknas lokalt: dagar, datum och
 * påminnelsetext kommer aldrig från sparade `next`-fält.
 */
data class HomeContent(val primary: Entry?, val others: List<Entry>) {
    data class FractionItem(val id: String, val info: FractionInfo)

    /** Nästa hämtning för en adress. */
    data class Pickup(
        val date: DayDate,
        val daysUntil: Int,
        val estimated: Boolean,
        val fractions: List<FractionItem>,
        /** "Om 3 dagar", "I övermorgon", "I morgon" eller "I dag", med "Ca" först när datumet är uppskattat. */
        val headline: String,
        /** "Måndag 9 november", med "Ca" först när datumet är uppskattat. */
        val longDate: String,
    ) {
        /** Datum, dagar kvar och kärlen i ett: "Nästa tömning. Om 3 dagar. Måndag 9 november. Restavfall, Matavfall". */
        val accessibilityLabel: String
            get() = listOf("Nästa tömning", headline, longDate, fractions.joinToString(", ") { it.info.name }).joinToString(". ")
    }

    sealed interface Status {
        data class Upcoming(val pickup: Pickup) : Status

        /** Schemat finns men har inga hämtningar från och med i dag. */
        data object NoUpcoming : Status

        /** Schemat har inte hämtats än. */
        data object Loading : Status

        /**
         * Schemat saknas och det senaste försöket misslyckades. Bara `NotFound` betyder att adressen inte finns längre, alla
         * andra fel är tekniska.
         */
        data class Failed(val error: ApiError) : Status
    }

    /** Påminnelsen på en rad under "Fler adresser". Notis av ger ingen rad alls. */
    sealed interface RowReminder {
        val text: String

        /** Notis på och tillåten: "Påminnelse tisdag kl. 18:45", eller "Påminnelser på" utan senare tömning. */
        data class Scheduled(override val text: String) : RowReminder

        /** Notis på för adressen, men notiser är inte tillåtna för appen. */
        data object Denied : RowReminder {
            override val text = "Notiser är avstängda för appen"
        }

        /** Kvällens påminnelse har redan passerat, med samma text som huvudkortet. */
        data class Missed(override val text: String) : RowReminder
    }

    /** Påminnelsen för huvudadressen. Kortet visar [line] i sin fot, eller rutan om nekade notiser. */
    data class PrimaryReminder(
        /** Påminnelsen är på och tillåten. */
        val isOn: Boolean,
        /** Systemet har nekat notiser. Reglaget är av, och en knapp öppnar appens notisinställningar. */
        val isDenied: Boolean,
        /** "Påminn mig", eller "Notiser är avstängda för appen". */
        val title: String,
        /**
         * Raden under: när påminnelsen kommer ("Söndag kl. 18:00"), eller en väntande Live Update ("Live Update söndag
         * kl. 17:30", och "Notis och Live Update söndag kl. 17:30" när notisen också är på).
         */
        val detail: String?,
        /** Raden i huvudkortets fot: "Påminnelse söndag kl. 18:00", "Live Update söndag kl. 17:30". `null` när påminnelsen är av. */
        val line: String? = null,
        /** Påminnelsen är på för adressen men systemet nekar notiser. Kortet visar då en ruta med en knapp till inställningarna. */
        val showsDeniedNotice: Boolean = false,
    ) {
        companion object {
            /**
             * Byggs av huvudkortets text för påminnelsen. Inbjudan blir rubriken, och "Påminnelse söndag kl. 18:00" blir
             * "Söndag kl. 18:00" under den.
             */
            internal fun fromText(text: String, isOn: Boolean, isDenied: Boolean, isWanted: Boolean): PrimaryReminder {
                // Inbjudan betyder att varken notis eller Live Update är på.
                val invitation = text == reminderTitle()
                val detail = when {
                    // Inbjudan är redan rubriken, och "Påminnelser på" säger bara det reglaget redan visar.
                    invitation || text == "Påminnelser på" -> null
                    text.startsWith(REMINDER_PREFIX) -> text.removePrefix(REMINDER_PREFIX).capitalizedFirst()
                    else -> text
                }
                return PrimaryReminder(
                    isOn = isOn,
                    isDenied = isDenied,
                    title = if (isDenied) RowReminder.Denied.text else reminderTitle(),
                    detail = detail,
                    line = if (invitation) null else text,
                    showsDeniedNotice = isDenied && isWanted,
                )
            }

            private const val REMINDER_PREFIX = "Påminnelse "
        }
    }

    /**
     * Adressen och platsen på var sin rad: "Storgatan 12" och "Krylbo · Avesta kommun". Där adressens namn inte står i
     * rubriken, som i Hela schemat, står namnet på en egen rad först.
     */
    data class AddressLines(
        /** Adressens namn, "Hemma". Tomt där namnet redan står i rubriken eller på kortet. */
        val name: String = "",
        /** Gatan med nummer, eller områdets namn. Tom när adressen saknar gata eller när gatan bara upprepar namnet. */
        val address: String,
        /** Orten och kommunen. Kommunen döljs när den bara upprepar orten. */
        val place: String,
    ) {
        /** Gatan och platsen på en rad, med komma emellan: "Storgatan 12, Krylbo · Avesta kommun". Namnet står inte med. */
        val singleLine: String get() = listOf(address, place).filter { it.isNotEmpty() }.joinToString(", ")

        /** "Hemma, Storgatan 12, Krylbo, Avesta kommun", utan mittpunkt och med vanliga mellanslag. */
        val accessibilityLabel: String
            get() = listOf(name, address, place.replace("$NBSP· ", ", "))
                .filter { it.isNotEmpty() }
                .joinToString(", ")
                .replace(NBSP, " ")
    }

    data class Entry(
        val key: AddressKey,
        val title: String,
        /** Adressen och platsen på var sin rad. */
        val lines: AddressLines,
        val status: Status,
        /** Senaste försöket att uppdatera misslyckades, men ett äldre schema visas. */
        val refreshFailed: Boolean,
        /** Huvudkortets reglage för påminnelsen. `null` när det inte finns någon kommande hämtning, och alltid på raderna. */
        val reminder: PrimaryReminder?,
        /**
         * Radens påminnelse under "Fler adresser". Bara när notis är på för adressen och en hämtning kommer, och utan Live
         * Update, som bara gäller huvudadressen. Alltid `null` på huvudkortet.
         */
        val rowReminder: RowReminder?,
        /** "Schemat slutar 10 jan" när schemat tar slut inom 14 dagar. Bara med kommande hämtningar, och aldrig för live-källor. */
        val scheduleEnding: ScheduleEnding?,
        /** Raden under adressen: "Ons 18 nov · om 12 dagar" eller en statustext. */
        val summary: String,
        /** Raden för Ställ ut kärlen och Utställt, för varje status. `null` när det inte finns något att visa. */
        val placedOut: PlacedOutLine?,
    ) {
        /** Hur raden under adressen visas: som ett datum, som en lugn statustext eller som en varning. */
        enum class SummaryTone { Date, Neutral, Warning }

        /** "Inga kommande hämtningar" och "Hämtar schema…" är neutrala. Ett misslyckat försök utan sparat schema är en varning. */
        val summaryTone: SummaryTone
            get() = when (status) {
                is Status.Upcoming -> SummaryTone.Date
                Status.NoUpcoming, Status.Loading -> SummaryTone.Neutral
                is Status.Failed -> SummaryTone.Warning
            }

        val id: AddressKey get() = key

        /** Raden under datumet på huvudkortet när nästa tömning är i dag. `null` alla andra dagar. */
        val dayNote: String?
            get() {
                val pickup = (status as? Status.Upcoming)?.pickup ?: return null
                if (pickup.daysUntil != 0) return null
                return if (pickup.estimated) "Kärlen ska stå ute i dag, om tömningen kommer som beräknat." else "Kärlen ska stå ute i dag."
            }

        /** Alla fraktioner som text, så att TalkBack kan läsa dem även när raden bara visar ikoner. */
        val accessibilityLabel: String
            get() {
                val parts = mutableListOf(title, lines.accessibilityLabel, summary)
                if (refreshFailed) parts += "Kunde inte uppdateras, visar senast hämtade schema"
                (status as? Status.Upcoming)?.let { parts += it.pickup.fractions.joinToString(", ") { item -> item.info.name } }
                scheduleEnding?.let { parts += it.spokenText }
                // De hårda mellanslagen gäller bara radbrytningen. TalkBack får vanliga mellanslag.
                return parts.joinToString(", ").replace(NBSP, " ")
            }
    }

    companion object {
        /** Reglagets namn på huvudkortet, i adressvyn och i menyn. */
        fun reminderTitle() = "Påminn mig"

        /** TalkBacks åtgärd för samma reglage, på huvudkortet och raderna. */
        fun reminderActionTitle(isOn: Boolean) = if (isOn) "Stäng av påminnelse" else "Slå på påminnelse"

        /**
         * [remindersAllowed] är sant när systemet tillåter notiser, [remindersDenied] när det har nekat dem. Är frågan inte
         * ställd än är båda falska, och raderna visar då det planerade läget. [placedOutTimes] är när kärlen ställdes ut, för
         * raden Utställt.
         */
        fun make(
            addresses: List<SavedAddress>,
            schedules: Map<AddressKey, CachedSchedule>,
            settings: ReminderSettings,
            now: Instant,
            remindersAllowed: Boolean = true,
            remindersDenied: Boolean = false,
            liveActivity: ExistingActivity? = null,
            liveActivitiesEnabled: Boolean = true,
            liveActivityError: String? = null,
            missedReminder: String? = null,
            reserveAt: Instant? = null,
            ownPlacedOut: Set<PlacedOut> = emptySet(),
            placedOutTimes: Map<PlacedOut, Instant> = emptyMap(),
        ): HomeContent {
            val today = StockholmClock.today(now)
            val primaryAddress = addresses.firstOrNull { it.isPrimary } ?: addresses.firstOrNull()
            val common = Common(today, now, remindersAllowed, remindersDenied, liveActivitiesEnabled, ownPlacedOut, placedOutTimes)
            val primary = primaryAddress?.let { address ->
                entry(address, schedules[address.key], settings, common, asRow = false, liveActivity, liveActivityError, missedReminder, reserveAt)
            }
            val others = addresses.filter { it.key != primaryAddress?.key }.map { address ->
                // Samma regel som huvudkortet, men utan Live Update och reservnotis. "Påminnelsen har passerat" räknas här,
                // eftersom väntande Live Updates bara finns för huvudadressen.
                val notificationsOnly = settings.copy(liveActivityOn = false)
                val schedule = schedules[address.key]
                val missed = if (address.notificationsOn && remindersAllowed) {
                    AddressDetail.missedReminder(schedule?.response?.events ?: emptyList(), settings, now)
                } else {
                    null
                }
                entry(address, schedule, notificationsOnly, common, asRow = true, liveActivity = null, liveActivityError = null, missedReminder = missed, reserveAt = null)
            }
            return HomeContent(primary, others)
        }

        /** Det som är lika för alla adresser i en beräkning. */
        private data class Common(
            val today: DayDate,
            val now: Instant,
            val remindersAllowed: Boolean,
            val remindersDenied: Boolean,
            val liveActivitiesEnabled: Boolean,
            val ownPlacedOut: Set<PlacedOut>,
            val placedOutTimes: Map<PlacedOut, Instant>,
        )

        private fun entry(
            address: SavedAddress,
            schedule: CachedSchedule?,
            settings: ReminderSettings,
            common: Common,
            asRow: Boolean,
            liveActivity: ExistingActivity?,
            liveActivityError: String?,
            missedReminder: String?,
            reserveAt: Instant?,
        ): Entry {
            val today = common.today
            val status = status(schedule, today)
            val refreshFailed = schedule?.response != null && schedule.lastError != null
            var rowReminder: RowReminder? = null
            var primaryReminder: PrimaryReminder? = null
            var scheduleEnding: ScheduleEnding? = null
            var nextPickup: DayDate? = null
            val summary: String
            when (status) {
                is Status.Upcoming -> {
                    val pickup = status.pickup
                    nextPickup = pickup.date
                    // Raderna under Fler adresser visar ingen sådan rad, så TalkBack ska inte läsa den heller.
                    scheduleEnding = if (asRow) null else ScheduleEnding.make(schedule?.response?.schedule, today)
                    // Hårt mellanslag före mittpunkten, så att den aldrig börjar en rad.
                    summary = SwedishFormat.estimated(
                        "${SwedishFormat.shortDate(pickup.date)}$NBSP· ${SwedishFormat.relative(pickup.daysUntil)}",
                        pickup.estimated,
                    )
                    // Raden visar det planerade läget även när systemet inte har frågat än. Bara nekade notiser ger det nekade läget.
                    val notifications = address.notificationsOn && (if (asRow) !common.remindersDenied else common.remindersAllowed)
                    val skipping = skippedDays(address.key, common.ownPlacedOut)
                    val text = {
                        reminderText(
                            notifications, settings, schedule?.response?.events ?: emptyList(), skipping, today, common.now, liveActivity,
                            common.liveActivitiesEnabled, liveActivityError, missedReminder, reserveAt,
                        )
                    }
                    if (!asRow) {
                        primaryReminder = PrimaryReminder.fromText(text(), isOn = notifications, isDenied = common.remindersDenied, isWanted = address.notificationsOn)
                    } else if (address.notificationsOn) {
                        rowReminder = when {
                            common.remindersDenied -> RowReminder.Denied
                            missedReminder != null -> RowReminder.Missed(missedReminder)
                            else -> RowReminder.Scheduled(text())
                        }
                    }
                }
                Status.NoUpcoming -> summary = "Inga kommande hämtningar"
                Status.Loading -> summary = "Hämtar schema…"
                is Status.Failed -> summary = if (status.error == ApiError.NotFound) "Adressen hittas inte längre" else "Kunde inte hämta schemat"
            }
            return Entry(
                key = address.key,
                title = address.displayName,
                lines = lines(address),
                status = status,
                refreshFailed = refreshFailed,
                reminder = primaryReminder,
                rowReminder = rowReminder,
                scheduleEnding = scheduleEnding,
                summary = summary,
                placedOut = PlacedOutLine.make(
                    address.key, nextPickup, today, common.ownPlacedOut,
                    remindersOn = address.notificationsOn || (address.isPrimary && settings.liveActivityOn),
                    placedOutTimes = common.placedOutTimes,
                ),
            )
        }

        /**
         * Gatan eller områdets namn på första raden, och orten och kommunens hela namn på den andra. Ett område har hela sitt
         * namn som gata och ingen ort: "Kaplansgården, Jularbo m.fl." och "Avesta kommun". Kommunen utelämnas när den bara
         * upprepar orten, också i genitiv. Hårt mellanslag mellan gatunamn och nummer och före mittpunkten, så att raderna
         * aldrig bryts där. Är namnet detsamma som gatan står gatan inte en gång till, bara platsen.
         */
        fun lines(address: SavedAddress): AddressLines {
            val trimmed = address.street.trim(Char::isWhitespace)
            val name = address.displayName.trim(Char::isWhitespace)
            val street = if (trimmed.equals(name, ignoreCase = true)) "" else trimmed.replace(spaceBeforeNumber, NBSP)
            return AddressLines(address = street, place = localityAndKommun(address.locality, address.kommun))
        }

        /**
         * Som [lines], med adressens namn på första raden. För vyer där rubriken inte är adressens namn, som Hela schemat.
         * Regeln om gatan tar då bara bort dubbletten: är namnet detsamma som gatan står det en gång, som namn.
         */
        fun namedLines(address: SavedAddress): AddressLines {
            val base = lines(address)
            val name = address.displayName.trim(Char::isWhitespace).replace(spaceBeforeNumber, NBSP)
            return AddressLines(name = name, address = base.address, place = base.place)
        }

        private fun status(schedule: CachedSchedule?, today: DayDate): Status {
            schedule ?: return Status.Loading
            val response = schedule.response ?: return schedule.lastError?.let { Status.Failed(it) } ?: Status.Loading
            val event = ScheduleLogic.nextPickup(response.events, today) ?: return Status.NoUpcoming
            val daysUntil = today.daysUntil(event.date)
            val headline = SwedishFormat.estimated(SwedishFormat.relative(daysUntil), event.estimated)
            val longDate = SwedishFormat.estimated(SwedishFormat.longDate(event.date, capitalized = !event.estimated), event.estimated)
            return Status.Upcoming(
                Pickup(
                    date = event.date,
                    daysUntil = daysUntil,
                    estimated = event.estimated,
                    fractions = event.fractions.map { FractionItem(it, ScheduleLogic.displayInfo(it, response.fractions)) },
                    headline = headline.capitalizedFirst(),
                    longDate = longDate.capitalizedFirst(),
                ),
            )
        }

        /**
         * Påminnelsen gäller kvällen före en hämtning eller samma morgon, i svensk tid. Har tiden för nästa hämtning redan
         * passerat räknas den från nästa hämtning efter den. Finns ingen sådan visas en neutral text. Texten ska vara sann:
         * en tid för Live Update lovas bara när en finns hos systemet.
         */
        private fun reminderText(
            notifications: Boolean,
            settings: ReminderSettings,
            events: List<PickupEvent>,
            skipping: Set<DayDate>,
            today: DayDate,
            now: Instant,
            liveActivity: ExistingActivity?,
            liveActivitiesEnabled: Boolean,
            liveActivityError: String?,
            missedReminder: String?,
            reserveAt: Instant?,
        ): String {
            // En Live Update för en utställd tömning tas bort av planeringen, så den lovas inte.
            if (settings.liveActivityOn && liveActivity != null && liveActivity.pickupDate !in skipping) {
                if (!liveActivity.isPending) return "Live Update visas nu"
                // En tid som redan passerat lovas inte, även om den står kvar som väntande.
                if (liveActivity.start > now) {
                    // Live Updaten och notiserna för samma tömning nämns tillsammans. Står bara Live Updaten ser det ut som att
                    // notisen är av.
                    val notes = if (notifications) notificationDates(liveActivity.pickupDate, settings, skipping, now) else emptyList()
                    return upcomingText(notes, liveActivity.start, today)
                }
            }
            // Felet visas även med notiser på. Annars kan kortet lova en senare tömning när nästa står utan påminnelse.
            if (settings.liveActivityOn && liveActivityError != null) return liveActivityError
            if (!notifications && !settings.liveActivityOn) return reminderTitle()
            if (!notifications) return if (liveActivitiesEnabled) "Ingen Live Update planerad" else "Live Updates är avstängda"
            // En reservnotis som ligger framför är den påminnelse som gäller just nu.
            reserveAt?.let { return "Reservpåminnelse kl. ${AddressDetail.clock(it)}" }
            missedReminder?.let { return it }
            ReminderTime.next(events, settings, now, skipping)?.let { next ->
                return upcomingText(notificationDates(next.pickup, settings, skipping, now), null, today)
            }
            return "Påminnelser på"
        }

        /** Notistiderna som är kvar för en tömning, i tidsordning: en per påslaget val. */
        private fun notificationDates(pickup: DayDate, settings: ReminderSettings, skipping: Set<DayDate>, now: Instant): List<Instant> {
            if (pickup in skipping) return emptyList()
            return settings.enabledTimings.map { ReminderTime.date(pickup, it, settings) }.filter { it > now }.sorted()
        }

        /**
         * Alla påminnelser som är kvar för samma tömning, i tidsordning. Bara notiser: "Påminnelse söndag kl. 15:00 och måndag
         * kl. 06:00". Med en Live Update får varje tid sitt slag: "Notis och Live Update söndag kl. 15:00, notis måndag kl.
         * 06:00". En notis inom en minut från starten räknas som samma tid, också när den har blivit reserv.
         */
        private fun upcomingText(notifications: List<Instant>, activityStart: Instant?, today: DayDate): String {
            if (activityStart == null) return "Påminnelse " + notifications.joinToString(" och ") { startText(it, today) }
            val moments = mutableListOf<Pair<Instant, String>>()
            var activityPlaced = false
            for (date in notifications) {
                if (!activityPlaced && Duration.between(activityStart, date).abs() < Duration.ofSeconds(60)) {
                    moments += activityStart to "notis och Live Update"
                    activityPlaced = true
                } else {
                    moments += date to "notis"
                }
            }
            if (!activityPlaced) moments += activityStart to "Live Update"
            return moments.sortedBy { it.first }.joinToString(", ") { "${it.second} ${startText(it.first, today)}" }.capitalizedFirst()
        }

        /**
         * Tömningarna för en adress som saknar påminnelser: de utställda. Samma mängd som planeraren får, så att texterna
         * aldrig lovar en påminnelse som planeraren har tagit bort.
         */
        internal fun skippedDays(key: AddressKey, ownPlacedOut: Set<PlacedOut>): Set<DayDate> =
            ownPlacedOut.filter { it.key == key }.map { it.date }.toSet()

        /** "tisdag kl. 18:00", i svensk tid. Från en vecka bort räcker inte veckodagen: "tisdag 8 dec kl. 18:00". */
        private fun startText(date: Instant, today: DayDate): String {
            val day = StockholmClock.today(date)
            val weekday = SwedishFormat.weekdayName(day)
            val whenText = if (today.daysUntil(day) >= 7) "$weekday ${SwedishFormat.dayMonth(day)}" else weekday
            return "$whenText kl. ${AddressDetail.clock(date)}"
        }
    }
}
