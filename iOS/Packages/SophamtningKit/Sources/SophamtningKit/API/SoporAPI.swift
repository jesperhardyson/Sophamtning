import Foundation

/// Det appen behöver av Sopor API v1.
public protocol SoporAPI: Sendable {
    func search(query: String, source: String?) async throws -> SearchResponse
    func areas(place: String) async throws -> SearchResponse
    func address(url: URL) async throws -> AddressResponse
    func sources() async throws -> SourcesResponse
}
