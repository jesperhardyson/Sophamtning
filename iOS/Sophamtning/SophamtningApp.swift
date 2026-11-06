import SophamtningDesign
import SophamtningKit
import SwiftUI

@main
struct SophamtningApp: App {
    @State private var model: AppModel

    init() {
        Fonts.register()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SophamtningKitInfo.version
        _model = State(initialValue: AppModel(api: SoporClient(version: version), store: LocalStore.shared()))
    }

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
        }
    }
}
