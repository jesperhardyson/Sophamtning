package se.hardyson.sophamtning.core.kommun

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class WebLinkTest {
    @Test
    fun httpsGodkanns() {
        val url = "https://sopor.hardyson.se/bidra"
        val link = assertNotNull(WebLink(url))
        assertEquals(url, link.url)
        assertEquals(url, link.id)
    }

    @Test
    fun versalerIScheman() {
        assertNotNull(WebLink("HTTPS://sopor.hardyson.se/bidra"))
    }

    @Test
    fun andraSchemanGerNil() {
        for (text in listOf(
            "http://sopor.hardyson.se/bidra",
            "mailto:hej@example.se",
            "file:///etc/hosts",
            "javascript:alert(1)",
            "tel:+46701234567",
            "sophamtning://hem",
        )) {
            assertNull(WebLink(text), text)
        }
    }

    @Test
    fun relativAdressGerNil() {
        assertNull(WebLink("/bidra"))
    }

    @Test
    fun utanVardGerNil() {
        for (text in listOf("https:", "https://", "https:///bidra")) {
            assertNull(WebLink(text), text)
        }
    }
}
