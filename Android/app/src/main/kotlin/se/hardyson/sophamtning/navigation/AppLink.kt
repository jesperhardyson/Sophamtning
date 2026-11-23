package se.hardyson.sophamtning.navigation

import android.content.Context
import android.content.Intent
import se.hardyson.sophamtning.MainActivity
import se.hardyson.sophamtning.core.storage.AddressKey

/**
 * Vart appen öppnas utifrån: från widgeten, rutan i snabbinställningarna och genvägarna på appikonen. Länken är en
 * `Intent` till [MainActivity], som navigeringen läser. Adressens källa och id skickas som de är och tolkas aldrig.
 */
sealed interface AppLink {
    /** Hemskärmen. */
    data object Home : AppLink

    /** Lägg till adress: sökningen, ovanpå hemskärmen. */
    data object AddAddress : AppLink

    /** Adressvyn för [key]. Finns adressen inte längre visas hemskärmen. */
    data class OpenAddress(val key: AddressKey) : AppLink

    fun intent(context: Context): Intent {
        val intent = Intent(context, MainActivity::class.java)
            // Appen har en aktivitet. Är den redan öppen får den länken, i stället för att en till startas.
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return when (this) {
            Home -> intent.setAction(ACTION_HOME)
            AddAddress -> intent.setAction(ACTION_ADD)
            is OpenAddress -> intent.setAction(ACTION_ADDRESS).putExtra(EXTRA_SOURCE, key.source).putExtra(EXTRA_ID, key.id)
        }
    }

    companion object {
        const val ACTION_HOME = "se.hardyson.sophamtning.action.HEM"
        /** Samma som i `res/xml/shortcuts.xml`. */
        const val ACTION_ADD = "se.hardyson.sophamtning.action.LAGG_TILL"
        const val ACTION_ADDRESS = "se.hardyson.sophamtning.action.ADRESS"
        private const val EXTRA_SOURCE = "källa"
        private const val EXTRA_ID = "id"

        /** Länken i en `Intent`, eller `null` när den inte är en länk, som när appen startas från appikonen. */
        fun from(intent: Intent?): AppLink? = when (intent?.action) {
            ACTION_HOME -> Home
            ACTION_ADD -> AddAddress
            ACTION_ADDRESS -> {
                val source = intent.getStringExtra(EXTRA_SOURCE)
                val id = intent.getStringExtra(EXTRA_ID)
                if (source != null && id != null) OpenAddress(AddressKey(source, id)) else Home
            }
            else -> null
        }
    }
}
