import Foundation
import Testing
@testable import SophamtningKit

/// Kontraktstester mot produktions-API:t. Körs bara med `SOPOR_LIVE=1`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SOPOR_LIVE"] == "1"))
struct LiveAPITests {
    let client = SoporClient(version: "1.0")

    @Test func avkodarKallor() async throws {
        let r = try await client.sources()
        #expect(!r.sources.isEmpty)
        #expect(!r.fractions.isEmpty)
    }

    @Test func avkodarOmradenForAvesta() async throws {
        let r = try await client.areas(place: "Avesta")
        #expect(!r.addresses.isEmpty)
        #expect(r.addresses.allSatisfy { $0.isArea })
    }

    @Test func avkodarSokningOchAdress() async throws {
        let r = try await client.search(query: "storgatan 2", source: nil)
        // Ett failed som inte är tomt godkänns, eftersom enskilda källor kan ligga nere.
        let hit = try #require(r.addresses.first)
        let address = try await client.address(url: hit.url)
        #expect(address.address.id == hit.id)
    }
}
