package se.hardyson.sophamtning.shortcuts

import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.xmlpull.v1.XmlPullParser
import se.hardyson.sophamtning.R
import se.hardyson.sophamtning.SophamtningApp
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.navigation.AppLink
import se.hardyson.sophamtning.reminders.application
import se.hardyson.sophamtning.reminders.idleUntil
import se.hardyson.sophamtning.ui.PHONE
import se.hardyson.sophamtning.ui.TestApp
import se.hardyson.sophamtning.ui.testHit
import se.hardyson.sophamtning.ui.waitForText

/** Genvägarna på appikonen: huvudadressen och Lägg till adress. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class AppShortcutsTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun dynamic() = ShortcutManagerCompat.getDynamicShortcuts(application)

    @Test
    fun dynamiskGenvagTillHuvudadressen() {
        val app = TestApp()
        val first = testHit("Testgatan 1")
        val second = testHit("Testgatan 2")
        app.model.add(first)
        app.model.add(second)
        val scope = MainScope()
        AppShortcuts.observe(app.model, application, scope)
        idleUntil { dynamic().size == 1 }
        val shortcut = dynamic().single()
        assertEquals("Hemma", shortcut.shortLabel)
        assertEquals(AppLink.OpenAddress(AddressKey(first.source, first.id)), AppLink.from(shortcut.intent))

        // Huvudadressen byts, och genvägen följer med.
        app.model.setPrimary(AddressKey(second.source, second.id))
        idleUntil { dynamic().singleOrNull()?.let { AppLink.from(it.intent) } == AppLink.OpenAddress(AddressKey(second.source, second.id)) }

        // Utan adresser finns ingen genväg till huvudadressen.
        app.model.remove(AddressKey(first.source, first.id))
        app.model.remove(AddressKey(second.source, second.id))
        idleUntil { dynamic().isEmpty() }
        scope.cancel()
    }

    @Test
    fun genvagenLaggTillAdressOppnarSokningen() {
        // Den fasta genvägen i shortcuts.xml har en länk som navigeringen läser.
        val parser = application.resources.getXml(R.xml.shortcuts)
        var action: String? = null
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType == XmlPullParser.START_TAG && parser.name == "intent") action = parser.getAttributeValue(ANDROID, "action")
        }
        val link = AppLink.from(Intent(action))
        assertEquals(AppLink.AddAddress, link)

        val app = TestApp()
        app.model.add(testHit("Testgatan 1"))
        compose.setContent { SophamtningApp(app.dependencies, link) }
        compose.waitForText("Gata och husnummer")
    }

    private companion object {
        const val ANDROID = "http://schemas.android.com/apk/res/android"
    }
}
