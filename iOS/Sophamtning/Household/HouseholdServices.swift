import CloudKit
import SophamtningKit
import SwiftUI

/// Hushållets synk: brevlådan, hushållet som kan ligga kvar i iCloud, valet mellan dem och flytten.
@MainActor
final class HouseholdServices {
    /// Delas med appens delegat, som skapas av systemet. `nil` under UI-testerna.
    static var shared: HouseholdServices?

    let cloud: CloudKitHouseholdSync
    let routing: RoutingHouseholdSync
    private let migrator: HouseholdMigrator
    weak var model: AppModel?

    init(version: String, store: LocalStore) {
        let transport = URLSessionRelayTransport(version: version)
        let credentials = LayeredCredentialStore(synced: KeychainCredentialStore(synchronizable: true), local: KeychainCredentialStore(synchronizable: false))
        let relay = RelayHouseholdSync(transport: transport, credentials: credentials, store: store, deviceId: KeychainCredentialStore.deviceId)
        let cloud = CloudKitHouseholdSync(container: CKContainer(identifier: HouseholdRecords.containerIdentifier), stateStore: store)
        let migration = HouseholdMigrationStore(store: store)
        let routing = RoutingHouseholdSync(relay: relay, legacy: cloud, migration: migration, store: store)
        self.cloud = cloud
        self.routing = routing
        migrator = HouseholdMigrator(relay: relay, legacy: cloud, transport: transport, migration: migration, onChange: { routing.migrationDidChange() })
    }

    /// Medan appen är aktiv lyssnar den på ändringar, och flytten från iCloud görs när det är dags.
    func sceneDidChange(to phase: ScenePhase) {
        switch phase {
        case .active:
            routing.startSignals()
            Task {
                await model?.fetchHouseholdChanges()
                await migrator.run()
            }
        case .background:
            routing.stopSignals()
        default:
            break
        }
    }
}
