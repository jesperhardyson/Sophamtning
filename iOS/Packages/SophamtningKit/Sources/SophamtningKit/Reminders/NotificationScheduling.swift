import Foundation

/// Systemets tillstånd för notiser, utan detaljer appen inte använder.
public enum NotificationAuthorization: Equatable, Sendable {
    /// Användaren har inte fått frågan än.
    case notDetermined
    case authorized
    case denied
}

/// Svaret när användaren slår på notiser för en adress.
public enum PermissionResult: Equatable, Sendable {
    case granted
    case denied
}

/// En väntande notis som appen själv har skapat.
public struct PendingNotification: Equatable, Sendable {
    public let identifier: String
    /// `nil` när systemet inte kan ange nästa tid.
    public let fireDate: Date?
    public let body: String

    public init(identifier: String, fireDate: Date?, body: String) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.body = body
    }
}

/// Det som `AppModel` behöver av systemets notiscenter. Appen implementerar det med `UNUserNotificationCenter`.
/// Implementationen rör bara notiser vars identifierare `NotificationDiff.isOwn` känner igen.
public protocol NotificationScheduling: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Visar systemets fråga. Sant om användaren tillåter.
    func requestAuthorization() async -> Bool
    /// Väntande notiser som appen själv har skapat, inga andra.
    func pending() async -> [PendingNotification]
    func schedule(_ notifications: [PlannedNotification]) async
    func cancel(identifiers: [String]) async
}

/// Används när ingen schemaläggare angetts, till exempel i tester: notiser är då alltid nekade.
public struct DisabledNotifications: NotificationScheduling {
    public init() {}
    public func authorization() async -> NotificationAuthorization { .denied }
    public func requestAuthorization() async -> Bool { false }
    public func pending() async -> [PendingNotification] { [] }
    public func schedule(_ notifications: [PlannedNotification]) async {}
    public func cancel(identifiers: [String]) async {}
}
