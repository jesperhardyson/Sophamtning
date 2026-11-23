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
import se.hardyson.sophamtning.core.storage.AddressKey
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
    private fun install(now: Instant): TestApp {
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
        val app = TestApp(clock = TestClock(now), dir = SophamtningApplication.storeDirectory(application))
        application.dependencies = app.dependencies
        return app
    }

    private fun tile(): Pair<PlaceOutTileService, Tile> {
        val service = Robolectric.buildService(PlaceOutTileService::class.java).create().get()
        service.onStartListening()
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
        idleUntil { true }
        assertTrue(appStore.placedOut().isEmpty())
    }
}
