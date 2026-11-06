import Foundation

/// Fel från Sopor API:t. Klienten mappar på HTTP-status, inte på felkoden i svaret.
public enum APIError: Error, Equatable, Codable, Sendable {
    /// 400: ogiltig förfrågan.
    case badRequest
    /// 404: adressen eller källan finns inte.
    case notFound
    /// 502: källan svarar inte just nu. Behåll det senast lyckade svaret.
    case sourceUnavailable
    /// Nätverksfel, till exempel tidsgräns eller ingen uppkoppling.
    case network
    /// Alla andra statuskoder, och svar som inte går att tolka (då med status 200).
    case unexpected(Int)
}
