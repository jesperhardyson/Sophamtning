import Foundation

/// Rena regler för listan med sparade adresser. Listan har alltid unika nycklar och, om den
/// inte är tom, exakt en huvudadress.
public enum AddressList {
    /// Lägger till adressen sist. Finns nyckeln redan ändras ingenting. Den första adressen
    /// blir huvudadress, och en senare adress blir det aldrig av sig själv.
    public static func add(_ address: SavedAddress, to list: [SavedAddress]) -> [SavedAddress] {
        guard !list.contains(where: { $0.key == address.key }) else { return list }
        var added = address
        added.isPrimary = false
        return normalized(list + [added])
    }

    /// Tar bort adressen. Var den huvudadress blir den äldsta kvarvarande (`addedAt`) det.
    public static func remove(_ key: AddressKey, from list: [SavedAddress]) -> [SavedAddress] {
        normalized(list.filter { $0.key != key })
    }

    /// Gör adressen till huvudadress och alla andra till vanliga. En okänd nyckel ändrar ingenting.
    public static func setPrimary(_ key: AddressKey, in list: [SavedAddress]) -> [SavedAddress] {
        guard list.contains(where: { $0.key == key }) else { return list }
        return list.map { address in
            var copy = address
            copy.isPrimary = address.key == key
            return copy
        }
    }

    /// Ser till att exakt en adress är huvudadress. Behåller den första som redan är det,
    /// annars blir den äldsta det.
    private static func normalized(_ list: [SavedAddress]) -> [SavedAddress] {
        guard !list.isEmpty else { return list }
        let primary = list.first(where: \.isPrimary) ?? list.min { $0.addedAt < $1.addedAt }!
        return setPrimary(primary.key, in: list)
    }
}
