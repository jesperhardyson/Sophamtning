import Foundation

/// Systemets läge för en aktivitet, utan ActivityKit, så att bedömningen går att testa med `swift test`.
public enum LiveActivityPhase: Equatable, Sendable {
    case pending, active, stale, ended, dismissed

    /// Bara en väntande eller pågående aktivitet aviserar eller syns. Räknas någon annan försvinner en notis tyst.
    /// `stale` räknas inte heller: den visas som inaktuell, och appen sätter aldrig något `staleDate`.
    public var countsAsExisting: Bool {
        self == .pending || self == .active
    }
}

public struct SystemActivity: Equatable, Sendable {
    public let activity: ExistingActivity
    public let phase: LiveActivityPhase

    public init(activity: ExistingActivity, phase: LiveActivityPhase) {
        self.activity = activity
        self.phase = phase
    }
}

/// Appen ligger i bakgrunden, så starten gjordes inte. Det är inget fel, och nästa öppning försöker igen.
public struct LiveActivityNotInForeground: Error {
    public init() {}
}

/// Det som `AppModel` behöver av ActivityKit. Appen implementerar det med `Activity`.
public protocol LiveActivityScheduling: Sendable {
    /// Om Live Activities är påslagna för appen i iOS.
    func areEnabled() async -> Bool
    /// Alla aktiviteter systemet känner till, i vilket läge de än är.
    func current() async -> [SystemActivity]
    func start(_ activity: PlannedLiveActivity) async throws
    func update(id: String, content: PickupActivityContent) async
    func remove(id: String) async
    /// Visar innehållet en kort stund och avslutar sedan aktiviteten, som knappen Utställt gör.
    func end(id: String, showing content: PickupActivityContent) async
}

extension LiveActivityScheduling {
    /// Utan en egen avslutning uppdateras aktiviteten och tas sedan bort.
    public func end(id: String, showing content: PickupActivityContent) async {
        await update(id: id, content: content)
        await remove(id: id)
    }
}

/// Används när ingen schemaläggare angetts, till exempel i tester: inga aktiviteter finns och inga kan startas.
public struct DisabledLiveActivities: LiveActivityScheduling {
    public init() {}
    public func areEnabled() async -> Bool { false }
    public func current() async -> [SystemActivity] { [] }
    public func start(_ activity: PlannedLiveActivity) async throws {}
    public func update(id: String, content: PickupActivityContent) async {}
    public func remove(id: String) async {}
}
