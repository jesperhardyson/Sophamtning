package se.hardyson.sophamtning.core.storage

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun address(id: String, primary: Boolean = false, added: Long) =
    savedAddress(key = AddressKey("orebro", id), isPrimary = primary, addedAt = Instant.ofEpochSecond(added))

class AddressListTest {
    @Test
    fun forstaAdressenBlirHuvudadress() {
        val list = AddressList.add(address("a", added = 1), emptyList())
        assertEquals(listOf("a"), list.map { it.key.id })
        assertTrue(list[0].isPrimary)
    }

    @Test
    fun nastaAdressBlirInteHuvudadress() {
        val list = AddressList.add(address("b", primary = true, added = 2), AddressList.add(address("a", added = 1), emptyList()))
        assertEquals(listOf("a", "b"), list.map { it.key.id })
        assertEquals(listOf(true, false), list.map { it.isPrimary })
    }

    @Test
    fun enAdressSomRedanFinnsLaggsInteTillIgen() {
        val first = AddressList.add(address("a", added = 1), emptyList())
        assertEquals(first, AddressList.add(address("a", added = 5), first))
    }

    @Test
    fun borttagenHuvudadressGerAldstaKvarvarande() {
        val list = listOf(address("a", primary = true, added = 30), address("b", added = 20), address("c", added = 10))
        val result = AddressList.remove(list[0].key, list)
        assertEquals(listOf("b", "c"), result.map { it.key.id })
        assertEquals(listOf(false, true), result.map { it.isPrimary })
    }

    @Test
    fun borttagningAvEnVanligAdressBehallerHuvudadressen() {
        val list = listOf(address("a", primary = true, added = 30), address("b", added = 20))
        val result = AddressList.remove(list[1].key, list)
        assertEquals(listOf("a"), result.map { it.key.id })
        assertTrue(result[0].isPrimary)
    }

    @Test
    fun endastEnHuvudadress() {
        val list = listOf(address("a", primary = true, added = 1), address("b", added = 2), address("c", added = 3))
        val result = AddressList.setPrimary(list[2].key, list)
        assertEquals(listOf(false, false, true), result.map { it.isPrimary })
    }

    @Test
    fun okandNyckelAndrarInteHuvudadressen() {
        val list = listOf(address("a", primary = true, added = 1), address("b", added = 2))
        assertEquals(list, AddressList.setPrimary(AddressKey("x", "y"), list))
    }

    @Test
    fun borttagningAvSistaAdressenGerTomLista() {
        val list = listOf(address("a", primary = true, added = 1))
        assertTrue(AddressList.remove(list[0].key, list).isEmpty())
    }

    @Test
    fun listaUtanHuvudadressFarAldstaSomHuvudadress() {
        val list = AddressList.add(address("c", added = 3), listOf(address("a", added = 2), address("b", added = 1)))
        assertEquals(listOf("b"), list.filter { it.isPrimary }.map { it.key.id })
    }

    @Test
    fun namnetTrimmasOchKravsInteVaraTomt() {
        assertEquals("Stugan", AddressList.validName("  Stugan "))
        assertNull(AddressList.validName(""))
        assertNull(AddressList.validName("   \n "))
        assertNull(AddressList.validName("  "))
    }

    @Test
    fun namnetArHogst60Tecken() {
        assertNotNull(AddressList.validName("å".repeat(60)))
        assertNull(AddressList.validName("å".repeat(61)))
        // Ett tecken som består av flera delar räknas som ett, som på iOS.
        assertNotNull(AddressList.validName("👨‍👩‍👧".repeat(60)))
    }

    @Test
    fun nyttNamnAndrarBaraDenAdressen() {
        val list = listOf(address("a", primary = true, added = 1), address("b", added = 2))
        val result = AddressList.rename(list[1].key, " Stugan ", list)
        assertEquals(listOf(list[0].displayName, "Stugan"), result.map { it.displayName })
        assertEquals(listOf(true, false), result.map { it.isPrimary })
    }

    @Test
    fun ogiltigtNamnEllerOkandNyckelAndrarInget() {
        val list = listOf(address("a", primary = true, added = 1))
        assertEquals(list, AddressList.rename(list[0].key, "  ", list))
        assertEquals(list, AddressList.rename(AddressKey("x", "y"), "Stugan", list))
    }
}
