package se.hardyson.sophamtning.core.kommun

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import se.hardyson.sophamtning.core.api.Kommun
import se.hardyson.sophamtning.core.api.Source

class KommunCheckerTest {
    private val index = PlaceIndex.load()

    /** Kommunnamn som källorna använder när de skiljer sig från ortlistan. */
    private val sourceNames = mapOf("0980" to "Gotlands kommun")

    /** [covered] är kommunkod till källans id. */
    private fun sources(covered: Map<String, String>): List<Source> {
        val byId = linkedMapOf<String, MutableList<Kommun>>()
        for ((code, id) in covered.toSortedMap()) {
            byId.getOrPut(id) { mutableListOf() } += Kommun(code = code, name = sourceNames[code] ?: index.kommunName(code) ?: code)
        }
        return byId.map { (id, kommuner) -> Source(id = id, name = id, url = "https://example.com/$id", kommuner = kommuner, testData = false) }
    }

    private fun check(q: String, covered: Map<String, String>) = KommunChecker.check(q, index, sources(covered))

    private fun row(code: String, name: String, sourceId: String? = null) = KommunRow(code = code, name = name, sourceId = sourceId)

    @Test
    fun tomText() {
        assertEquals(KommunAnswer.Empty, check("  ", emptyMap()))
        assertEquals(KommunAnswer.Empty, check("k", emptyMap()))
        assertEquals(KommunAnswer.Empty, check(" k ", emptyMap()))
    }

    @Test
    fun kommunnamnGarForeOrt() {
        val answer = assertIs<KommunAnswer.Covered>(check("stockholm", mapOf("0180" to "stockholm-kalla")))
        assertNull(answer.viaPlace)
        assertEquals("Stockholms kommun", answer.row.name)
    }

    @Test
    fun moraGallerKommunenInteOrten() {
        // Orten Mora finns också i Säter och Eskilstuna, men kommunnamnet går först.
        assertEquals(KommunAnswer.Covered(row("2062", "Mora kommun", "mora-kalla"), viaPlace = null), check("mora", mapOf("2062" to "mora-kalla")))
        assertEquals(KommunAnswer.NotYet(row("2062", "Mora kommun")), check("mora", emptyMap()))
    }

    @Test
    fun medOchUtanKommunOchGenitiv() {
        for (q in listOf("örebro", "Örebro kommun", "orebro", "ÖREBROS", "  Örebros kommun ")) {
            assertIs<KommunAnswer.Covered>(check(q, mapOf("1880" to "orebro")), q)
        }
    }

    @Test
    fun ortITackKommun() {
        assertEquals(
            KommunAnswer.Covered(KommunRow(code = "2084", name = "Avesta kommun", sourceId = "avesta"), viaPlace = "Krylbo"),
            check("krylbo", mapOf("2084" to "avesta")),
        )
    }

    @Test
    fun ortStavningenKommerFranListan() {
        assertEquals("Krylbo", assertIs<KommunAnswer.Covered>(check("KRYLBO", mapOf("2084" to "avesta"))).viaPlace)
    }

    @Test
    fun ortIOtackKommunGerNotYetMedRad() {
        assertEquals(KommunAnswer.NotYet(row("2084", "Avesta kommun")), check("krylbo", emptyMap()))
    }

    @Test
    fun inteAn() {
        assertEquals(KommunAnswer.NotYet(row("0123", "Järfälla kommun")), check("järfälla", emptyMap()))
    }

    @Test
    fun ortIFleraKommuner() {
        val answer = assertIs<KommunAnswer.Multiple>(check("almvik", mapOf("0181" to "telge")))
        assertEquals("Almvik", answer.place)
        assertEquals(2, answer.rows.size)
        assertEquals("telge", answer.rows.first { it.code == "0181" }.sourceId)
        assertNull(answer.rows.first { it.code != "0181" }.sourceId)
    }

    @Test
    fun forstaKallanVinnerNarFleraTackerSammaKommun() {
        val k = listOf(Kommun(code = "1880", name = "Örebro kommun"))
        val list = listOf(
            Source(id = "a", name = "A", url = "https://example.com", kommuner = k, testData = false),
            Source(id = "b", name = "B", url = "https://example.com", kommuner = k, testData = false),
        )
        assertEquals(KommunAnswer.Covered(row("1880", "Örebro kommun", "a"), viaPlace = null), KommunChecker.check("örebro", index, list))
    }

    @Test
    fun forslagKortastForstHogstFem() {
        assertEquals(KommunAnswer.Suggestions(listOf("Krylbo")), check("kry", emptyMap()))
        val s = assertIs<KommunAnswer.Suggestions>(check("sk", emptyMap()), "förväntade förslag").suggestions
        assertEquals(5, s.size)
        assertEquals(s.map { it.length }.sorted(), s.map { it.length })
        assertTrue(s.all { it.lowercase().startsWith("sk") })
    }

    @Test
    fun okandPlats() {
        assertEquals(KommunAnswer.Unknown, check("xyzby", emptyMap()))
    }

    @Test
    fun utanKallistaAldrigFinnsInte() {
        assertEquals(KommunAnswer.Unavailable, KommunChecker.check("järfälla", index, null))
        assertEquals(KommunAnswer.Unavailable, KommunChecker.check("krylbo", index, null))
        assertEquals(KommunAnswer.Unavailable, KommunChecker.check("almvik", index, null))
        assertEquals(KommunAnswer.Suggestions(listOf("Krylbo")), KommunChecker.check("kry", index, null))
        assertEquals(KommunAnswer.Unknown, KommunChecker.check("xyzby", index, null))
        assertEquals(KommunAnswer.Empty, KommunChecker.check(" ", index, null))
    }

    @Test
    fun tomKallistaArInteDetSammaSomSaknad() {
        assertEquals(KommunAnswer.NotYet(row("0123", "Järfälla kommun")), KommunChecker.check("järfälla", index, emptyList()))
    }

    private fun codes(a: KommunAnswer): List<String> = when (a) {
        is KommunAnswer.Covered -> listOf(a.row.code)
        is KommunAnswer.NotYet -> listOf(a.row.code)
        is KommunAnswer.Multiple -> a.rows.map { it.code }.sorted()
        else -> emptyList()
    }

    @Test
    fun gotlandHittasMedOchUtanRegionOchKommun() {
        for (q in listOf("gotland", "Gotlands kommun", "region gotland", "Region Gotland")) {
            assertEquals(KommunAnswer.Covered(row("0980", "Gotlands kommun", "gotland"), viaPlace = null), check(q, mapOf("0980" to "gotland")), q)
            assertEquals(KommunAnswer.NotYet(row("0980", "Region Gotland")), check(q, emptyMap()), q)
        }
    }

    @Test
    fun haboUtanPrickarGerHaboOchHabo() {
        val answer = assertIs<KommunAnswer.Multiple>(check("habo", emptyMap()))
        assertEquals("habo", answer.place)
        assertEquals(listOf("0305", "0643"), answer.rows.map { it.code }.sorted())
    }

    @Test
    fun haboMedPrickarGerBaraHabo() {
        assertEquals(KommunAnswer.NotYet(row("0305", "Håbo kommun")), check("håbo", emptyMap()))
        assertEquals(KommunAnswer.NotYet(row("0305", "Håbo kommun")), check("Håbo kommun", emptyMap()))
    }

    @Test
    fun marstaUtanPrickarGerBadaMarstaOchMarsta() {
        val answer = assertIs<KommunAnswer.Multiple>(check("marsta", emptyMap()))
        assertEquals("marsta", answer.place)
        assertEquals(listOf("0191", "0380"), answer.rows.map { it.code }.sorted())
    }

    @Test
    fun marstaMedPrickarGerBaraMarsta() {
        assertEquals(KommunAnswer.NotYet(row("0191", "Sigtuna kommun")), check("märsta", emptyMap()))
    }

    @Test
    fun albyOchAlbyGerAllaKommuner() {
        val answer = assertIs<KommunAnswer.Multiple>(check("alby", emptyMap()))
        assertEquals("alby", answer.place)
        val alby = codes(check("alby", emptyMap())).toSet()
        assertEquals(answer.rows.size, alby.size)
        val a = index.place("Alby")?.codes.orEmpty()
        val b = index.place("Älby")?.codes.orEmpty()
        assertEquals(alby, (a + b).toSet())
        assertTrue(b.isNotEmpty() && a.isNotEmpty())
    }

    @Test
    fun forslagOmfattarKommuner() {
        assertEquals(KommunAnswer.Suggestions(listOf("Huddinge", "Huddunge")), check("hudd", emptyMap()))
        val s = assertIs<KommunAnswer.Suggestions>(check("nac", emptyMap())).suggestions
        assertEquals("Nacka", s.first())
        assertTrue(s.size <= 5)
        assertEquals(s.size, s.toSet().size)
        val g = assertIs<KommunAnswer.Suggestions>(check("gotl", emptyMap())).suggestions
        assertTrue(g.contains("Gotland"))
    }

    @Test
    fun dataMatcharFilen() {
        val i = PlaceIndex.load()
        assertEquals(290, i.kommunCount)
        assertEquals(6524, i.placeCount)
    }

    @Test
    fun egetIndexUtanFil() {
        val i = PlaceIndex(kommuner = mapOf("0001" to "Testby kommun"), orter = mapOf("Lilla" to listOf("0001")))
        assertEquals(KommunAnswer.NotYet(row("0001", "Testby kommun")), KommunChecker.check("lilla", i, emptyList()))
    }

    // Tillagt på Android: å skrivet som a och en ring (NFD) ger samma svar som å, som när Swift jämför tecken.
    @Test
    fun sammansattAaGerSammaSvar() {
        assertEquals(KommunAnswer.NotYet(row("0305", "Håbo kommun")), check("håbo", emptyMap()))
        assertFalse(check("håbo", emptyMap()) is KommunAnswer.Multiple)
    }
}
