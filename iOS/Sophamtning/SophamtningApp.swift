import SophamtningDesign
import SophamtningKit
import SwiftUI
import UserNotifications

@main
struct SophamtningApp: App {
    @State private var model: AppModel
    @State private var showsIntro: Bool
    @State private var entrance: StartEntrance

    init() {
        let start = StartIntroState.claim()
        _showsIntro = State(initialValue: start.intro)
        _entrance = State(initialValue: StartEntrance(plays: start.cards))
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
            return AppModel(api: UITestAPI(), store: UITestSupport.store())
        }
        #endif
        return AppModel(api: SoporClient(version: version), store: LocalStore.shared(), scheduler: NotificationScheduler(), activities: LiveActivityScheduler(), widgetReloader: { WidgetReload.reloadAll() })
    }

    var body: some Scene {
        WindowGroup {
            HomeView(model: model, entrance: entrance, onEntranceFinished: { entrance.finish() })
                .environment(\.entranceEnabled, !StartIntroState.skipsIntro)
                .overlay {
                    if showsIntro {
                        StartIntroView(
                            onExit: { entrance.start(at: Date()) },
                            onFinish: {
                                showsIntro = false
                                entrance.start(at: Date())
                            },
                            onNoFreshLaunch: {
                                showsIntro = false
                                settleEntrance()
                            }
                        )
                    }
                }
                .onAppear {
                    // Utan intro startar korten direkt, om det är en start från början.
                    guard !showsIntro else { return }
                    if StartIntroState.isFreshLaunch { entrance.start(at: Date()) } else { settleEntrance() }
                }
        }
    }

    /// Processen startade i bakgrunden, så det är ingen start från början. Korten visas på en gång, utan rörelse.
    private func settleEntrance() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { entrance.finish() }
    }
}
