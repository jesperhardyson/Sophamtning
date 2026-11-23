package se.hardyson.sophamtning.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import java.time.Instant
import kotlinx.coroutines.delay

/**
 * Anropar [onTick] vid varje minutbyte medan skärmen syns, så att "i dag" och "i morgon" räknas om, till exempel vid
 * midnatt. Samma på hemskärmen, i adressvyn och i Hela schemat.
 */
@Composable
fun MinuteTick(clock: () -> Instant, onTick: () -> Unit) {
    val tick by rememberUpdatedState(onTick)
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000L - clock().toEpochMilli() % 60_000L)
            tick()
        }
    }
}
