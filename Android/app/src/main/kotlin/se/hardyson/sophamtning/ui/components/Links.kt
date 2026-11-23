package se.hardyson.sophamtning.ui.components

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.net.toUri
import se.hardyson.sophamtning.core.kommun.WebLink

/** Öppnar en webbsida i Custom Tabs, som `SFSafariViewController` på iOS. Bara `https` öppnas (`WebLink`). */
fun Context.openWebLink(link: WebLink) {
    try {
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(this, link.url.toUri())
    } catch (_: ActivityNotFoundException) {
        // Utan webbläsare finns inget att öppna.
    }
}

/** Öppnar en webbadress i Custom Tabs, om den är `https`. */
fun Context.openWeb(url: String) {
    WebLink(url)?.let(::openWebLink)
}

/** Låter systemet öppna adressen: ringa, skriva ett mejl eller öppna Google Kalender. */
fun Context.openExternal(url: String) {
    try {
        startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        // Ingen app kan öppna adressen.
    }
}
