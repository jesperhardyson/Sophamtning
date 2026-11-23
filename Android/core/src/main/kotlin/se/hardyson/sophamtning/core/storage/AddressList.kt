package se.hardyson.sophamtning.core.storage

/** Rena regler för listan med sparade adresser. Listan har alltid unika nycklar och, om den inte är tom, exakt en huvudadress. */
object AddressList {
    const val MAX_NAME_LENGTH = 60

    /** Lägger till adressen sist. Finns nyckeln redan ändras ingenting. Den första adressen blir huvudadress. */
    fun add(address: SavedAddress, list: List<SavedAddress>): List<SavedAddress> {
        if (list.any { it.key == address.key }) return list
        return normalized(list + address.copy(isPrimary = false))
    }

    /** Tar bort adressen. Var den huvudadress blir den äldsta kvarvarande (`addedAt`) det. */
    fun remove(key: AddressKey, list: List<SavedAddress>) = normalized(list.filter { it.key != key })

    /** Gör adressen till huvudadress och alla andra till vanliga. En okänd nyckel ändrar ingenting. */
    fun setPrimary(key: AddressKey, list: List<SavedAddress>): List<SavedAddress> {
        if (list.none { it.key == key }) return list
        return list.map { it.copy(isPrimary = it.key == key) }
    }

    /** Namnet utan omgivande blanksteg, eller `null` när det är tomt eller längre än 60 tecken. */
    fun validName(raw: String): String? {
        val name = raw.trim { it.isWhitespace() }
        // Räknar tecken som användaren ser dem, som `count` på iOS.
        val length = java.text.BreakIterator.getCharacterInstance().run {
            setText(name)
            var count = 0
            while (next() != java.text.BreakIterator.DONE) count++
            count
        }
        return if (name.isEmpty() || length > MAX_NAME_LENGTH) null else name
    }

    /** Byter namn på adressen. Ett ogiltigt namn eller en okänd nyckel ändrar ingenting. */
    fun rename(key: AddressKey, name: String, list: List<SavedAddress>): List<SavedAddress> {
        val valid = validName(name) ?: return list
        if (list.none { it.key == key }) return list
        return list.map { if (it.key == key) it.copy(displayName = valid) else it }
    }

    /** Ser till att exakt en adress är huvudadress. Behåller den första som redan är det, annars blir den äldsta det. */
    private fun normalized(list: List<SavedAddress>): List<SavedAddress> {
        if (list.isEmpty()) return list
        val primary = list.firstOrNull { it.isPrimary } ?: list.minBy { it.addedAt }
        return setPrimary(primary.key, list)
    }
}
