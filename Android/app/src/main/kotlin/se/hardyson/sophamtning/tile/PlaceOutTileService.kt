package se.hardyson.sophamtning.tile

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.core.content.edit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.widget.PlaceOutTileContent
import se.hardyson.sophamtning.core.widget.WidgetData
import se.hardyson.sophamtning.widget.PlaceOutAction
import se.hardyson.sophamtning.widget.WidgetUpdates

/**
 * Rutan **Ställ ut kärlen** i snabbinställningarna, för huvudadressen. Ett tryck gör samma sak som Klart i Live Updaten,
 * via `AppModel.markPlacedOut`, utan att appen öppnas. Rutan läser bara från lagringen och gör inga nätanrop.
 *
 * Rutan är aktiv (`ACTIVE_TILE` i manifestet): systemet binder den bara när appen ber om det, och appen gör det när
 * Utställt, schemat eller huvudadressen ändras och vid midnatt. Därför stämmer den redan när snabbinställningarna öppnas.
 * Lagringen läses utanför huvudtråden, och rutan ritas på huvudtråden.
 */
class PlaceOutTileService : TileService() {
    private var listening = false

    private val dependencies get() = (application as SophamtningApplication).dependencies

    private suspend fun content(): PlaceOutTileContent {
        val now = dependencies.clock()
        return withContext(Dispatchers.IO) {
            PlaceOutTileContent.make(WidgetData.read(LocalStore(SophamtningApplication.storeDirectory(this@PlaceOutTileService))), now)
        }
    }

    override fun onTileAdded() {
        super.onTileAdded()
        setAdded(this, true)
        // Rutan visar dagen och behöver alarmet vid midnatt.
        WidgetUpdates.armMidnight(this)
    }

    override fun onTileRemoved() {
        setAdded(this, false)
        WidgetUpdates.armMidnight(this)
        super.onTileRemoved()
    }

    override fun onStartListening() {
        super.onStartListening()
        listening = true
        dependencies.appScope.launch { render(content()) }
    }

    override fun onStopListening() {
        listening = false
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        // Arbetet körs i appens räckvidd och inte rutans: systemet tar bort rutans tjänst när snabbinställningarna stängs,
        // och då får bocken inte bli sparad medan notiserna ligger kvar. Rutan ritas bara om medan den syns.
        dependencies.appScope.launch {
            // Bara när kärlen ska ställas ut. Utställt och avstängt gör inget, och bocken ångras i appen.
            val entry = content().entry ?: return@launch
            PlaceOutAction.placeOut(applicationContext, entry)
            render(content())
        }
    }

    /** Ritar rutan, om den fortfarande syns. Körs på huvudtråden. */
    private fun render(content: PlaceOutTileContent) {
        if (!listening) return
        val tile = qsTile ?: return
        tile.label = PlaceOutTileContent.TITLE
        tile.subtitle = content.subtitle
        tile.state = when (content.state) {
            PlaceOutTileContent.State.Active -> Tile.STATE_ACTIVE
            PlaceOutTileContent.State.PlacedOut -> Tile.STATE_INACTIVE
            PlaceOutTileContent.State.Unavailable -> Tile.STATE_UNAVAILABLE
        }
        tile.contentDescription = "${PlaceOutTileContent.TITLE}, ${content.subtitle}"
        tile.updateTile()
    }

    companion object {
        private const val PREFERENCES = "ruta"
        private const val ADDED = "tillagd"

        /** Om rutan ligger i snabbinställningarna. */
        fun isAdded(context: Context): Boolean = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(ADDED, false)

        private fun setAdded(context: Context, added: Boolean) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit { putBoolean(ADDED, added) }
        }

        /** Ber systemet binda rutan och rita om den, så att den stämmer nästa gång den visas. */
        fun requestUpdate(context: Context) {
            try {
                requestListeningState(context, ComponentName(context, PlaceOutTileService::class.java))
            } catch (e: IllegalArgumentException) {
                Log.w("Sophamtning", "Rutan kunde inte ritas om", e)
            } catch (e: SecurityException) {
                Log.w("Sophamtning", "Rutan kunde inte ritas om", e)
            }
        }
    }
}
