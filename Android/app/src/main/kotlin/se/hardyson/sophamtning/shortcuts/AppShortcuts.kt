package se.hardyson.sophamtning.shortcuts

import android.content.Context
import androidx.core.content.edit
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.storage.SavedAddress
import se.hardyson.sophamtning.navigation.AppLink

/**
 * Genvägarna på appikonen, som Siris genvägar på iOS men utan röst. Den fasta genvägen **Lägg till adress** står i
 * `res/xml/shortcuts.xml`. Den dynamiska öppnar huvudadressen och följer den när den byts, byter namn eller tas bort.
 */
object AppShortcuts {
    const val PRIMARY_ID = "huvudadress"

    /** Håller genvägen till huvudadressen i takt med appens tillstånd, så länge processen lever. */
    fun observe(model: AppModel, context: Context, scope: CoroutineScope) {
        val app = context.applicationContext
        scope.launch {
            model.state
                .map { state -> state.addresses.firstOrNull { it.isPrimary } ?: state.addresses.firstOrNull() }
                .distinctUntilChanged()
                .collect { update(app, it) }
        }
    }

    /**
     * Lägger in genvägen till [primary], eller tar bort den utan huvudadress. Genvägen läggs bara in när adressen eller
     * namnet har ändrats sedan förra gången, också i en tidigare process, så att varje start av appen inte lägger in den
     * på nytt.
     */
    fun update(context: Context, primary: SavedAddress?) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val pushed = primary?.let { listOf(it.key.source, it.key.id, it.displayName) }
        val previous = PUSHED.map { preferences.getString(it, null) }.takeIf { values -> values.all { it != null } }
        if (previous == pushed) return
        if (primary == null) {
            ShortcutManagerCompat.removeDynamicShortcuts(context, listOf(PRIMARY_ID))
        } else {
            val shortcut = ShortcutInfoCompat.Builder(context, PRIMARY_ID)
                .setShortLabel(primary.displayName)
                .setLongLabel(context.getString(R.string.shortcut_primary_long, primary.displayName))
                .setIcon(IconCompat.createWithResource(context, R.drawable.ic_shortcut_home))
                .setIntent(AppLink.OpenAddress(primary.key).intent(context))
                .build()
            // Ersätter genvägen med samma id, och låter startprogrammet räkna hur den används.
            ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
        }
        preferences.edit { PUSHED.forEachIndexed { index, name -> putString(name, pushed?.get(index)) } }
    }

    private const val PREFERENCES = "genvagar"
    /** Källan, id:t och namnet för genvägen som senast lades in. De jämförs bara, och tolkas aldrig. */
    private val PUSHED = listOf("källa", "id", "namn")
}
