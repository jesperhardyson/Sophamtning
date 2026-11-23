package se.hardyson.sophamtning.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import se.hardyson.sophamtning.navigation.AddAddress
import se.hardyson.sophamtning.navigation.Address
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.AreaConfirm
import se.hardyson.sophamtning.navigation.AreaFinder
import se.hardyson.sophamtning.navigation.AreaPicker
import se.hardyson.sophamtning.navigation.FullSchedule

/** Skärmarna för varje nyckel. Skärmarna byggs i uppgift 3 till 5 i plan 4a. */
object AppScreens {
    @Composable fun Home(navigator: AppNavigator) = Placeholder("Sophämtning")
    @Composable fun Search(key: AddAddress, navigator: AppNavigator) = Placeholder("Lägg till adress")
    @Composable fun Kommun(navigator: AppNavigator) = Placeholder("Finns min kommuns hämtningsschema?")
    @Composable fun AreaPicker(key: AreaPicker, navigator: AppNavigator) = Placeholder("Välj område")
    @Composable fun AreaFinder(key: AreaFinder, navigator: AppNavigator) = Placeholder("Hitta område")
    @Composable fun AreaConfirm(key: AreaConfirm, navigator: AppNavigator) = Placeholder("Stämmer området?")
    @Composable fun Address(key: Address, navigator: AppNavigator) = Placeholder("Adress")
    @Composable fun FullSchedule(key: FullSchedule, navigator: AppNavigator) = Placeholder("Hela schemat")

    @Composable
    private fun Placeholder(title: String) {
        Box(Modifier.fillMaxSize()) { Text(title) }
    }
}
