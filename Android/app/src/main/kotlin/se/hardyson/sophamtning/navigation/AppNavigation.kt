package se.hardyson.sophamtning.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import se.hardyson.sophamtning.core.app.AppModel
import se.hardyson.sophamtning.core.storage.AddressKey
import se.hardyson.sophamtning.ui.screens.AppScreens

/** Flyttar mellan skärmarna. Skärmarna känner bara till det här, inte backstacken. */
class AppNavigator(private val backStack: NavBackStack<NavKey>, private val model: AppModel) {
    fun open(key: NavKey) {
        backStack.add(key)
    }

    fun back() {
        if (backStack.size > 1) backStack.removeAt(backStack.lastIndex)
    }

    /** Stänger hela flödet Lägg till adress utan att spara. */
    fun closeAddFlow() {
        backStack.removeAll { it.isAddFlow }
    }

    /**
     * En adress eller ett område har sparats: flödet stängs och hemskärmen syns. Var flödet "Sök igen" ersätts den gamla
     * adressen nu, när den nya finns.
     */
    fun saved(new: AddressKey) {
        val replacing = backStack.filterIsInstance<AddAddress>().firstNotNullOfOrNull { it.replacing }
        if (replacing != null && replacing != new) model.replace(replacing, new)
        closeAddFlow()
        if (backStack.isEmpty()) backStack.add(Home)
    }

    /** Tillbaka till hemskärmen, till exempel när adressen har tagits bort. */
    fun home() {
        backStack.removeAll { it != Home }
        if (backStack.isEmpty()) backStack.add(Home)
    }
}

/** Appens skärmar i en backstack som sparas när telefonen vrids eller appen dödas. Bakåtgesten är systemets, med förhandsvisning. */
@Composable
fun AppNavigation(model: AppModel) {
    val backStack = rememberNavBackStack(Home)
    val navigator = remember(backStack) { AppNavigator(backStack, model) }
    NavDisplay(
        backStack = backStack,
        onBack = { navigator.back() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),
            // Varje skärm får sina egna ViewModels, som rensas när skärmen tas bort från backstacken.
            rememberViewModelStoreNavEntryDecorator(),
        ),
        entryProvider = entryProvider {
            entry<Home> { AppScreens.Home(navigator) }
            entry<AddAddress> { AppScreens.Search(it, navigator) }
            entry<KommunCheck> { AppScreens.Kommun(navigator) }
            entry<AreaPicker> { AppScreens.AreaPicker(it, navigator) }
            entry<AreaFinder> { AppScreens.AreaFinder(it, navigator) }
            entry<AreaConfirm> { AppScreens.AreaConfirm(it, navigator) }
            entry<Address> { AppScreens.Address(it, navigator) }
            entry<FullSchedule> { AppScreens.FullSchedule(it, navigator) }
            entry<Rename> { AppScreens.Rename(it, navigator) }
        },
    )
}
