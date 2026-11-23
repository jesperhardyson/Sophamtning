package se.hardyson.sophamtning.core.api

import se.hardyson.sophamtning.core.dates.DayDate

/** Sopor API v1, som SoporAPI.swift på iOS. */
interface SoporApi {
    suspend fun search(query: String, source: String?): SearchResponse
    suspend fun areas(place: String): SearchResponse
    suspend fun areas(place: String, lastEmptied: DayDate): SearchResponse
    /** Hämtar [url] från sökträffen oförändrad. */
    suspend fun address(url: String): AddressResponse
    /** Alla källor utom de med testdata. */
    suspend fun sources(): SourcesResponse
}
