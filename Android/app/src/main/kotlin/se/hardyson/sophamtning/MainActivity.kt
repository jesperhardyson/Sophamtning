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
        setContent { SophamtningApp(dependencies) }
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
