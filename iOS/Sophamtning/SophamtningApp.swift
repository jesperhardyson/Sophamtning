import SophamtningDesign
import SophamtningKit
import SwiftUI
import UserNotifications

@main
struct SophamtningApp: App {
    @State private var model: AppModel

    init() {
        Fonts.register()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SophamtningKitInfo.version
        let model = AppModel(api: SoporClient(version: version), store: LocalStore.shared(), scheduler: NotificationScheduler(), widgetReloader: { WidgetReload.reloadAll() })
        // Uppgiften måste registreras innan appen startat klart.
        BackgroundRefresh.register(model: model)
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
        }
    }
}
