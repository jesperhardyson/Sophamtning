import SophamtningDesign
import SophamtningKit
import SwiftUI
import UserNotifications

@main
struct SophamtningApp: App {
    @State private var model: AppModel
    @State private var showsIntro = StartIntroState.claim()

    init() {
        Fonts.register()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SophamtningKitInfo.version
        let model = Self.makeModel(version: version)
        // Uppgiften måste registreras innan appen startat klart.
        BackgroundRefresh.register(model: model)
        _model = State(initialValue: model)
    }

    private static func makeModel(version: String) -> AppModel {
        #if DEBUG
        if UITestSupport.isActive {
            // UI-testerna får en stubb, en tom lagring och inga notiser. Koden finns bara i Debug-bygget.
            return AppModel(api: UITestAPI(), store: UITestSupport.freshStore())
        }
        #endif
        return AppModel(api: SoporClient(version: version), store: LocalStore.shared(), scheduler: NotificationScheduler(), activities: LiveActivityScheduler(), widgetReloader: { WidgetReload.reloadAll() })
    }

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
                .overlay {
                    if showsIntro {
                        StartIntroView { showsIntro = false }
                    }
                }
        }
    }
}
