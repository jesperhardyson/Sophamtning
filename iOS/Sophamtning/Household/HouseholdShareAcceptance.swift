import CloudKit
import os
import SophamtningKit
import UIKit

/// Tar emot inbjudningar till ett hushåll. Den som redan är med i ett hushåll, som ägare eller medlem, får först frågan
/// `HouseholdTexts.leaveFirst`. Svarar personen nej accepteras ingenting.
@MainActor
final class HouseholdShareAcceptance {
    static let shared = HouseholdShareAcceptance()

    /// Inbjudan som väntar på svar om att lämna det nuvarande hushållet först.
    private var awaitingAnswer: CKShare.Metadata?

    private var sync: CloudKitHouseholdSync?
    private var model: AppModel?
    /// En inbjudan som kom innan appen hade startat klart, till exempel när appen öppnades av länken.
    private var early: CKShare.Metadata?
    private let logger = Logger(subsystem: "se.hardyson.sophamtning", category: "Hushall")

    func configure(sync: CloudKitHouseholdSync, model: AppModel) {
        self.sync = sync
        self.model = model
        if let early {
            self.early = nil
            receive(early)
        }
    }

    func receive(_ metadata: CKShare.Metadata) {
        guard let sync, let model else {
            early = metadata
            return
        }
        if sync.isCurrentHousehold(metadata) {
            // Samma hushåll som jag redan är med i: bara hämta det.
            Task { await sync.fetchChanges() }
            return
        }
        let household = model.household
        if household.role != .none, household.status != .removed {
            ask(metadata)
        } else {
            accept(metadata)
        }
    }

    /// Frågan visas som en dialog från UIKit ovanpå det som visas, även när Inställningar eller Hushåll är öppet.
    private func ask(_ metadata: CKShare.Metadata) {
        // En ny inbjudan ersätter en obesvarad.
        awaitingAnswer = metadata
        let alert = UIAlertController(title: HouseholdTexts.leaveFirst, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel) { _ in self.answer(leaveFirst: false) })
        alert.addAction(UIAlertAction(title: "Lämna och gå med", style: .destructive) { _ in self.answer(leaveFirst: true) })
        guard let top = UIApplication.shared.topViewController else { return }
        if let shown = top as? UIAlertController, let below = shown.presentingViewController {
            // En obesvarad fråga byts mot den nya.
            shown.dismiss(animated: false) { below.present(alert, animated: true) }
        } else {
            top.present(alert, animated: true)
        }
    }

    /// Svaret på frågan om att lämna först. Ja lämnar det nuvarande hushållet och accepterar sedan inbjudan.
    func answer(leaveFirst: Bool) {
        guard let metadata = awaitingAnswer else { return }
        awaitingAnswer = nil
        guard leaveFirst, let model else { return }
        Task {
            await model.leaveHousehold()
            // Gick det inte att lämna står felet i arket, och inbjudan accepteras inte.
            guard model.household.role == .none else { return }
            accept(metadata)
        }
    }

    private func accept(_ metadata: CKShare.Metadata) {
        guard let sync else { return }
        Task {
            do {
                try await sync.accept(metadata)
            } catch {
                logger.error("Kunde inte gå med i hushållet: \(error.localizedDescription, privacy: .public)")
                sync.recordFailure(error)
            }
        }
    }
}

extension CloudKitHouseholdSync {
    /// Ett fel vid inbjudan eller delning visas som att hushållet inte kunde uppdateras, aldrig som ett tomt hushåll.
    func recordFailure(_ error: any Error) {
        let mapped = (error as? CKError).flatMap { HouseholdRecords.status(for: $0, ownerName: "") }
        mutate { inner in
            if mapped == .notSignedIn {
                inner.signedIn = false
            } else {
                inner.status = mapped ?? .failed
            }
        }
        emit()
    }
}

// MARK: Appens och scenens delegater

/// Registrerar för tyst push och ger scenerna en delegat som tar emot inbjudningar.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // CKSyncEngine sköter prenumerationerna själv, men behöver att appen tar emot push.
        if HouseholdEnvironment.usesCloudKit { application.registerForRemoteNotifications() }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = HouseholdSceneDelegate.self
        return configuration
    }
}

/// Inbjudningar kommer till scenen: när appen redan körs, och i `connectionOptions` när länken startade appen.
final class HouseholdSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Task { @MainActor in HouseholdShareAcceptance.shared.receive(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in HouseholdShareAcceptance.shared.receive(cloudKitShareMetadata) }
    }
}

/// Om appen talar med CloudKit. Under UI-testerna (`-uitest`) används ett hushåll i minnet, och ingen CloudKit-kod körs.
enum HouseholdEnvironment {
    static var usesCloudKit: Bool {
        #if DEBUG
        return !UITestSupport.isActive
        #else
        return true
        #endif
    }
}
