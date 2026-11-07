import BackgroundTasks
import os
import SophamtningKit
import WidgetKit

/// Laddar om widgetens tidslinjer. Ett tunt anrop, så att paketet inte behöver känna till WidgetKit.
enum WidgetReload {
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Kopplar bakgrundsuppdateringen (`BGAppRefreshTask`) till `BackgroundRefreshRun`, som har själva logiken.
@MainActor
enum BackgroundRefresh {
    private static let logger = Logger(subsystem: "se.hardyson.sophamtning", category: "BackgroundRefresh")

    /// Måste anropas innan appen har startat klart. Uppgiften körs på huvudtråden.
    static func register(model: AppModel) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundRefreshRun.identifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = TaskBox(task)
            MainActor.assumeIsolated { run(box, model: model) }
        }
    }

    /// Begär nästa körning, tidigast om en timme. iOS bestämmer själv när, och om, den körs.
    static func schedule(now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefreshRun.identifier)
        request.earliestBeginDate = BackgroundRefreshRun.earliestBeginDate(now: now)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Till exempel när bakgrundsuppdatering är avstängd i Inställningar. Appen fungerar ändå och hämtar när den öppnas.
            logger.error("Kunde inte boka bakgrundsuppdatering: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func run(_ box: TaskBox, model: AppModel) {
        let run = BackgroundRefreshRun(
            model: model,
            reloadWidgets: { WidgetReload.reloadAll() },
            scheduleNext: { schedule() },
            complete: { box.task.setTaskCompleted(success: $0) }
        )
        // Systemet anropar den här på en valfri kö. `expire()` är idempotent och ser till att uppgiften avslutas en gång.
        box.task.expirationHandler = { Task { @MainActor in run.expire() } }
        run.start()
    }
}

/// `BGAppRefreshTask` är inte `Sendable`. Den används bara på huvudtråden, förutom `expirationHandler`, som sätts där.
private final class TaskBox: @unchecked Sendable {
    let task: BGAppRefreshTask
    init(_ task: BGAppRefreshTask) { self.task = task }
}
