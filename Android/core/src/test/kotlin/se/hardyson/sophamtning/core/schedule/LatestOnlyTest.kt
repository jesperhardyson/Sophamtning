package se.hardyson.sophamtning.core.schedule

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest

private class Boom : Exception()

class LatestOnlyTest {
    @Test
    fun gammaltSvarErsatterInteNytt() = runTest {
        val latest = LatestOnly()
        val gate = CompletableDeferred<Unit>()
        val started = CompletableDeferred<Unit>()
        val first = async { latest.run { started.complete(Unit); gate.await(); 1 } }
        started.await()
        val second = latest.run { 2 }
        gate.complete(Unit)
        assertEquals(2, second)
        assertNull(first.await())
    }

    @Test
    fun ensamtAnropGerSittVarde() = runTest { assertEquals(7, LatestOnly().run { 7 }) }

    @Test
    fun felFranDetNyasteKastas() = runTest {
        assertFailsWith<Boom> { LatestOnly().run<Int> { throw Boom() } }
    }

    @Test
    fun felFranGammaltAnropGerNil() = runTest {
        val latest = LatestOnly()
        val gate = CompletableDeferred<Unit>()
        val started = CompletableDeferred<Unit>()
        val first = async { latest.run<Int> { started.complete(Unit); gate.await(); throw Boom() } }
        started.await()
        latest.run { 2 }
        gate.complete(Unit)
        assertNull(first.await())
    }
}
