import Foundation

/// En inbjudan till ett hushåll. Nyckeln ligger efter `#` och skickas därför aldrig till någon server när länken öppnas.
public struct HouseholdInviteLink: Hashable, Sendable {
    public let householdId: String
    public let inviteToken: String
    public let householdKey: Data

    private static let host = "sopor.hardyson.se"
    private static let path = "/hushall"
    private static let version = "1"

    public init(householdId: String, inviteToken: String, householdKey: Data) {
        self.householdId = householdId
        self.inviteToken = inviteToken
        self.householdKey = householdKey
    }

    /// `nil` för allt som inte är en hel inbjudan i formatet appen känner till.
    public init?(url: URL) {
        guard url.scheme == "https", url.host(percentEncoded: false) == Self.host, url.path(percentEncoded: false) == Self.path || url.path(percentEncoded: false) == Self.path + "/",
              let fragment = url.fragment(percentEncoded: false) else { return nil }
        let parts = fragment.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == Self.version,
              Data(base64URL: parts[1])?.count == 16,
              Data(base64URL: parts[2])?.count == 32,
              let key = Data(base64URL: parts[3]), key.count == 32 else { return nil }
        self.init(householdId: parts[1], inviteToken: parts[2], householdKey: key)
    }

    public var url: URL {
        URL(string: "https://\(Self.host)\(Self.path)#\(Self.version).\(householdId).\(inviteToken).\(householdKey.base64URL)")!
    }
}

/// Länken är hemlig och skrivs aldrig ut i loggar.
extension HouseholdInviteLink: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "HouseholdInviteLink" }
    public var debugDescription: String { description }
}
