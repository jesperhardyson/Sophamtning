package se.hardyson.sophamtning.reminders

import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

/** Arbetet i mottagarna får aldrig krascha appen, och mottagaren avslutas alltid. */
@RunWith(AndroidJUnit4::class)
class ReceiverWorkTest {
    @Test
    fun felIArbetetKrascharInteOchAvslutar() {
        // Ett fel som ingen fångar hamnar hos trådens hanterare, som i appen avslutar processen.
        val thread = Thread.currentThread()
        val previous = thread.uncaughtExceptionHandler
        var crash: Throwable? = null
        thread.uncaughtExceptionHandler = Thread.UncaughtExceptionHandler { _, e -> crash = e }
        try {
            var finished = 0
            ReceiverWork.launch(finish = { finished++ }) { error("Modellen kastar") }
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(1, finished)
            assertNull(crash)
        } finally {
            thread.uncaughtExceptionHandler = previous
        }
    }
}
