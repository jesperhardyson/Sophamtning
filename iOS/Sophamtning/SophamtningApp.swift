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
        _model = State(initialValue: AppModel(api: SoporClient(version: version), store: LocalStore.shared(), scheduler: NotificationScheduler()))
    }

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
        }
    }
}
