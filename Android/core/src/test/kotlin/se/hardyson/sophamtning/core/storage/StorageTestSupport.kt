package se.hardyson.sophamtning.core.storage

import java.io.File
import java.nio.file.Files
import java.time.Instant
import se.hardyson.sophamtning.core.api.AddressResponse
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.fixture

/** En tillfällig katalog per test. */
fun tempDir(): File = Files.createTempDirectory("sophamtning-test-").toFile().also { it.deleteOnExit() }

val testKey = AddressKey(source = "orebro", id = "storgatan-21_örebro-75130")

fun savedAddress(key: AddressKey = testKey, isPrimary: Boolean = false, addedAt: Instant = Instant.ofEpochSecond(1_800_000_000)) = SavedAddress(
    key = key,
    url = "https://sopor.hardyson.se/api/v1/adress/orebro/storgatan-21_%C3%B6rebro-75130",
    street = "Storgatan 21",
    locality = "Örebro",
    kommun = "Örebro",
    detail = null,
    selection = "address",
    displayName = "Storgatan 21, Örebro",
    isPrimary = isPrimary,
    addedAt = addedAt,
)

fun fixtureResponse(): AddressResponse = ApiDecoding.addressResponse(fixture("adress"))
