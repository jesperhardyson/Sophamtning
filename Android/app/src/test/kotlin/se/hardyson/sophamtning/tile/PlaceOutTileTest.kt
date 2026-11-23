package se.hardyson.sophamtning.tile

import android.service.quicksettings.Tile
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.dates.StockholmClock
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.NotificationScheduling
import se.hardyson.sophamtning.core.reminders.PendingNotification
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.core.storage.CachedSchedule
import se.hardyson.sophamtning.core.storage.PlacedOut
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.reminders.appStore
import se.hardyson.sophamtning.reminders.application
import se.hardyson.sophamtning.reminders.idleUntil
import se.hardyson.sophamtning.ui.TestApp
import se.hardyson.sophamtning.ui.TestClock
import se.hardyson.sophamtning.ui.day
import se.hardyson.sophamtning.ui.uiTestData

/** Rutan Ställ ut kärlen i snabbinställningarna, som PlaceOutControl.swift. Den gäller huvudadressen. */
@RunWith(AndroidJUnit4::class)
class PlaceOutTileTest {
    private val key = AddressKey("orebro", "1")
    private val pickup = PlacedOut(key, day("2026-11-11"))

    /** Huvudadressen med schemat där nästa tömning är onsdag 11 november, och appen med klockan [now]. */
    private fun install(now: Instant, reminders: se.hardyson.sophamtning.core.reminders.NotificationScheduling = se.hardyson.sophamtning.ui.AllowedReminders()): TestApp {
        val store = appStore
        store.setAddresses(
            listOf(
                SavedAddress(
                    key = key, url = "https://sopor.hardyson.se/api/v1/adress/orebro/1", street = "Storgatan 1", locality = "Örebro",
                    kommun = "Örebro", selection = "address", displayName = "Hemma", isPrimary = true, notificationsOn = false, addedAt = now,
                ),
            ),
        )
        store.setSchedule(CachedSchedule(ApiDecoding.addressResponse(uiTestData("uitest-adress")), fetchedAt = now), key)
        val app = TestApp(clock = TestClock(now), reminders = reminders, dir = SophamtningApplication.storeDirectory(application))
        application.dependencies = app.dependencies
        return app
    }

    private fun tile(): Pair<PlaceOutTileService, Tile> {
        val service = Robolectric.buildService(PlaceOutTileService::class.java).create().get()
        service.onStartListening()
        // Lagringen läses utanför huvudtråden, och rutan ritas sedan.
        idleUntil { service.qsTile.subtitle != null }
        return service to service.qsTile
    }

    @Test
    fun rutanArAktivNarKarlenSkaStallasUt() {
        install(StockholmClock.dateOn(day("2026-11-10"), 19 * 60 + 42))
        val (_, tile) = tile()
        assertEquals(Tile.STATE_ACTIVE, tile.state)
        assertEquals("Ställ ut kärlen", tile.label)
        // Undertexten är nästa tömning.
        assertEquals("I morgon", tile.subtitle)
    }

    @Test
    fun rutanVisarUtstalltEfterTryck() {
        val evening = StockholmClock.dateOn(day("2026-11-10"), 19 * 60 + 42)
        val app = install(evening)
        val (service, tile) = tile()
        service.onClick()
        idleUntil { pickup in appStore.placedOut() && tile.subtitle == "Utställt" }
        // Samma väg som Klart: bocken har tid och syns i appen.
        assertTrue(pickup in app.model.state.value.ownPlacedOut)
        assertEquals(evening, app.model.state.value.placedOutTimes[pickup])
        assertEquals(Tile.STATE_INACTIVE, tile.state)
        // Rutan som visas nästa gång säger också Utställt.
        val (_, again) = tile()
        assertEquals("Utställt", again.subtitle)
        assertEquals(Tile.STATE_INACTIVE, again.state)
    }

    @Test
    fun rutanArAvstangdUtanTomningSnart() {
        // Fem dagar kvar: inget att ställa ut, och undertexten är datumet.
        install(StockholmClock.dateOn(day("2026-11-06"), 12 * 60))
        val (service, tile) = tile()
        assertEquals(Tile.STATE_UNAVAILABLE, tile.state)
        assertEquals("Ons 11 nov", tile.subtitle)
        service.onClick()
        org.robolectric.shadows.ShadowLooper.idleMainLooper(500, java.util.concurrent.TimeUnit.MILLISECONDS)
        Thread.sleep(200)
        org.robolectric.shadows.ShadowLooper.idleMainLooper()
        assertTrue(appStore.placedOut().isEmpty())
    }

    @Test
    fun trycketGorKlartAvenNarRutanStangs() {
        val reminders = RecordingReminders()
        val evening = StockholmClock.dateOn(day("2026-11-10"), 19 * 60 + 42)
        val app = install(evening, reminders)
        val service = Robolectric.buildService(PlaceOutTileService::class.java).create().get()
        service.onStartListening()
        service.onClick()
        // Snabbinställningarna stängs direkt, och systemet tar bort rutans tjänst.
        service.onStopListening()
        // Robolectric kan inte köra `TileService.onDestroy` till slut (skuggan går inte att omvandla), men rutans egen
        // del körs före systemets.
        runCatching { service.onDestroy() }
        idleUntil { pickup in appStore.placedOut() && reminders.cancelled.size == ReminderTiming.entries.size }
        assertTrue(pickup in app.model.state.value.ownPlacedOut)
        assertEquals(ReminderTiming.entries.map { PlannedNotification.identifier(key, pickup.date, it) }.toSet(), reminders.cancelled.toSet())
    }

    @Test
    fun rutanArAktivOchRitasOmNarAppenBerOmDet() {
        // En aktiv ruta binds av systemet när appen ber om det, så att den stämmer när snabbinställningarna öppnas.
        val info = application.packageManager.getServiceInfo(
            android.content.ComponentName(application, PlaceOutTileService::class.java),
            android.content.pm.PackageManager.GET_META_DATA,
        )
        assertTrue(info.metaData.getBoolean(android.service.quicksettings.TileService.META_DATA_ACTIVE_TILE))
    }

    @Test
    fun rutanFarAlarmetVidMidnattUtanWidget() {
        // Rutan ritas bara om när appen ber om det, så den behöver midnatten för att "i morgon" ska bli "i dag".
        install(StockholmClock.dateOn(day("2026-11-10"), 12 * 60))
        val service = Robolectric.buildService(PlaceOutTileService::class.java).create().get()
        service.onTileAdded()
        assertTrue(midnight().isNotEmpty())
        service.onTileRemoved()
        assertTrue(midnight().isEmpty())
    }

    private fun midnight() = se.hardyson.sophamtning.reminders.alarms.scheduledAlarms
        .filter { org.robolectric.Shadows.shadowOf(it.operation).savedIntent.action == se.hardyson.sophamtning.widget.WidgetUpdates.ACTION_MIDNIGHT }

    /** Notiser som tillåts, och som minns vilka som tagits bort. */
    private class RecordingReminders : NotificationScheduling {
        val cancelled = java.util.Collections.synchronizedList(mutableListOf<String>())
        override suspend fun authorization() = NotificationAuthorization.Authorized
        override suspend fun requestAuthorization() = true
        override suspend fun pending() = emptyList<PendingNotification>()
        override suspend fun schedule(notifications: List<PlannedNotification>) = emptyList<String>()
        override suspend fun cancel(identifiers: List<String>) {
            cancelled += identifiers
        }
        override suspend fun deliverNow(identifier: String, title: String, body: String) {}
    }
}
