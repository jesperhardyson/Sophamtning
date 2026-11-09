import Foundation

/// En körning av bakgrundsuppdateringen (`BGAppRefreshTask`). Logiken ligger här så att den går att testa med `swift test`,
/// och appens tunna lager kopplar den till BackgroundTasks.
///
/// Körningen bokar nästa körning först, hämtar hushållets ändringar, hämtar scheman enligt `RefreshPolicy` (`refreshAll(manual: false)`), kör
/// `applyReminders`, laddar om widgeten och avslutar. Den startar aldrig en Live Activity: en bakgrundskörning får inte det,
/// och planerarens aktiviteter startas bara när appen är öppen. Att ta bort och uppdatera går bra. Tiden ute (`expire()`) avslutar uppgiften direkt.
/// `complete` anropas exakt en gång, oavsett om arbetet eller tiden ute kommer först.
@MainActor
public final class BackgroundRefreshRun {
    public nonisolated static let identifier = "se.hardyson.sophamtning.refresh"
    /// Nästa körning begärs tidigast så här långt fram. iOS bestämmer själv när den faktiskt körs.
    public nonisolated static let earliestDelay: TimeInterval = 3600

    public nonisolated static func earliestBeginDate(now: Date) -> Date {
        now.addingTimeInterval(earliestDelay)
    }

    private let model: AppModel
    private let reloadWidgets: @MainActor () -> Void
    private let scheduleNext: @MainActor () -> Void
    private let complete: @MainActor (Bool) -> Void
    private var started = false
    private var finished = false
    private var work: Task<Void, Never>?

    /// - Parameters:
    ///   - reloadWidgets: laddar om widgetens tidslinjer.
    ///   - scheduleNext: bokar nästa körning, tidigast om en timme.
    ///   - complete: avslutar uppgiften, `true` när arbetet blev klart och `false` när tiden gick ut.
    public init(model: AppModel, reloadWidgets: @escaping @MainActor () -> Void, scheduleNext: @escaping @MainActor () -> Void, complete: @escaping @MainActor (Bool) -> Void) {
        self.model = model
        self.reloadWidgets = reloadWidgets
        self.scheduleNext = scheduleNext
        self.complete = complete
    }

    public func start() {
        guard !started else { return }
        started = true
        // Nästa körning bokas före arbetet, så att kedjan består även om den här avbryts.
        scheduleNext()
        work = Task { @MainActor in
            // Hushållets ändringar först, så att andras bockar tystar påminnelserna som planeras nedan.
            await model.fetchHouseholdChanges()
            await model.refreshAll(manual: false, startingActivities: false)
            model.applyReminders(startingActivities: false)
            await model.settleReminders()
            finish(success: true)
        }
    }

    /// Systemet säger att tiden är slut. Arbetet avbryts och uppgiften avslutas som misslyckad.
    public func expire() {
        work?.cancel()
        finish(success: false)
    }

    /// Väntar tills arbetet är slut (för tester).
    public func waitUntilFinished() async {
        await work?.value
    }

    private func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        reloadWidgets()
        complete(success)
    }
}
