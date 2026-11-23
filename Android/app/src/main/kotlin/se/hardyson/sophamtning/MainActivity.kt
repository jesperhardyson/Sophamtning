package se.hardyson.sophamtning

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import se.hardyson.sophamtning.navigation.AppLink
import se.hardyson.sophamtning.navigation.AppNavigation
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

class MainActivity : ComponentActivity() {
    /** Länken från widgeten, rutan eller en genväg, tills navigeringen har följt den. */
    private var link by mutableStateOf<AppLink?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Efter att aktiviteten återskapats är länken redan följd, och backstacken är sparad.
        if (savedInstanceState == null) link = AppLink.from(intent)
        enableEdgeToEdge()
        val dependencies = (application as SophamtningApplication).dependencies
        // Frågan om notiser går genom aktiviteten, och ställs bara när användaren slår på en påminnelse eller Live Update.
        dependencies.notificationPermission?.attach(this)
        setContent { SophamtningApp(dependencies, link) { link = null } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        AppLink.from(intent)?.let { link = it }
    }

    override fun onDestroy() {
        (application as SophamtningApplication).dependencies.notificationPermission?.detach(this)
        super.onDestroy()
    }
}

/** Hela appen med tema och beroenden. Testerna visar samma vy med sina egna beroenden. */
@Composable
fun SophamtningApp(dependencies: AppDependencies, link: AppLink? = null, onLinkHandled: () -> Unit = {}) {
    CompositionLocalProvider(LocalAppDependencies provides dependencies) {
        SophamtningTheme {
            AppNavigation(dependencies.model, link = link, onLinkHandled = onLinkHandled)
        }
    }
}
