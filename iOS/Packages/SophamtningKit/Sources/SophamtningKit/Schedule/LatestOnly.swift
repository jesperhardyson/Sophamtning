import Foundation

/// Låter bara det senast startade arbetet lämna ett svar. Ett äldre arbete som blir klart efter
/// att ett nyare startat får `nil`, så att ett gammalt svar aldrig ersätter ett nyare.
public actor LatestOnly {
    private var latest = 0

    public init() {}

    /// Ger `nil` om ett nyare anrop har startat medan det här pågick. Fel från ett omsprunget anrop kastas inte.
    public func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T? {
        latest += 1
        let mine = latest
        do {
            let value = try await work()
            return mine == latest ? value : nil
        } catch {
            if mine != latest { return nil }
            throw error
        }
    }
}
