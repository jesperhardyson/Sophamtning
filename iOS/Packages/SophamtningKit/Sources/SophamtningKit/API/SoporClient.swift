import Foundation

/// Klient mot Sopor API v1. Adresser hämtas från den sparade `url:en` oförändrad.
public struct SoporClient: SoporAPI {
    static let baseURL = "https://sopor.hardyson.se/api/v1"
    static let timeout: TimeInterval = 15

    private let session: URLSession
    private let userAgent: String

    public init(session: URLSession = .shared, version: String) {
        self.session = session
        self.userAgent = "Sophamtning-iOS/\(version)"
    }

    public func search(query: String, source: String?) async throws -> SearchResponse {
        var items = [("q", query)]
        if let source { items.append(("kalla", source)) }
        return try await get(Self.endpoint("sok", items))
    }

    public func areas(place: String) async throws -> SearchResponse {
        try await get(Self.endpoint("omraden", [("plats", place)]))
    }

    public func areas(place: String, lastEmptied: DayDate) async throws -> SearchResponse {
        try await get(Self.endpoint("omraden", [("plats", place), ("tomning", lastEmptied.iso)]))
    }

    public func address(url: URL) async throws -> AddressResponse {
        try await get(url)
    }

    public func sources() async throws -> SourcesResponse {
        let all: SourcesResponse = try await get(Self.endpoint("kallor", []))
        return SourcesResponse(sources: all.sources.filter { !$0.testData }, fractions: all.fractions)
    }

    // MARK: - Internt

    /// Bygger adressen för hand så att allt utom oreserverade tecken procentkodas, även `+` och `,`.
    private static func endpoint(_ path: String, _ items: [(String, String)]) -> URL {
        var text = "\(baseURL)/\(path)"
        if !items.isEmpty {
            text += "?" + items.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
        }
        return URL(string: text)!
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private func get<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw APIError.network
        }

        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw APIError.unexpected(0)
        }
        switch status {
        case 200..<300:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw APIError.unexpected(status)
            }
        case 400: throw APIError.badRequest
        case 404: throw APIError.notFound
        case 502: throw APIError.sourceUnavailable
        default: throw APIError.unexpected(status)
        }
    }
}
