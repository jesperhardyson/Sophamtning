import ActivityKit
import Foundation
import SophamtningKit
import UIKit

/// Lägger in och tar bort Live Activities hos iOS. Start sker bara när appen inte ligger i bakgrunden.
struct LiveActivityScheduler: LiveActivityScheduling {
    func areEnabled() async -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func current() async -> [SystemActivity] {
        Activity<PickupActivityAttributes>.activities.map { activity in
            let phase = Self.phase(of: activity.activityState)
            return SystemActivity(
                activity: ExistingActivity(
                    id: activity.id,
                    key: activity.attributes.key,
                    pickupDate: activity.attributes.pickupDate,
                    content: activity.content.state,
                    isPending: phase == .pending,
                    start: activity.attributes.start
                ),
                phase: phase
            )
        }
    }

    func start(_ planned: PlannedLiveActivity) async throws {
        // Bakgrundskörningar startar aldrig en aktivitet. Det här stoppar också ett anrop som råkar komma efter att appen lämnats.
        guard await UIApplication.shared.applicationState != .background else { throw LiveActivityNotInForeground() }
        let attributes = PickupActivityAttributes(key: planned.key, pickupDate: planned.pickupDate, start: planned.start)
        // Inget `staleDate`, eftersom ingen uppdatering kommer utan appen. Systemets gräns på 12 timmar avslutar aktiviteten.
        let content = ActivityContent(state: planned.content, staleDate: nil)
        switch planned.startMode(now: Date()) {
        case .immediately:
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        case .scheduled(let date):
            let alert = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: PickupActivityContent.alertTitle),
                body: LocalizedStringResource(stringLiteral: planned.content.alertBody),
                sound: .default
            )
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil, style: .standard, alertConfiguration: alert, start: date)
        }
    }

    func update(id: String, content: PickupActivityContent) async {
        for activity in Activity<PickupActivityAttributes>.activities where activity.id == id {
            await activity.update(ActivityContent(state: content, staleDate: nil))
        }
    }

    func remove(id: String) async {
        for activity in Activity<PickupActivityAttributes>.activities where activity.id == id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Bocken står kvar några sekunder innan aktiviteten försvinner, som när knappen Utställt trycks.
    func end(id: String, showing content: PickupActivityContent) async {
        for activity in Activity<PickupActivityAttributes>.activities where activity.id == id {
            let done = ActivityContent(state: content, staleDate: nil)
            await activity.end(done, dismissalPolicy: .after(Date().addingTimeInterval(PlacedOutAction.checkmarkSeconds)))
        }
    }

    /// Ett okänt läge räknas som avslutat, så att notisen står kvar.
    private static func phase(of state: ActivityState) -> LiveActivityPhase {
        switch state {
        case .pending: .pending
        case .active: .active
        case .stale: .stale
        case .ended: .ended
        case .dismissed: .dismissed
        @unknown default: .ended
        }
    }
}

/// Ändringar av valet för Live Activities i iOS.
enum LiveActivityEnablement {
    static func changes() -> ActivityAuthorizationInfo.ActivityEnablementUpdates {
        ActivityAuthorizationInfo().activityEnablementUpdates
    }
}
