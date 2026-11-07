import Foundation

/// Vad `/omraden` gav för orterna i söktexten.
public enum AreaLookup: Equatable, Sendable {
    /// `place` är orten som gav områdena.
    case found(place: String, areas: [SearchHit])
    /// Ingen ort gav områden, och inget anrop misslyckades.
    case notFound
    /// Inga områden, och minst ett anrop misslyckades. Det betyder inte att kommunen saknar områdesval.
    case failed

    /// Högst så många anrop till `/omraden` per söktext.
    public static let maxCalls = 3

    /// Frågar `/omraden` för söktextens orter i ordning, tills någon ger områden. Kastar bara vid avbrott.
    public static func run(query: String, api: any SoporAPI) async throws -> AreaLookup {
        try await run(candidates: SearchState.placeCandidates(in: query), api: api)
    }

    static func run(candidates: [String], api: any SoporAPI) async throws -> AreaLookup {
        var failed = false
        for place in candidates.prefix(maxCalls) {
            try Task.checkCancellation()
            do {
                let response = try await api.areas(place: place)
                if !response.addresses.isEmpty { return .found(place: place, areas: response.addresses) }
                if !response.failed.isEmpty { failed = true }
            } catch APIError.badRequest {
                // 400: orten gick inte att tolka. Inget tekniskt fel, bara inga områden för den.
                continue
            } catch {
                try Task.checkCancellation()
                failed = true
            }
        }
        try Task.checkCancellation()
        return failed ? .failed : .notFound
    }
}

/// Ett svar från adressökningen. `areas` är `nil` medan `/omraden` fortfarande frågas.
public struct SearchOutcome: Equatable, Sendable {
    public var state: SearchState
    public var areas: AreaLookup?

    public init(state: SearchState, areas: AreaLookup?) {
        self.state = state
        self.areas = areas
    }
}

public enum AddressSearch {
    /// Frågar `/sok` och, samtidigt, `/omraden` för orterna i söktexten. Träffarna lämnas direkt och väntar inte på
    /// områdena, som lämnas i ett andra svar. Vid noll träffar lämnas ett enda svar när områdena är klara. Inget lämnas
    /// efter avbrott, eller när ett nyare anrop har startat.
    @MainActor
    public static func run(query: String, source: String?, api: any SoporAPI, searches: LatestOnly, areaLookups: LatestOnly,
                           deliver: (SearchOutcome) -> Void) async {
        async let lookup = areaLookups.run { try await AreaLookup.run(query: query, api: api) }
        let state: SearchState
        do {
            guard let response = try await searches.run({ try await api.search(query: query, source: source) }) else { return }
            state = SearchState.from(response, query: query)
        } catch let error as APIError {
            guard !Task.isCancelled else { return }
            state = .failed(error)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        switch state {
        case .results:
            deliver(SearchOutcome(state: state, areas: nil))
            guard let areas = try? await lookup, !Task.isCancelled else { return }
            deliver(SearchOutcome(state: state, areas: areas))
        case .noHits:
            guard let areas = try? await lookup, !Task.isCancelled else { return }
            deliver(SearchOutcome(state: state, areas: areas))
        case .idle, .searching, .sourcesFailed, .failed:
            deliver(SearchOutcome(state: state, areas: nil))
        }
    }
}
