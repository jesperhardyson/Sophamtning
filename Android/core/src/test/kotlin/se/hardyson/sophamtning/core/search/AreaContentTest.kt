package se.hardyson.sophamtning.core.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import se.hardyson.sophamtning.core.api.ApiDecoding
import se.hardyson.sophamtning.core.api.AreaDetails
import se.hardyson.sophamtning.core.api.AreaSource
import se.hardyson.sophamtning.core.api.SearchHit
import se.hardyson.sophamtning.core.api.SearchResponse
import se.hardyson.sophamtning.core.api.fixture

private fun areas(name: String): SearchResponse = ApiDecoding.searchResponse(fixture(name))

private fun areaHit(detail: String? = "Måndag, udda vecka · Område 1", area: AreaDetails?) = SearchHit(
    id = "trakt-1", street = "Askön, Nyhyttan m.fl.", locality = "", kommun = "Avesta kommun", source = "avesta", detail = detail,
    selection = "area", notice = null, areasUrl = null, url = "https://sopor.hardyson.se/api/v1/adress/avesta/trakt-1", area = area,
)

class AreaDecodingTest {
    @Test
    fun detaljerOchKallorAvkodas() {
        val response = areas("omraden-detaljer")
        val first = assertNotNull(response.addresses.first().area)
        assertEquals("Måndag, udda vecka", first.day)
        assertEquals("Område 1", first.label)
        assertEquals(listOf("Askön", "Nyhyttan"), first.places.take(2))
        assertTrue(first.otherDays.isEmpty())
        assertTrue(first.searchTerms.contains("trakt 1"))
        assertEquals(1, response.addresses.first { it.id == "trakt-7" }.area?.otherDays?.size)
        assertEquals(
            listOf(
                AreaSource(
                    id = "avesta",
                    name = "Avesta Vatten och Avfall",
                    explanation = "Avesta Vatten publicerar sophämtningen per område, men inte vilka adresser som hör till vilket område.",
                    help = "Osäker? Fråga Avesta Vatten på 0226-64 55 00.",
                ),
            ),
            response.sources,
        )
    }

    @Test
    fun aldreSvarUtanFaltenArInteEttFel() {
        val response = areas("omraden")
        assertEquals(10, response.addresses.size)
        assertTrue(response.addresses.all { it.area == null })
        assertTrue(response.sources.isEmpty())
    }

    @Test
    fun trasigaFaltFallerInteOmradena() {
        val json = ApiDecoding.json.parseToJsonElement(fixture("omraden-detaljer")).jsonObject
        val hits = json.getValue("addresses").jsonArray.map { it.jsonObject }.toMutableList()
        hits[0] = JsonObject(hits[0] + ("area" to JsonPrimitive("trasig")))
        hits[1] = JsonObject(
            hits[1] + ("area" to buildJsonObject {
                put("day", 3)
                put("label", JsonNull)
                put("places", "Rosse")
                put("otherDays", JsonNull)
            }),
        )
        hits[2] = JsonObject(hits[2] + ("area" to JsonNull))
        val sources = JsonArray(
            listOf(
                buildJsonObject { put("id", "avesta"); put("name", "Avesta"); put("explanation", 5); put("help", JsonNull) },
                buildJsonObject { put("name", "utan id") },
            ),
        )
        val changed = JsonObject(json + ("addresses" to JsonArray(hits)) + ("sources" to sources))
        val response = ApiDecoding.searchResponse(changed)
        assertEquals(10, response.addresses.size)
        assertNull(response.addresses[0].area)
        assertEquals(AreaDetails(day = "", label = null, places = emptyList()), response.addresses[1].area)
        assertNull(response.addresses[2].area)
        assertEquals(listOf(AreaSource(id = "avesta", name = "Avesta", explanation = null, help = null)), response.sources)

        val broken = ApiDecoding.searchResponse(JsonObject(changed + ("sources" to JsonPrimitive("trasig"))))
        assertTrue(broken.sources.isEmpty())
        assertEquals(10, broken.addresses.size)
    }
}

class AreaRowContentTest {
    @Test
    fun radenVisarEtikettDagOchKortaPlatser() {
        val row = AreaRowContent.make(areas("omraden-detaljer").addresses.first())
        assertEquals("Askön, Nyhyttan m.fl.", row.title)
        assertEquals("Område 1", row.label)
        assertEquals("Måndag, udda vecka", row.day)
        assertEquals("Askön, Nyhyttan, Klintbo, Snickarbo m.fl.", row.places)
        assertTrue(row.allPlaces?.startsWith("Askön, Nyhyttan, Klintbo, Snickarbo, Knallasbenning") == true)
        assertTrue(row.allPlaces?.endsWith("Högbo och Rutbo") == true)
        assertTrue(row.otherDays.isEmpty())
        assertTrue(row.detailed)
        assertTrue(row.hidesPlaces)
        assertEquals("Visa alla 18 platser", row.showAllPlacesText)
    }

    @Test
    fun knappenIBekraftelsenFallerUtOchIhop() {
        val row = AreaRowContent.make(areas("omraden-detaljer").addresses.first())
        assertEquals("Visa alla 18 platser", row.placesToggleText(expanded = false))
        assertEquals("Visa färre platser", row.placesToggleText(expanded = true))
    }

    @Test
    fun fåPlatserVisasAllaUtanMfl() {
        val three = AreaRowContent.make(areaHit(area = AreaDetails(day = "Onsdag, udda vecka", label = "Område 3", places = listOf("Fors", "Nordanö", "Brogård"))))
        assertEquals("Fors, Nordanö, Brogård", three.places)
        assertEquals("Fors, Nordanö och Brogård", three.allPlaces)
        // En enda plats till ger ingen "m.fl.".
        val five = AreaRowContent.make(areaHit(area = AreaDetails(day = "Dag", label = null, places = listOf("A", "B", "C", "D", "E"))))
        assertEquals("A, B, C, D, E", five.places)
        assertFalse(five.hidesPlaces)
        val six = AreaRowContent.make(areaHit(area = AreaDetails(day = "Dag", label = null, places = listOf("A", "B", "C", "D", "E", "F"))))
        assertEquals("A, B, C, D m.fl.", six.places)
    }

    @Test
    fun andraDagarVisasNarDeFinns() {
        val row = AreaRowContent.make(areas("omraden-detaljer").addresses.first { it.id == "trakt-7" })
        assertEquals(listOf("Till exempel Stallgatan och Storbogatan (måndag, udda vecka) och Bodgatan (onsdag, jämn vecka)."), row.otherDays)
        assertTrue(
            row.accessibilityLabel.endsWith(
                "Vissa gator har en annan hämtdag. Till exempel Stallgatan och Storbogatan (måndag, udda vecka) och Bodgatan (onsdag, jämn vecka).",
            ),
        )
    }

    @Test
    fun utanDetaljerVisasDagensRad() {
        val row = AreaRowContent.make(areaHit(area = null))
        assertEquals(
            AreaRowContent(title = "Askön, Nyhyttan m.fl.", label = null, day = "Måndag, udda vecka · Område 1", places = null, allPlaces = null, otherDays = emptyList()),
            row,
        )
        // En tom dag räknas som saknade detaljer, så att raden aldrig blir tom.
        val empty = AreaRowContent.make(areaHit(area = AreaDetails(day = "  ", label = "Område 1", places = listOf("Askön"))))
        assertEquals("Måndag, udda vecka · Område 1", empty.day)
        assertNull(empty.label)
    }

    @Test
    fun tomEtikettOchTommaPlatserVisasInte() {
        val row = AreaRowContent.make(areaHit(area = AreaDetails(day = "Fredag", label = " ", places = listOf(" ", ""), otherDays = listOf(""))))
        assertNull(row.label)
        assertNull(row.places)
        assertNull(row.allPlaces)
        assertTrue(row.otherDays.isEmpty())
    }

    @Test
    fun voiceOverLaserAllaPlatser() {
        val row = AreaRowContent.make(areaHit(area = AreaDetails(day = "Måndag, udda vecka", label = "Område 1", places = listOf("A", "B", "C", "D", "E", "F"))))
        assertEquals("Askön, Nyhyttan m.fl., Område 1, Måndag, udda vecka. Platser: A, B, C, D, E och F.", row.accessibilityLabel)
        val plain = AreaRowContent.make(areaHit(area = null))
        assertEquals("Askön, Nyhyttan m.fl., Måndag, udda vecka · Område 1.", plain.accessibilityLabel)
    }
}

class AreaSourceNoteTest {
    @Test
    fun forklaringOchHjalpradMedTelefonlank() {
        val notes = AreaSourceNote.notes(areas("omraden-detaljer").sources)
        assertEquals(1, notes.size)
        val note = notes.first()
        assertEquals("Avesta Vatten publicerar sophämtningen per område, men inte vilka adresser som hör till vilket område.", note.explanation)
        val help = assertNotNull(note.help)
        // Texten står som källan skrev den.
        assertEquals("Osäker? Fråga Avesta Vatten på 0226-64 55 00.", help.text)
        assertEquals(1, help.links.size)
        assertEquals("tel:0226645500", help.links.first().url)
        assertEquals("0226-64 55 00", help.text.substring(help.links.first().range))
    }

    @Test
    fun utanNummerArTextenOforandrad() {
        val help = AreaSourceNote.linkingPhoneNumbers("Fråga kommunen.")
        assertEquals("Fråga kommunen.", help.text)
        assertTrue(help.links.isEmpty())
    }

    @Test
    fun tommaKallorGerIngenForklaring() {
        assertTrue(AreaSourceNote.notes(emptyList()).isEmpty())
        assertTrue(AreaSourceNote.notes(listOf(AreaSource(id = "a", name = "A", explanation = " ", help = null))).isEmpty())
        val twice = AreaSourceNote.notes(
            listOf(AreaSource(id = "a", name = "A", explanation = "X", help = null), AreaSource(id = "a", name = "A", explanation = "X", help = null)),
        )
        assertEquals(1, twice.size)
        assertNull(twice.first().help)
    }

    @Test
    fun telLankBehallerPlus() {
        assertEquals("tel:+46226645500", AreaSourceNote.telURL("+46 226-64 55 00"))
        assertNull(AreaSourceNote.telURL("12"))
    }
}

class AreaWarningTest {
    private val avesta = AreaSource(id = "avesta", name = "Avesta Vatten", explanation = "Avesta publicerar per område.", help = "Fråga på 0226-64 55 00.")
    private val notice = "Adresser publiceras inte."

    @Test
    fun forklaringenVisasOrdagrantOchNoticeVisasInte() {
        val warning = AreaWarning.make(notice = notice, notes = AreaSourceNote.notes(listOf(avesta)))
        assertEquals(listOf("Avesta publicerar per område."), warning.explanations.map { it.text })
        assertEquals(1, warning.helps.size)
        assertFalse(warning.explanations.map { it.text }.contains(notice))
        assertTrue(warning.showsConsequence)
    }

    @Test
    fun saknasForklaringenVisasNotice() {
        val onlyHelp = AreaSource(id = "avesta", name = "Avesta Vatten", explanation = null, help = "Fråga på 0226-64 55 00.")
        val warning = AreaWarning.make(notice = notice, notes = AreaSourceNote.notes(listOf(onlyHelp)))
        assertEquals(listOf(notice), warning.explanations.map { it.text })
        assertEquals(1, warning.helps.size)
    }

    @Test
    fun utanKallorVisasNoticeEnsam() {
        val warning = AreaWarning.make(notice = notice, notes = emptyList())
        assertEquals(listOf(notice), warning.explanations.map { it.text })
        assertTrue(warning.helps.isEmpty())
    }

    @Test
    fun utanNoticeOchKallorFinnsKortetAndaMedKonsekvensen() {
        for (missing in listOf(null, "  ")) {
            val warning = AreaWarning.make(notice = missing, notes = emptyList())
            assertTrue(warning.explanations.isEmpty(), "notice $missing")
            assertTrue(warning.helps.isEmpty(), "notice $missing")
            assertTrue(warning.showsConsequence, "notice $missing")
        }
        assertEquals("Du väljer området själv", AreaWarning.title)
        assertEquals("Väljer du fel område kan du missa din tömning.", AreaWarning.consequence)
    }

    @Test
    fun konsekvensenStarInteTvaGangerNarNoticeRedanHarDen() {
        val full = "Adresser publiceras inte. ${AreaWarning.consequence}"
        val warning = AreaWarning.make(notice = full, notes = emptyList())
        assertEquals(listOf(full), warning.explanations.map { it.text })
        assertFalse(warning.showsConsequence)
    }

    @Test
    fun flerKallorVisasMedNamn() {
        val other = AreaSource(id = "sater", name = "Säter", explanation = "Säter publicerar per område.", help = null)
        val warning = AreaWarning.make(notice = null, notes = AreaSourceNote.notes(listOf(avesta, other)))
        assertEquals(listOf("Avesta Vatten", "Säter"), warning.explanations.map { it.name })
        val single = AreaWarning.make(notice = null, notes = AreaSourceNote.notes(listOf(avesta)))
        assertNull(single.explanations.first().name)
    }

    @Test
    fun postnummerOchDatumBlirInteTelefonlankar() {
        for (text in listOf("Skicka till Box 123, 791 83 Falun.", "Nya tider från 2026-11-23.", "Öppet 08-16 vardagar.")) {
            assertEquals(emptyList(), AreaSourceNote.linkingPhoneNumbers(text).links, text)
        }
        val help = AreaSourceNote.linkingPhoneNumbers("Ring 0226-64 55 00 eller +46 226-64 55 00.")
        assertEquals(listOf("tel:0226645500", "tel:+46226645500"), help.links.map { it.url })
    }
}
