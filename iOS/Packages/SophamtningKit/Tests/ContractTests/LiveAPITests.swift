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
        // Enskilda källor kan svara 502 även när API:t är friskt. Det är inget kontraktsbrott.
        do {
            let address = try await client.address(url: hit.url)
            #expect(address.address.id == hit.id)
        } catch APIError.sourceUnavailable {}
    }

    /// Verifierat mot produktion: Avesta 2026-10-27 ger Trakt 7 och schemat täcker datumet.
    @Test func avkodarOmradeMedSenasteTomning() async throws {
        let r = try await client.areas(place: "Avesta", lastEmptied: DayDate("2026-10-27")!)
        #expect(r.dateCovered == true)
        let hit = try #require(r.addresses.first { $0.detail?.contains("Trakt 7") == true })
        let pickups = try #require(hit.pickups)
        #expect(pickups.previous.last == DayDate("2026-10-27"))
        #expect(pickups.previous.count <= 2)
        #expect(pickups.next != nil)
        #expect(AreaFinderState.from(r) != .failed)
    }

    @Test func omradenUtanTomningHarInteNyaFalt() async throws {
        let r = try await client.areas(place: "Avesta")
        #expect(r.dateCovered == nil)
        #expect(r.addresses.allSatisfy { $0.pickups == nil })
    }
}
