package se.hardyson.sophamtning

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import se.hardyson.sophamtning.navigation.AppNavigation
import se.hardyson.sophamtning.ui.theme.SophamtningTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val dependencies = (application as SophamtningApplication).dependencies
        // Frågan om notiser går genom aktiviteten, och ställs bara när användaren slår på en påminnelse eller Live Update.
        dependencies.notificationPermission?.attach(this)
        setContent { SophamtningApp(dependencies) }
    }

    override fun onDestroy() {
        (application as SophamtningApplication).dependencies.notificationPermission?.detach(this)
        super.onDestroy()
    }
}

/** Hela appen med tema och beroenden. Testerna visar samma vy med sina egna beroenden. */
@Composable
fun SophamtningApp(dependencies: AppDependencies) {
    CompositionLocalProvider(LocalAppDependencies provides dependencies) {
        SophamtningTheme {
            AppNavigation(dependencies.model)
        }
    }
}
