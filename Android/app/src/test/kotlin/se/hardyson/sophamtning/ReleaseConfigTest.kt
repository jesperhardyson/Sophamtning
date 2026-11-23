package se.hardyson.sophamtning

import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Release-byggets signering, prövad med Gradle i en egen process. Ett osignerat bygge får aldrig nå Play: utan
 * uppladdningsnyckeln stoppar bygget med ett tydligt fel, och debug-nyckeln används bara med `-Psigning=debug`.
 */
class ReleaseConfigTest {
    // Enhetstesterna körs i modulens katalog, Android/app.
    private val project = File("..").canonicalFile

    @Test
    fun releaseUtanNyckelByggsInteTystOsignerad() {
        val (code, output) = gradle(":app:checkReleaseSigning")
        assertNotEquals(output, 0, code)
        for (name in SIGNING_VARIABLES) assertTrue(output, output.contains(name))
        assertTrue(output, output.contains("-Psigning=debug"))
    }

    @Test
    fun aabOchApkKontrollerarSigneringenForstPaketeras() {
        val (code, output) = gradle(":app:bundleRelease", ":app:assembleRelease", "--dry-run")
        assertEquals(output, 0, code)
        val lines = output.lines()
        val check = lines.indexOf(":app:checkReleaseSigning SKIPPED")
        assertTrue(output, check >= 0)
        assertTrue(output, check < lines.indexOf(":app:packageReleaseBundle SKIPPED"))
        assertTrue(output, check < lines.indexOf(":app:packageRelease SKIPPED"))
    }

    @Test
    fun releaseMedNyckelnGarIgenom() {
        val keystore = Files.createTempFile("upload", ".jks").toFile()
        try {
            val (code, output) = gradle(":app:checkReleaseSigning", environment = signing(keystore.path))
            assertEquals(output, 0, code)
        } finally {
            keystore.delete()
        }
    }

    @Test
    fun nyckelfilSomSaknasStoppar() {
        val missing = File(project, "finns-inte.jks").path
        val (code, output) = gradle(":app:checkReleaseSigning", environment = signing(missing))
        assertNotEquals(output, 0, code)
        assertTrue(output, output.contains("finns-inte.jks"))
    }

    @Test
    fun debugNyckelnBaraMedFlaggan() {
        val (code, output) = gradle(":app:checkReleaseSigning", "-Psigning=debug")
        assertEquals(output, 0, code)
        assertTrue(output, output.contains("debug-nyckeln"))
    }

    private fun signing(keystore: String) = mapOf(
        "SOPHAMTNING_UPLOAD_KEYSTORE" to keystore,
        "SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD" to "losenord",
        "SOPHAMTNING_UPLOAD_KEY_ALIAS" to "upload",
        "SOPHAMTNING_UPLOAD_KEY_PASSWORD" to "losenord",
    )

    /** Kör Gradle utan nyckelns miljövariabler, utöver [environment]. Ger utgångskoden och utskriften. */
    private fun gradle(vararg arguments: String, environment: Map<String, String> = emptyMap()): Pair<Int, String> {
        // Egen projektcache, så att den här körningen inte väntar på låsen i bygget som kör testet.
        val cache = Files.createTempDirectory("release-config").toFile()
        try {
            val command = listOf(File(project, "gradlew").path, "--console=plain", "--project-cache-dir", cache.path) +
                arguments
            val builder = ProcessBuilder(command).directory(project).redirectErrorStream(true)
            SIGNING_VARIABLES.forEach(builder.environment()::remove)
            builder.environment().putAll(environment)
            val process = builder.start()
            val output = process.inputStream.bufferedReader().readText()
            check(process.waitFor(5, TimeUnit.MINUTES)) { "Gradle blev inte klart" }
            return process.exitValue() to output
        } finally {
            cache.deleteRecursively()
        }
    }

    private companion object {
        val SIGNING_VARIABLES = listOf(
            "SOPHAMTNING_UPLOAD_KEYSTORE",
            "SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD",
            "SOPHAMTNING_UPLOAD_KEY_ALIAS",
            "SOPHAMTNING_UPLOAD_KEY_PASSWORD",
        )
    }
}
