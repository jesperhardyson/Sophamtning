package se.hardyson.sophamtning.reminders

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import kotlinx.coroutines.CompletableDeferred
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization

/**
 * Tillståndet för notiser (`POST_NOTIFICATIONS`), och frågan om det. Frågan ställs genom aktiviteten, som kopplar in sig med
 * [attach], och bara när användaren slår på en påminnelse eller Live Update. Utan aktivitet ställs ingen fråga.
 */
class NotificationPermission(private val context: Context) {
    private var launcher: ActivityResultLauncher<String>? = null
    private var waiting: CompletableDeferred<Boolean>? = null
    private val preferences get() = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    /** Systemets tillstånd. "Inte avgjort" tills appen har ställt frågan, så att frågan ställs en gång, som på iOS. */
    fun authorization(): NotificationAuthorization = when {
        canNotify(context) -> NotificationAuthorization.Authorized
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !granted() && !preferences.getBoolean(ASKED, false) ->
            NotificationAuthorization.NotDetermined
        else -> NotificationAuthorization.Denied
    }

    /** Kopplar in aktivitetens fråga. Anropas i `onCreate`, före `onStart`. */
    fun attach(activity: ComponentActivity) {
        launcher = activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
            waiting?.complete(allowed)
            waiting = null
        }
    }

    fun detach(activity: ComponentActivity) {
        if (!activity.isChangingConfigurations) launcher = null
    }

    /** Visar systemets fråga och svarar med om notiser tillåts. Före Android 13 finns ingen fråga. Anropas på huvudtråden. */
    suspend fun request(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return canNotify(context)
        val launcher = launcher ?: return false
        preferences.edit { putBoolean(ASKED, true) }
        val answer = waiting ?: CompletableDeferred<Boolean>().also {
            waiting = it
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        return answer.await() && canNotify(context)
    }

    /** Om tillståndet är givet. Före Android 13 finns det inte, och då räknas det som givet. */
    private fun granted() = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    companion object {
        private const val PREFERENCES = "notiser"
        private const val ASKED = "fragat"

        /** Om appen får visa notiser just nu. */
        fun canNotify(context: Context): Boolean {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        }
    }
}
