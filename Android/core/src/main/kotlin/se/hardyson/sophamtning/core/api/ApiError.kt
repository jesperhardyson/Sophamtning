package se.hardyson.sophamtning.core.api

/** Fel från Sopor API:t. Klienten mappar på HTTP-status, inte på felkoden i svaret. */
sealed class ApiError : Exception() {
    /** 400: ogiltig förfrågan. */
    data object BadRequest : ApiError() { private fun readResolve(): Any = BadRequest }

    /** 404: adressen eller källan finns inte. */
    data object NotFound : ApiError() { private fun readResolve(): Any = NotFound }

    /** 502: källan svarar inte just nu. Behåll det senast lyckade svaret. */
    data object SourceUnavailable : ApiError() { private fun readResolve(): Any = SourceUnavailable }

    /** Nätverksfel, till exempel tidsgräns eller ingen uppkoppling. */
    data object Network : ApiError() { private fun readResolve(): Any = Network }

    /** Alla andra statuskoder, och svar som inte går att tolka (då med status 200). */
    data class Unexpected(val status: Int) : ApiError()
}
