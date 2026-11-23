package se.hardyson.sophamtning.core.api

import io.ktor.client.engine.okhttp.OkHttp
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

/** Anropar Sopor API i produktion, som ContractTests på iOS. Körs för hand: ./gradlew :core:contractTest */
class ContractTest {
    private val client = SoporClient(OkHttp.create(), version = "kontrakt")

    @Test
    fun kallornaGarAttLasa() = runBlocking {
        assertTrue(client.sources().sources.isNotEmpty())
    }

    @Test
    fun sokningOchAdressGarAttLasa() = runBlocking {
        val hit = client.search("Storgatan", null).addresses.first { !it.isArea }
        assertTrue(client.address(hit.url).events.isNotEmpty())
    }
}
