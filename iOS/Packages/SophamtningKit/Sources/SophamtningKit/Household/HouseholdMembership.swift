import Foundation

public enum HouseholdMembershipError: Error, Equatable, Sendable {
    /// Hushållet ligger kvar i iCloud, och hanteras där.
    case unsupported
    /// Inbjudan har gått ut eller gjorts ogiltig, eller så har hushållet avslutats.
    case inviteInvalid
    case full
    /// Jag är redan med i ett hushåll, som måste lämnas först.
    case alreadyMember
    /// Det finns inget hushåll.
    case noHousehold
    /// Inbjudan för flytten från iCloud har redan skapats, eller så är det för sent.
    case migrationUnavailable
    /// Allt annat: inget nät, serverfel eller nycklar som inte går att spara.
    case failed
}

/// Vilka som är med i hushållet: skapa, bjuda in, gå med, ta bort och avsluta.
public protocol HouseholdMembership: AnyObject, Sendable {
    func create(myName: String) async throws
    /// En ny inbjudan, som gäller i sju dagar och kan användas av flera.
    func invite() async throws -> URL
    /// Gör alla inbjudningar ogiltiga.
    func revokeInvites() async throws
    /// - Parameter replacing: lämnar hushållet jag är med i, men först när inbjudan har godtagits. Går något fel är jag kvar.
    func join(_ link: HouseholdInviteLink, myName: String?, replacing: Bool) async throws
    func remove(participantId: String) async throws
    func end() async throws
    /// Telefonens push-token, som skickas till hushållet när det finns ett.
    func registerDevice(token: String, environment: String) async
    /// Om inbjudan gäller hushållet jag redan är med i.
    func isCurrent(_ link: HouseholdInviteLink) -> Bool
    /// Om medlemmarna hanteras med det här gränssnittet. Falskt för ett hushåll som ligger kvar i iCloud.
    var managesMembers: Bool { get }
}

extension HouseholdMembership {
    public func join(_ link: HouseholdInviteLink, myName: String?) async throws {
        try await join(link, myName: myName, replacing: false)
    }
}
