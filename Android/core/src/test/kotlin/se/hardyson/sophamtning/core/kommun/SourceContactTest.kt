package se.hardyson.sophamtning.core.kommun

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.Kommun
import se.hardyson.sophamtning.core.api.Source
import se.hardyson.sophamtning.core.api.SourceContact
import se.hardyson.sophamtning.core.api.kommunerText
import se.hardyson.sophamtning.core.dates.DayDate

/** Källan som ansvarar för hämtningen: avkodningen av `contact` i `/kallor` och länkarna i kortet och på Datakällor. */
class SourceContactTest {
    /** Källan läses som en del av `/kallor`, eftersom ApiDecoding bara läser hela svar. */
    private fun decode(contact: String?): Source {
        val field = contact?.let { """, "contact": $it""" } ?: ""
        val json = """{"id": "uppsala", "name": "Uppsala Vatten", "url": "https://www.uppsalavatten.se", "kommuner": [{"code": "0380", "name": "Uppsala kommun"}], "testData": false$field}"""
        return ApiDecoding.sourcesResponse("""{"sources": [$json], "fractions": {}}""").sources.single()
    }

    private val full = """{"phone": {"number": "+46187279400", "display": "018-727 94 00"}, "email": "kundservice@uppsalavatten.se", "page": "https://www.uppsalavatten.se/kontakt", "checkedAt": "2026-11-07", "checkedUrl": "https://www.uppsalavatten.se/kontakt"}"""

    // Avkodning

    @Test
    fun utanFaltetFinnsIngenKontakt() {
        assertNull(decode(null).contact)
    }

    @Test
    fun nullGerIngenKontakt() {
        assertNull(decode("null").contact)
    }

    @Test
    fun allaDelarAvkodas() {
        val contact = assertNotNull(decode(full).contact)
        assertEquals(SourceContact.Phone(number = "+46187279400", display = "018-727 94 00"), contact.phone)
        assertEquals("kundservice@uppsalavatten.se", contact.email)
        assertEquals("https://www.uppsalavatten.se/kontakt", contact.page)
        assertEquals(DayDate.parse("2026-11-07"), contact.checkedAt)
        assertEquals("https://www.uppsalavatten.se/kontakt", contact.checkedUrl)
    }

    @Test
    fun enskildaDelarKanVaraNull() {
        val contact = assertNotNull(decode("""{"phone": null, "email": "kundservice@uppsalavatten.se", "page": null, "checkedAt": null, "checkedUrl": null}""").contact)
        assertNull(contact.phone)
        assertEquals("kundservice@uppsalavatten.se", contact.email)
        assertNull(contact.page)
        assertNull(contact.checkedAt)
        val partPhone = assertNotNull(decode("""{"phone": {"number": "+46187279400", "display": null}}""").contact)
        assertEquals(SourceContact.Phone(number = "+46187279400", display = null), partPhone.phone)
    }

    @Test
    fun trasigKontaktFallerInteKallan() {
        assertNull(decode("\"ring oss\"").contact)
        val contact = assertNotNull(decode("""{"phone": "018-727 94 00", "email": 12, "page": "https://www.uppsalavatten.se/kontakt"}""").contact)
        assertNull(contact.phone)
        assertNull(contact.email)
        assertNotNull(contact.page)
    }

    @Test
    fun kontaktenSparasOchLasesIgen() {
        val source = decode(full)
        val encoded = ApiDecoding.json.encodeToString(Source.serializer(), source)
        val again = ApiDecoding.sourcesResponse("""{"sources": [$encoded], "fractions": {}}""").sources.single()
        assertEquals(source, again)
    }

    // Länkar

    @Test
    fun webbplatsOchKommunensInformationIOrdning() {
        val links = SourceLink.links(decode(null), kommunInfo = "https://www.uppsala.se/avfall")
        assertEquals(listOf("Webbplats", "Kommunens information"), links.map { it.title })
        assertEquals(listOf(SourceLink.Kind.Website, SourceLink.Kind.KommunInfo), links.map { it.kind })
        assertTrue(links.all { it.webLink != null })
    }

    @Test
    fun kontaktenVisasMedRingMejlOchKontaktsida() {
        val links = SourceLink.links(decode(full), kommunInfo = null)
        assertEquals(listOf(SourceLink.Kind.Website, SourceLink.Kind.Phone, SourceLink.Kind.Email, SourceLink.Kind.ContactPage), links.map { it.kind })
        assertEquals(listOf("Webbplats", "018-727 94 00", "kundservice@uppsalavatten.se", "Kontaktsida"), links.map { it.title })
        // Ikonerna (SF Symbols) väljs i appen på Android och prövas inte här.
        assertEquals("tel:+46187279400", links[1].url)
        assertNull(links[1].webLink)
        assertEquals("mailto:kundservice@uppsalavatten.se", links[2].url)
        assertEquals("https://www.uppsalavatten.se/kontakt", links[3].webLink?.url)
        assertEquals("Ring 018-727 94 00", links[1].accessibilityLabel)
        assertEquals("Mejla kundservice@uppsalavatten.se", links[2].accessibilityLabel)
    }

    @Test
    fun baraTelefonenStarIAccentfargOchWebbsidorFarPil() {
        val links = SourceLink.links(decode(full), kommunInfo = "https://www.uppsala.se/avfall")
        assertEquals(
            listOf(SourceLink.Kind.Website, SourceLink.Kind.KommunInfo, SourceLink.Kind.Phone, SourceLink.Kind.Email, SourceLink.Kind.ContactPage),
            links.map { it.kind },
        )
        // Telefonnumret är det man oftast vill använda, så det står i accentfärg. Resten står i vanlig textfärg.
        assertEquals(listOf(false, false, true, false, false), links.map { it.isPrimaryAction })
        // Sidor som öppnas i appens webbvy får en pil. Telefon och e-post öppnas av systemet.
        assertEquals(listOf(true, true, false, false, true), links.map { it.showsChevron })
    }

    @Test
    fun telefonUtanVisningsformVisarNumret() {
        val links = SourceLink.links(decode("""{"phone": {"number": "+46187279400", "display": null}}"""), kommunInfo = null)
        assertEquals("+46187279400", links.last().title)
    }

    @Test
    fun detSomSaknasVisasInte() {
        // Ingen källa, ingen sida för kommunen, trasiga adresser och telefon utan nummer.
        assertTrue(SourceLink.links(null, kommunInfo = null).isEmpty())
        val http = Source(
            id = "x", name = "X", url = "http://example.com", kommuner = emptyList(), testData = false,
            contact = SourceContact(phone = SourceContact.Phone(number = null, display = "018-727 94 00"), email = "inte en adress", page = "http://example.com/kontakt"),
        )
        assertTrue(SourceLink.links(http, kommunInfo = "http://example.com/avfall").isEmpty())
    }

    // Datakällor

    @Test
    fun kommunernaKallanTacker() {
        val source = Source(
            id = "x", name = "X", url = "https://example.com", testData = false,
            kommuner = listOf(Kommun(code = "1", name = "Avesta kommun"), Kommun(code = "2", name = "Hedemora kommun"), Kommun(code = "3", name = "Säters kommun")),
        )
        assertEquals("Avesta kommun, Hedemora kommun och Säters kommun", source.kommunerText)
        val one = Source(id = "y", name = "Y", url = "https://example.com", kommuner = listOf(Kommun(code = "0980", name = "Region Gotland")), testData = false)
        assertEquals("Region Gotland", one.kommunerText)
    }
}
