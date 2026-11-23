package se.hardyson.sophamtning.ui.screens

import androidx.compose.runtime.Composable
import se.hardyson.sophamtning.navigation.AddAddress
import se.hardyson.sophamtning.navigation.Address
import se.hardyson.sophamtning.navigation.AppNavigator
import se.hardyson.sophamtning.navigation.AreaConfirm
import se.hardyson.sophamtning.navigation.AreaFinder
import se.hardyson.sophamtning.navigation.AreaPicker
import se.hardyson.sophamtning.navigation.FullSchedule
import se.hardyson.sophamtning.navigation.Rename
import se.hardyson.sophamtning.ui.address.RenameScreen
import se.hardyson.sophamtning.ui.address.AddressScreen
import se.hardyson.sophamtning.ui.address.FullScheduleScreen
import se.hardyson.sophamtning.ui.area.AreaConfirmScreen
import se.hardyson.sophamtning.ui.area.AreaFinderScreen
import se.hardyson.sophamtning.ui.area.AreaPickerScreen
import se.hardyson.sophamtning.ui.home.HomeScreen
import se.hardyson.sophamtning.ui.kommun.KommunScreen
import se.hardyson.sophamtning.ui.search.SearchScreen
import se.hardyson.sophamtning.ui.settings.ChangelogScreen
import se.hardyson.sophamtning.ui.settings.DataSourcesScreen
import se.hardyson.sophamtning.ui.settings.PrimaryAddressScreen
import se.hardyson.sophamtning.ui.settings.SettingsScreen
import se.hardyson.sophamtning.ui.settings.LiveUpdateTimingScreen
import se.hardyson.sophamtning.ui.settings.ReminderTimeChoiceScreen
import se.hardyson.sophamtning.ui.settings.ReminderTimesScreen

/** Skärmen för varje nyckel i backstacken. */
object AppScreens {
    @Composable fun Home(navigator: AppNavigator) = HomeScreen(navigator)
    @Composable fun Search(key: AddAddress, navigator: AppNavigator) = SearchScreen(key, navigator)
    @Composable fun Kommun(navigator: AppNavigator) = KommunScreen(navigator)
    @Composable fun AreaPicker(key: AreaPicker, navigator: AppNavigator) = AreaPickerScreen(key, navigator)
    @Composable fun AreaFinder(key: AreaFinder, navigator: AppNavigator) = AreaFinderScreen(key, navigator)
    @Composable fun AreaConfirm(key: AreaConfirm, navigator: AppNavigator) = AreaConfirmScreen(key, navigator)
    @Composable fun Address(key: Address, navigator: AppNavigator) = AddressScreen(key.key, navigator)
    @Composable fun FullSchedule(key: FullSchedule, navigator: AppNavigator) = FullScheduleScreen(key.key, navigator)
    @Composable fun Rename(key: Rename, navigator: AppNavigator) = RenameScreen(key.key, navigator)
    @Composable fun Settings(navigator: AppNavigator) = SettingsScreen(navigator)
    @Composable fun PrimaryAddressChoice(navigator: AppNavigator) = PrimaryAddressScreen(navigator)
    @Composable fun ReminderTimes(navigator: AppNavigator) = ReminderTimesScreen(navigator)
    @Composable fun ReminderTimeChoice(key: se.hardyson.sophamtning.navigation.ReminderTimeChoice, navigator: AppNavigator) =
        ReminderTimeChoiceScreen(key.timing, key.liveUpdate, navigator)
    @Composable fun LiveUpdateTiming(navigator: AppNavigator) = LiveUpdateTimingScreen(navigator)
    @Composable fun DataSources(navigator: AppNavigator) = DataSourcesScreen(navigator)
    @Composable fun Changelog(navigator: AppNavigator) = ChangelogScreen(navigator)
}
