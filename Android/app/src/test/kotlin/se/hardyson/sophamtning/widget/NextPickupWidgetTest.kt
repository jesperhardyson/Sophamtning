package se.hardyson.sophamtning.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.hasContentDescription
import androidx.glance.testing.unit.hasTestTag
import androidx.glance.testing.unit.hasText
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.PickupEvent
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.core.widget.WidgetData
import se.hardyson.sophamtning.reminders.alarms
import se.hardyson.sophamtning.reminders.application
import se.hardyson.sophamtning.reminders.idleUntil
import se.hardyson.sophamtning.reminders.onMain
import se.hardyson.sophamtning.ui.TestApp
import se.hardyson.sophamtning.ui.TestClock
import se.hardyson.sophamtning.ui.day
import se.hardyson.sophamtning.ui.uiTestData

/** Widgeten Nästa tömning, som NextPickupWidget.swift och WidgetContentTests på iOS. Texterna själva testas i `core`. */
@RunWith(AndroidJUnit4::class)
class NextPickupWidgetTest {
    private val key = AddressKey("orebro", "1")

    /** Fredag 6 november 2026 kl. 12, fem dagar före tömningen av plast och glas onsdag 11 november. */
    private val friday = StockholmClock.dateOn(day("2026-11-06"), 12 * 60)

    private fun address(name: String = "Hemma") = SavedAddress(
        key = key, url = "https://sopor.hardyson.se/api/v1/adress/orebro/1", street = "Storgatan 1", locality = "Örebro",
        kommun = "Örebro", selection = "address", displayName = name, isPrimary = true, notificationsOn = false, addedAt = friday,
    )

    /** En lagring med huvudadressen och, om [events] inte är `null`, ett schema. */
    private fun store(dir: File = kotlin.io.path.createTempDirectory("widget-").toFile(), events: List<PickupEvent>? = null, schedule: Boolean = true): LocalStore {
        val store = LocalStore(dir)
        store.setAddresses(listOf(address()))
        if (schedule) {
            val base = ApiDecoding.addressResponse(uiTestData("uitest-adress"))
            val response = if (events == null) base else base.copy(events = events, next = emptyList())
            store.setSchedule(CachedSchedule(response, fetchedAt = friday), key)
        }
        return store
    }

    private fun show(data: WidgetData, now: Instant, size: androidx.compose.ui.unit.DpSize, assertions: androidx.glance.appwidget.testing.unit.GlanceAppWidgetUnitTest.() -> Unit) =
        runGlanceAppWidgetUnitTest {
            setContext(application)
            setAppWidgetSize(size)
            provideComposable { NextPickupContent(data, now) }
            assertions()
        }

    @Test
    fun litenVisarDagOchKarl() = show(WidgetData.read(store()), friday, NextPickupWidget.SMALL) {
        onNode(hasText("Hemma")).assertExists()
        onNode(hasText("Om 5 dagar")).assertExists()
        onNode(hasText("Ons 11 nov")).assertExists()
        // Kärlen syns som ikoner, och TalkBack läser dem med namn, de senare med datum.
        onNode(hasContentDescription("Hemma. Om 5 dagar, Ons 11 nov. Glas, Plastförpackningar. Senare: Matavfall tors 12 nov")).assertExists()
        // Ingen knapp i den lilla, som på iOS.
        onAllNodes(hasTestTag(WidgetTags.PLACE_OUT)).assertCountEquals(0)
    }

    @Test
    fun mellanVisarEttKarlPerRadOchPlusTill() {
        val day = day("2026-11-11")
        val events = listOf(
            PickupEvent(day, listOf("rest", "mat", "plast", "glas"), false, null, null, emptyMap()),
            PickupEvent(day("2026-11-12"), listOf("papper"), false, null, null, emptyMap()),
        )
        show(WidgetData.read(store(events = events)), friday, NextPickupWidget.MEDIUM_TALL) {
            onNode(hasText("Om 5 dagar")).assertExists()
            // Kalenderbladet har datumet, så raderna har bara kärlen. Får de inte plats blir sista raden "+2 till", för
            // samma tömning, och papper dagen efter visas inte.
            onNode(hasText("NOV")).assertExists()
            onNode(hasText("11")).assertExists()
            onNode(hasText("Glas")).assertExists()
            onNode(hasText("Matavfall")).assertExists()
            onAllNodes(hasText("Plastförpackningar")).assertCountEquals(0)
            onAllNodes(hasText("Restavfall")).assertCountEquals(0)
            onNode(hasText("+2 till")).assertExists()
            onAllNodes(hasText("Pappersförpackningar")).assertCountEquals(0)
        }
        // Med största textstorleken ryms färre rader, och fler kärl blir "+N till" i stället för att klippas.
        val large = application.createConfigurationContext(android.content.res.Configuration(application.resources.configuration).apply { fontScale = 2f })
        runGlanceAppWidgetUnitTest {
            setContext(large)
            setAppWidgetSize(NextPickupWidget.MEDIUM_TALL)
            provideComposable { NextPickupContent(WidgetData.read(store(events = events)), friday) }
            onNode(hasText("Glas")).assertExists()
            onAllNodes(hasText("Matavfall")).assertCountEquals(0)
            onNode(hasText("+3 till")).assertExists()
        }
    }

    @Test
    fun utanHuvudadressVisasUppmaning() {
        val empty = LocalStore(kotlin.io.path.createTempDirectory("widget-").toFile())
        for (size in listOf(NextPickupWidget.SMALL, NextPickupWidget.MEDIUM_TALL)) {
            show(WidgetData.read(empty), friday, size) {
                onNode(hasText("Lägg till en adress i appen")).assertExists()
            }
        }
    }

    @Test
    fun utanSchemaVisasInteSomSaknadAdress() {
        show(WidgetData.read(store(schedule = false)), friday, NextPickupWidget.SMALL) {
            onNode(hasText("Hemma")).assertExists()
            onNode(hasText("Schemat har inte hämtats än")).assertExists()
            onAllNodes(hasText("Lägg till en adress i appen")).assertCountEquals(0)
        }
        // Filerna går inte att läsa, till exempel en skadad fil. Det är inte att adressen saknas.
        val dir = kotlin.io.path.createTempDirectory("widget-").toFile()
        store(dir)
        File(dir, "addresses.json").writeText("{inte json")
        show(WidgetData.read(LocalStore(dir)), friday, NextPickupWidget.SMALL) {
            onNode(hasText("Kan inte visa schemat just nu")).assertExists()
            onAllNodes(hasText("Lägg till en adress i appen")).assertCountEquals(0)
        }
    }

    @Test
    fun stallUtSparasOchWidgetenVisarUtstallt() {
        // Kvällen före tömningen. Appen är inte öppen: knappen körs i appens process, som startas av widgeten.
        val evening = StockholmClock.dateOn(day("2026-11-10"), 19 * 60 + 42)
        val store = store(SophamtningApplication.storeDirectory(application))
        val app = TestApp(clock = TestClock(evening), dir = SophamtningApplication.storeDirectory(application))
        application.dependencies = app.dependencies
        val target = PlacedOut(key, day("2026-11-11"))
        show(WidgetData.read(store), evening, NextPickupWidget.MEDIUM_TALL) {
            onNode(hasTestTag(WidgetTags.PLACE_OUT)).assertExists()
            onNode(hasText("Ställ ut kärlen")).assertExists()
        }
        val before = WidgetUpdates.version.value
        onMain { PlaceOutAction.placeOut(application, PlaceOutAction.entry(PlaceOutAction.parameters(target))!!) }
        // Bocken är sparad med tid, i appens tillstånd och i lagringen, och widgeten ritas om.
        assertTrue(target in store.placedOut())
        assertTrue(target in app.model.state.value.ownPlacedOut)
        assertTrue(app.model.state.value.placedOutTimes[target] == evening)
        assertTrue(WidgetUpdates.version.value > before)
        show(WidgetData.read(store), evening, NextPickupWidget.MEDIUM_TALL) {
            onAllNodes(hasTestTag(WidgetTags.PLACE_OUT)).assertCountEquals(0)
            onNode(hasText("Utställda")).assertExists()
        }
    }

    @Test
    fun widgetenUppdaterasVidMidnatt() {
        val data = WidgetData.read(store())
        // "I morgon" blir "i dag" vid midnatt i Stockholm.
        show(data, StockholmClock.dateOn(day("2026-11-10"), 23 * 60 + 59), NextPickupWidget.SMALL) { onNode(hasText("I morgon")).assertExists() }
        show(data, StockholmClock.dateOn(day("2026-11-11"), 0).plusSeconds(30), NextPickupWidget.SMALL) { onNode(hasText("I dag")).assertExists() }

        // Med en widget på hemskärmen ligger ett alarm vid nästa midnatt i Stockholm.
        val manager = AppWidgetManager.getInstance(application)
        shadowOf(manager).bindAppWidgetId(1, ComponentName(application, NextPickupWidgetReceiver::class.java))
        WidgetUpdates.armMidnight(application, StockholmClock.dateOn(day("2026-11-10"), 22 * 60))
        assertEquals(listOf(StockholmClock.dateOn(day("2026-11-11"), 0).toEpochMilli()), midnightAlarms())

        // Telefonen startas om och glömmer alarmet, som läggs in igen.
        val alarmManager = application.getSystemService(android.app.AlarmManager::class.java)
        alarmManager.cancel(WidgetUpdates.midnightIntent(application))
        assertTrue(midnightAlarms().isEmpty())
        application.sendBroadcast(Intent(Intent.ACTION_BOOT_COMPLETED).setPackage(application.packageName))
        idleUntil { midnightAlarms().isNotEmpty() }
        assertEquals(listOf(WidgetUpdates.nextMidnight(Instant.now()).toEpochMilli()), midnightAlarms())

        // Vid midnatt ritas widgeten om och nästa midnatt läggs in.
        alarmManager.cancel(WidgetUpdates.midnightIntent(application))
        val before = WidgetUpdates.version.value
        application.sendBroadcast(Intent(WidgetUpdates.ACTION_MIDNIGHT).setClass(application, MidnightReceiver::class.java))
        idleUntil { WidgetUpdates.version.value > before && midnightAlarms().isNotEmpty() }
    }

    private fun midnightAlarms() = alarms.scheduledAlarms
        .filter { shadowOf(it.operation).savedIntent.action == WidgetUpdates.ACTION_MIDNIGHT }
        .map { it.triggerAtMs }
}
