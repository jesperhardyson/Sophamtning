package se.hardyson.sophamtning.core.api

import io.ktor.client.HttpClient
import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.timeout
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.url
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.Url
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException
import se.hardyson.sophamtning.core.dates.DayDate

/** Klient mot Sopor API v1. Adresser hämtas från den sparade `url:en` oförändrad. */
class SoporClient(engine: HttpClientEngine, version: String) : SoporApi {
    private val userAgent = "Sophamtning-Android/$version"
    private val http = HttpClient(engine) {
        expectSuccess = false
        install(HttpTimeout)
    }

    override suspend fun search(query: String, source: String?): SearchResponse {
        val items = buildList {
            add("q" to query)
            if (source != null) add("kalla" to source)
        }
        return decode(endpoint("sok", items), ApiDecoding::searchResponse)
    }

    override suspend fun areas(place: String) = decode(endpoint("omraden", listOf("plats" to place)), ApiDecoding::searchResponse)

    override suspend fun areas(place: String, lastEmptied: DayDate) =
        decode(endpoint("omraden", listOf("plats" to place, "tomning" to lastEmptied.iso)), ApiDecoding::searchResponse)

    override suspend fun address(url: String) = decode(url, ApiDecoding::addressResponse)

    override suspend fun sources(): SourcesResponse {
        val all = decode(endpoint("kallor", emptyList()), ApiDecoding::sourcesResponse)
        return all.copy(sources = all.sources.filterNot { it.testData })
    }

    // MARK: Internt

    /** Hämtar och avkodar. Ett svar som inte går att tolka blir `Unexpected` med svarets status. */
    private suspend fun <T> decode(url: String, decoder: (String) -> T): T {
        val (status, body) = request(url)
        return try {
            decoder(body)
        } catch (_: DecodeException) {
            throw ApiError.Unexpected(status)
        }
    }

    private suspend fun request(url: String): Pair<Int, String> {
        val response = try {
            http.get {
                // Adressen tolkas som den är, så att procentkodningen aldrig görs om.
                url(Url(url))
                header(HttpHeaders.UserAgent, userAgent)
                header(HttpHeaders.Accept, "application/json")
                timeout { requestTimeoutMillis = TIMEOUT_MILLIS }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: IOException) {
            throw ApiError.Network
        }
        val status = response.status.value
        when (status) {
            in 200..299 -> return status to response.bodyAsText()
            400 -> throw ApiError.BadRequest
            404 -> throw ApiError.NotFound
            502 -> throw ApiError.SourceUnavailable
            else -> throw ApiError.Unexpected(status)
        }
    }

    companion object {
        const val BASE_URL = "https://sopor.hardyson.se/api/v1"
        const val TIMEOUT_MILLIS = 15_000L

        private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"

        /** Bygger adressen för hand så att allt utom oreserverade tecken procentkodas, även `+` och `,`. */
        internal fun endpoint(path: String, items: List<Pair<String, String>>): String {
            val query = items.joinToString("&") { (key, value) -> "${encode(key)}=${encode(value)}" }
            return if (query.isEmpty()) "$BASE_URL/$path" else "$BASE_URL/$path?$query"
        }

        private fun encode(value: String) = buildString {
            for (byte in value.encodeToByteArray()) {
                val char = byte.toInt().toChar()
                if (byte >= 0 && char in UNRESERVED) append(char) else append("%%%02X".format(java.util.Locale.ROOT, byte.toInt() and 0xFF))
            }
        }
    }
}
