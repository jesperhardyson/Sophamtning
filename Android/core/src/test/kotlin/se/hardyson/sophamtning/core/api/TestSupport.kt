package se.hardyson.sophamtning.core.api

import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import java.io.IOException

/** Fixturerna delas med iOS och läses från iOS-paketets testmapp (se build.gradle.kts). */
fun fixture(name: String): String =
    requireNotNull(Stub::class.java.getResource("/$name.json")) { "Fixturen $name saknas" }.readText()

/** Stubbat API: svarar med [status] och [body], eller kastar [error]. Sparar varje anrop. */
class Stub(var status: Int = 200, var body: String = "", var error: IOException? = null) {
    val requests = mutableListOf<HttpRequestData>()

    val engine = MockEngine { request ->
        requests += request
        error?.let { throw it }
        respondJson()
    }

    private fun MockRequestHandleScope.respondJson() =
        respond(body, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))

    fun client() = SoporClient(engine, version = "9.9.9")
}

const val TEST_URL = "https://sopor.hardyson.se/api/v1/adress/uppsala/storgatan-2_uppsala-4004688"
