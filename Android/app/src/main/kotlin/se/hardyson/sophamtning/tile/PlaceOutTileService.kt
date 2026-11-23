package se.hardyson.sophamtning.tile

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import java.time.Instant
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.SophamtningApplication
import se.hardyson.sophamtning.core.storage.LocalStore
import se.hardyson.sophamtning.core.widget.PlaceOutTileContent
import se.hardyson.sophamtning.core.widget.WidgetData
import se.hardyson.sophamtning.widget.PlaceOutAction

/**
 * Rutan **Ställ ut kärlen** i snabbinställningarna, för huvudadressen. Ett tryck gör samma sak som Klart i Live Updaten,
 * via `AppModel.markPlacedOut`, utan att appen öppnas. Rutan läser bara från lagringen och gör inga nätanrop. Den läser om
 * varje gång snabbinställningarna visas, och appen ber om en omritning när Utställt eller schemat ändras.
 */
class PlaceOutTileService : TileService() {
    private var destroyed = false

    private fun content(): PlaceOutTileContent {
        val store = LocalStore(SophamtningApplication.storeDirectory(this))
        val clock = (application as? SophamtningApplication)?.dependencies?.clock ?: { Instant.now() }
        return PlaceOutTileContent.make(WidgetData.read(store), clock())
    }

    override fun onStartListening() {
        super.onStartListening()
        render()
    }

    override fun onClick() {
        super.onClick()
        // Bara när kärlen ska ställas ut. Utställt och avstängt gör inget, och bocken ångras i appen.
        val entry = content().entry ?: return
        val dependencies = (application as SophamtningApplication).dependencies
        // Arbetet körs i appens räckvidd och inte rutans: systemet tar bort rutans tjänst när snabbinställningarna stängs,
        // och då får bocken inte bli sparad medan notiserna ligger kvar. Rutan ritas bara om medan den finns.
        dependencies.appScope.launch {
            PlaceOutAction.placeOut(applicationContext, entry)
            if (!destroyed) render()
        }
    }

    override fun onDestroy() {
        destroyed = true
        super.onDestroy()
    }

    private fun render() {
        val tile = qsTile ?: return
        val content = content()
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
        /** Ber systemet rita om rutan, om den syns. */
        fun requestUpdate(context: Context) {
            try {
                requestListeningState(context, ComponentName(context, PlaceOutTileService::class.java))
            } catch (e: IllegalArgumentException) {
                Log.w("Sophamtning", "Rutan kunde inte ritas om", e)
            }
        }
    }
}
