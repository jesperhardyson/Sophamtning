import Foundation
import Testing
@testable import SophamtningKit

private enum Boom: Error { case failed }

@Suite struct LatestOnlyTests {
    @Test func gammaltSvarErsatterInteNytt() async throws {
        let latest = LatestOnly()
        let gate = AsyncStream<Void>.makeStream()
        let started = AsyncStream<Void>.makeStream()

        let first = Task {
            try await latest.run { () -> Int in
                started.continuation.yield()
                for await _ in gate.stream { break }
                return 1
            }
        }
        for await _ in started.stream { break }
        let second = try await latest.run { 2 }
        gate.continuation.yield()

        #expect(second == 2)
        #expect(try await first.value == nil)
    }

    @Test func ensamtAnropGerSittVarde() async throws {
        let latest = LatestOnly()
        #expect(try await latest.run { 7 } == 7)
    }

    @Test func felFranDetNyasteKastas() async {
        let latest = LatestOnly()
        await #expect(throws: Boom.self) { try await latest.run { () -> Int in throw Boom.failed } }
    }

    @Test func felFranGammaltAnropGerNil() async throws {
        let latest = LatestOnly()
        let gate = AsyncStream<Void>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let first = Task {
            try await latest.run { () -> Int in
                started.continuation.yield()
                for await _ in gate.stream { break }
                throw Boom.failed
            }
        }
        for await _ in started.stream { break }
        _ = try await latest.run { 2 }
        gate.continuation.yield()
        #expect(try await first.value == nil)
    }
}
