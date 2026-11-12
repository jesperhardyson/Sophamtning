import Foundation

/// Knappen **Utställt** i påminnelsenotisen. Notisen bär adressens nyckel och tömningens datum, så att knappen kan markera
/// tömningen som utställd utan att appen öppnas, på samma sätt som **Klart** i Live Activityn.
public enum PlacedOutNotification {
    /// Notiskategorin som har knappen. Alla påminnelsenotiser, också reserven, har den.
    public static let categoryIdentifier = "paminnelse"
    public static let actionIdentifier = "utstallt"
    public static let actionTitle = "Utställt"

    private static let sourceKey = "kalla"
    private static let idKey = "adressId"
    private static let dateKey = "datum"

    /// Det som notisen bär. Adress-id:t sparas som det är och byggs aldrig om.
    public static func userInfo(key: AddressKey, date: DayDate) -> [String: Any] {
        [sourceKey: key.source, idKey: key.id, dateKey: date.iso]
    }

    /// Tömningen som notisen gäller, eller `nil` för en notis som saknar något av fälten.
    public static func entry(from userInfo: [AnyHashable: Any]) -> PlacedOut? {
        guard let source = userInfo[sourceKey] as? String,
              let id = userInfo[idKey] as? String,
              let iso = userInfo[dateKey] as? String,
              let date = DayDate(iso)
        else { return nil }
        return PlacedOut(key: AddressKey(source: source, id: id), date: date)
    }
}
