import Foundation

/// Det appen behöver av Sopor API v1.
public protocol SoporAPI: Sendable {
    func search(query: String, source: String?) async throws -> SearchResponse
    func areas(place: String) async throws -> SearchResponse
    /// Områdena som hade hämtning `lastEmptied`, med tömningarna kring datumet.
    func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse
    func address(url: URL) async throws -> AddressResponse
    func sources() async throws -> SourcesResponse
}
