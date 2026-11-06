import Foundation

/// En webbadress som appen får visa i sin egen webbvy. Bara `https` med en värd godkänns.
public struct WebLink: Identifiable, Hashable, Sendable {
    public let url: URL
    public var id: String { url.absoluteString }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else { return nil }
        self.url = url
    }
}
