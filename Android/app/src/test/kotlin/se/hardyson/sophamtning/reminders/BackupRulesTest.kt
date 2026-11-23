package se.hardyson.sophamtning.reminders

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.xmlpull.v1.XmlPullParser
import se.hardyson.sophamtning.R

/**
 * Säkerhetskopian och flytten till en ny telefon tar med adresserna och inställningarna, men inte det som är schemalagt på
 * den här telefonen och inte om appen redan har frågat om notiser. Alarmen och frågan hör till telefonen.
 */
@RunWith(AndroidJUnit4::class)
class BackupRulesTest {
    /** Undantagen per del (`cloud-backup` och `device-transfer`), som "domän:sökväg". */
    private fun exclusions(): Map<String, Set<String>> {
        val parser = application.resources.getXml(R.xml.data_extraction_rules)
        val result = mutableMapOf<String, MutableSet<String>>()
        var section = ""
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType != XmlPullParser.START_TAG) continue
            when (parser.name) {
                "cloud-backup", "device-transfer" -> section = parser.name
                "exclude" -> result.getOrPut(section) { mutableSetOf() } +=
                    "${parser.getAttributeValue(null, "domain")}:${parser.getAttributeValue(null, "path")}"
            }
        }
        return result
    }

    @Test
    fun schemalagdaPaminnelserOchFraganFoljerInteMed() {
        val expected = setOf("file:Sophamtning/${ScheduledReminders.FILE}", "sharedpref:notiser.xml")
        assertEquals(mapOf("cloud-backup" to expected, "device-transfer" to expected), exclusions())
    }
}
