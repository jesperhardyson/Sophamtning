import Foundation

/// Jämför önskade notiser med de som redan är schemalagda, så att bara skillnaden ändras.
public enum NotificationDiff {
    /// Ett enda ögonblick räknas som samma tid. Utlösarens klockslag har bara minuters noggrannhet.
    static let fireDateTolerance: TimeInterval = 1

    /// Identifierare som planeraren skapar: `<key.fileName>-<iso-datum>`, alltså 64 hexadecimala tecken, ett streck och `åååå-mm-dd`.
    /// Schemaläggaren rör bara väntande notiser med sådana identifierare, aldrig andra.
    public static func isOwn(identifier: String) -> Bool {
        let parts = identifier.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 64,
              parts[0].allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }),
              DayDate(String(parts[1])) != nil
        else { return false }
        return true
    }

    /// `pendingBodies` är valfri: med den ersätts även en notis vars text ändrats (till exempel ett nytt namn).
    /// Saknas en identifierare där räknas texten som oförändrad. `retain` är identifierare som får stå kvar när de ligger framför `now`.
    public static func diff(
        desired: [PlannedNotification],
        pendingIds: Set<String>,
        pendingFireDates: [String: Date],
        pendingBodies: [String: String] = [:],
        retain: Set<String> = [],
        now: Date = .distantFuture
    ) -> (add: [PlannedNotification], removeIds: [String]) {
        var add: [PlannedNotification] = []
        var remove: Set<String> = []
        let desiredIds = Set(desired.map(\.identifier))
        for notification in desired {
            guard pendingIds.contains(notification.identifier) else {
                add.append(notification)
                continue
            }
            let sameTime = pendingFireDates[notification.identifier].map {
                abs($0.timeIntervalSince(notification.fireDate)) < fireDateTolerance
            } ?? false
            let sameBody = pendingBodies[notification.identifier].map { $0 == notification.body } ?? true
            if !(sameTime && sameBody) {
                // Samma identifierare med ny tid eller text: den gamla tas bort och den nya läggs till.
                add.append(notification)
                remove.insert(notification.identifier)
            }
        }
        // En väntande notis som ligger framför och ska stå kvar (reserven) tas inte bort även om planen saknar den.
        let kept = pendingIds.filter { id in retain.contains(id) && (pendingFireDates[id].map { $0 > now } ?? false) }
        remove.formUnion(pendingIds.subtracting(desiredIds).subtracting(kept))
        return (add, remove.sorted())
    }
}
