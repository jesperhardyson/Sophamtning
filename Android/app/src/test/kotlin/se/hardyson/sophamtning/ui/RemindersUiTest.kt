package se.hardyson.sophamtning.ui

import android.provider.Settings as SystemSettings
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.lifecycle.Lifecycle
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.compose.runtime.CompositionLocalProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager
import se.hardyson.sophamtning.LocalAppDependencies
import se.hardyson.sophamtning.core.reminders.NotificationAuthorization
import se.hardyson.sophamtning.core.reminders.NotificationScheduling
import se.hardyson.sophamtning.core.reminders.PendingNotification
import se.hardyson.sophamtning.core.reminders.PlannedNotification
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.core.storage.ReminderTiming
import se.hardyson.sophamtning.navigation.Address
import se.hardyson.sophamtning.navigation.AppNavigation
import se.hardyson.sophamtning.navigation.ReminderTimeChoice
import se.hardyson.sophamtning.navigation.Settings
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

/** Notiser som räknar frågorna om tillstånd och svarar [answer]. */
private class AskingNotifications(var status: NotificationAuthorization, private val answer: Boolean = true) : NotificationScheduling {
    var requests = 0
    override suspend fun authorization() = status
    override suspend fun requestAuthorization(): Boolean {
        requests++
        status = if (answer) NotificationAuthorization.Authorized else NotificationAuthorization.Denied
        return answer
    }
    override suspend fun pending() = emptyList<PendingNotification>()
    override suspend fun schedule(notifications: List<PlannedNotification>) = emptyList<String>()
    override suspend fun cancel(identifiers: List<String>) {}
    override suspend fun deliverNow(identifier: String, title: String, body: String) {}
}

/** Påminnelsernas inställningar, som ReminderToggleRow.swift och avsnittet Notiser i SettingsView.swift. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = PHONE)
class RemindersUiTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val key = testHit("Testgatan 1").let { AddressKey(it.source, it.id) }

    private fun show(app: TestApp, screen: NavKey, waitFor: String) {
        app.model.add(testHit("Testgatan 1"))
        compose.setContent {
            CompositionLocalProvider(LocalAppDependencies provides app.dependencies) {
                SophamtningTheme { AppNavigation(app.model, rememberNavBackStack(screen)) }
            }
        }
        compose.waitForText(waitFor)
    }

    private fun toggle(text: String) = compose.onNode(isToggleable() and hasText(text, substring = true), useUnmergedTree = false)

    private fun tap(text: String) {
        compose.onNode(hasText(text) and hasClickAction()).performScrollTo().performClick()
    }

    private fun waitFor(condition: () -> Boolean) {
        compose.waitUntil(5_000) {
            compose.idleFor(50)
            condition()
        }
    }

    private fun startedAction(): String? = shadowOf(compose.activity).nextStartedActivity?.action

    @Test
    fun paminnMigFragarOmNotiserOchSlarPa() {
        val notifications = AskingNotifications(NotificationAuthorization.NotDetermined)
        val app = TestApp(reminders = notifications)
        show(app, Address(key), waitFor = "Påminnelser")
        assertEquals(0, notifications.requests)

        toggle("Påminn mig").performScrollTo().performClick()
        waitFor { app.model.state.value.address(key)?.notificationsOn == true }
        assertEquals(1, notifications.requests)
        compose.waitForIdle()
        toggle("Påminn mig").assertIsOn()
    }

    @Test
    fun nekadVisarRutanMedOppnaInstallningar() {
        val app = TestApp(reminders = AskingNotifications(NotificationAuthorization.Denied))
        show(app, Address(key), waitFor = "Påminnelser")
        compose.waitForText("Notiser är avstängda")
        tap("Öppna inställningar")
        assertEquals(SystemSettings.ACTION_APP_NOTIFICATION_SETTINGS, startedAction())
    }

    @Test
    fun exaktaTiderVisasBaraNarDeBehovs() {
        val app = TestApp()
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        show(app, Settings, waitFor = "Notiser")
        // Utan påminnelse behövs inga exakta tider.
        assertFalse(compose.isShowing("Exakta tider"))

        CoroutineScope(Dispatchers.Main).launch { app.model.setNotifications(true, key) }
        compose.waitForText("Exakta tider")
        tap("Exakta tider")
        assertEquals(SystemSettings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, startedAction())

        // Användaren tillåter exakta tider och kommer tillbaka till appen.
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        waitFor { !compose.isShowing("Exakta tider") }
    }

    @Test
    fun tidsvaljarenGerKvartarInomIntervallet() {
        val app = TestApp()
        show(app, ReminderTimeChoice(ReminderTiming.EveningBefore, liveUpdate = false), waitFor = "15:00")
        val choices = compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.Selected)).fetchSemanticsNodes()
        // 15:00 till 23:00 i steg om 15 minuter.
        assertEquals(33, choices.size)
        assertFalse(compose.isShowing("14:45"))
        tap("19:15")
        waitFor { app.model.state.value.settings.reminderMinutes == 19 * 60 + 15 }
        tap("23:00")
        waitFor { app.model.state.value.settings.reminderMinutes == 23 * 60 }
    }

    @Test
    fun liveUpdateKanSlasPaOchVisasFran() {
        val notifications = AskingNotifications(NotificationAuthorization.NotDetermined)
        val app = TestApp(reminders = notifications)
        show(app, Settings, waitFor = "Live Update")
        assertFalse(compose.isShowing("Visas från"))

        toggle("Live Update").performScrollTo().performClick()
        waitFor { app.model.state.value.settings.liveActivityOn }
        // Live Update är en notis, så frågan ställs när den slås på.
        assertEquals(1, notifications.requests)
        compose.waitForText("Visas från")
        assertTrue(compose.isShowing("Kvällen före, 18:00", substring = true))

        tap("Visas från")
        compose.waitForText("Samma morgon")
        tap("Samma morgon")
        waitFor { app.model.state.value.settings.liveActivityTiming == ReminderTiming.SameMorning }
        assertEquals(6 * 60, app.model.state.value.settings.liveActivityStartMinutes)
    }

    @Test
    fun kallmeddelandenFragarAldrigOmTillstand() {
        val notifications = AskingNotifications(NotificationAuthorization.NotDetermined)
        val app = TestApp(reminders = notifications)
        show(app, Settings, waitFor = "Meddelanden från källan")
        // Utan tillstånd i systemet går reglaget inte att ändra, och det frågar aldrig.
        toggle("Meddelanden från källan").performScrollTo().assertIsNotEnabled()
        toggle("Meddelanden från källan").performClick()
        compose.idleFor(200)
        assertEquals(0, notifications.requests)
        assertTrue(app.model.state.value.settings.sourceMessagesOn)
    }
}
