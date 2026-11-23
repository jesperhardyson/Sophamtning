package se.hardyson.sophamtning.core.storage

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import se.hardyson.sophamtning.core.messages.SourceMessageKey
import se.hardyson.sophamtning.core.messages.SourceMessageMemory

// Från SourceMessagesTests på iOS.
class SourceMessageMemoryStoreTest {
    @Test
    fun minnetILagringen() {
        val dir = tempDir()
        val store = LocalStore(dir)
        assertIs<StoreRead.Missing>(store.sourceMessageMemoryState(), "ska saknas")
        val memory = SourceMessageMemory().markSeen(listOf(SourceMessageKey(source = "avesta", id = "a")))
        store.setSourceMessageMemory(memory)
        val read = assertIs<StoreRead.Value<SourceMessageMemory>>(store.sourceMessageMemoryState(), "ska gå att läsa")
        assertEquals(memory, read.value)
        File(dir, "source-messages.json").writeText("{trasig")
        assertIs<StoreRead.Unreadable>(store.sourceMessageMemoryState(), "ska vara oläslig")
    }
}
