import CloudKit
import SophamtningDesign
import SophamtningKit
import SwiftUI
import UserNotifications

@main
struct SophamtningApp: App {
    /// Tyst push, och scenens delegat som tar emot inbjudningar till ett hushåll.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    /// Hushållets synk med CloudKit. `nil` under UI-testerna.
    private let cloudHousehold: CloudKitHouseholdSync?
    @State private var showsIntro: Bool
    @State private var entrance: StartEntrance

    init() {
        let start = StartIntroState.claim()
        _showsIntro = State(initialValue: start.intro)
        _entrance = State(initialValue: StartEntrance(plays: start.cards))
        Fonts.register()
        NavigationBarStyle.apply()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SophamtningKitInfo.version
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let (model, cloudHousehold) = Self.makeModel(version: version, build: build)
        self.cloudHousehold = cloudHousehold
        if let cloudHousehold {
            HouseholdShareAcceptance.shared.configure(sync: cloudHousehold, model: model)
        }
        // Hushållets lägen tas emot från start. Utan hushåll gör lyssnaren ingenting.
        model.startHousehold()
        // Knappen Utställt i Live Activity körs i appens process och skickar bocken till hushållet direkt.
        PlacedOutAction.sendToHousehold = { [model] in await model.sendLiveActivityMarks() }
        // Uppgiften måste registreras innan appen startat klart.
        BackgroundRefresh.register(model: model)
        _model = State(initialValue: model)
    }

    private static func makeModel(version: String, build: String) -> (AppModel, CloudKitHouseholdSync?) {
        #if DEBUG
        if UITestSupport.isActive {
            // UI-testerna får en stubb, en tom lagring, inga notiser (eller notiser i minnet) och ett hushåll i minnet. Ingen CloudKit-kod körs, och
            // koden finns bara i Debug-bygget.
            return (AppModel(api: UITestAPI(), store: UITestSupport.store(), scheduler: UITestSupport.notifications(), household: UITestSupport.household()), nil)
        }
        #endif
        let store = LocalStore.shared()
        let household = CloudKitHouseholdSync(container: CKContainer(identifier: HouseholdRecords.containerIdentifier), stateStore: store)
        let model = AppModel(api: SoporClient(version: version), store: store, scheduler: NotificationScheduler(), activities: LiveActivityScheduler(), widgetReloader: { WidgetReload.reloadAll() }, appVersion: "\(version) (\(build))", household: household)
        return (model, household)
    }

    var body: some Scene {
        WindowGroup {
            HomeView(model: model, entrance: entrance, onEntranceFinished: { entrance.finish() })
                .environment(\.entranceEnabled, !StartIntroState.skipsIntro)
                .environment(\.cloudHousehold, cloudHousehold)
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
