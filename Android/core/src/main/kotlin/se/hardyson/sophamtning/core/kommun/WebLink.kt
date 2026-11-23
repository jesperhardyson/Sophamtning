package se.hardyson.sophamtning.core.kommun

import java.net.URI
import java.net.URISyntaxException
import java.util.Locale

/** En webbadress som appen får visa i sin egen webbvy. Bara `https` med en värd godkänns. */
class WebLink private constructor(val url: String) {
    val id: String get() = url

    override fun equals(other: Any?) = other is WebLink && other.url == url

    override fun hashCode() = url.hashCode()

    override fun toString() = "WebLink($url)"

    companion object {
        /** `null` för allt som inte är `https` med en värd, som `WebLink(url:)` på iOS. */
        operator fun invoke(url: String): WebLink? {
            val uri = try { URI(url) } catch (_: URISyntaxException) { return null }
            if (uri.scheme?.lowercase(Locale.ROOT) != "https") return null
            // En värd med å, ä eller ö tolkas inte som värd av URI, men står kvar i adressens auktoritet.
            val host = uri.host ?: uri.rawAuthority?.substringAfterLast('@')?.substringBefore(':')
            if (host.isNullOrEmpty()) return null
            return WebLink(url)
        }
    }
}
