import Foundation

/// Valen för en adress i snabbmenyn och bland VoiceOver-åtgärderna, i samma ordning som i adressvyn.
public enum AddressAction: Hashable, Sendable {
    case rename, makePrimary, notifications, liveActivity, remove

    /// Gör till huvudadress finns bara för de andra adresserna, och Live Activity bara för huvudadressen.
    public static func choices(isPrimary: Bool) -> [AddressAction] {
        var choices: [AddressAction] = [.rename]
        if !isPrimary { choices.append(.makePrimary) }
        choices.append(.notifications)
        if isPrimary { choices.append(.liveActivity) }
        choices.append(.remove)
        return choices
    }
}
