package se.hardyson.sophamtning.reminders

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import se.hardyson.sophamtning.R

/**
 * Appens notiskanaler. Påminnelserna har hög vikt, så att de syns ovanpå andra appar. Live Update och Meddelanden från
 * källan har standardvikt. Namnen och beskrivningarna står i `strings.xml`, och användaren kan stänga av varje kanal.
 */
object NotificationChannels {
    const val REMINDERS = "paminnelser"
    const val LIVE_UPDATE = "live-update"
    const val SOURCE_MESSAGES = "meddelanden-fran-kallan"

    /** Skapar kanalerna, eller uppdaterar namn och beskrivning. Användarens val för en kanal ändras aldrig av det. */
    fun create(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannels(
            listOf(
                channel(context, REMINDERS, R.string.channel_reminders, R.string.channel_reminders_description, NotificationManager.IMPORTANCE_HIGH),
                channel(context, LIVE_UPDATE, R.string.channel_live_update, R.string.channel_live_update_description, NotificationManager.IMPORTANCE_DEFAULT),
                channel(
                    context, SOURCE_MESSAGES, R.string.channel_source_messages, R.string.channel_source_messages_description,
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            ),
        )
    }

    private fun channel(context: Context, id: String, name: Int, description: Int, importance: Int) =
        NotificationChannel(id, context.getString(name), importance).apply { this.description = context.getString(description) }
}

/**
 * Notisens heltals-id, från identifieraren som `PlannedNotification.identifier` och `SourceMessages.notificationId` ger.
 * `String.hashCode` är fastlagd i Java och ger alltid samma tal för samma sträng. Strängen är också notisens tagg, så två
 * strängar med samma tal blandas aldrig ihop.
 */
fun notificationId(identifier: String): Int = identifier.hashCode()
