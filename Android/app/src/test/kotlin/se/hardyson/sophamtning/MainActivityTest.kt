package se.hardyson.sophamtning

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun startvynVisasUtanSparadeAdresser() {
        compose.onNodeWithText("När töms dina kärl?").assertIsDisplayed()
    }

    @Test
    fun versionenKommerFranVersionTxt() {
        // Enhetstesterna körs i app-mappen, så version.txt ligger en nivå upp.
        assertEquals(File("../version.txt").readText().trim(), BuildConfig.VERSION_NAME)
    }
}
