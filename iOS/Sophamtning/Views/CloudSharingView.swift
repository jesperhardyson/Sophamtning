import CloudKit
import SophamtningKit
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Hushållets synk med CloudKit, för medlemmarna i ett hushåll som ligger kvar där. `nil` under UI-testerna, där hushållet finns i minnet.
    @Entry var cloudHousehold: CloudKitHouseholdSync?
}

/// **Hantera medlemmar**: systemets `UICloudSharingController`, presenterad modalt från UIKit ovanpå det som visas.
/// Inuti ett SwiftUI-ark blir kontrollern ofta tom, så den visas inte där.
@MainActor
enum CloudSharingPresenter {
    /// Delegaten hålls kvar så länge kontrollern visas, eftersom `delegate` är svag.
    private static var current: Coordinator?

    static func present(share: CKShare, sync: CloudKitHouseholdSync) {
        guard let presenter = UIApplication.shared.topViewController else { return }
        let coordinator = Coordinator(sync: sync)
        let controller = UICloudSharingController(share: share, container: sync.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = coordinator
        current = coordinator
        presenter.present(controller, animated: true)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let sync: CloudKitHouseholdSync

        init(sync: CloudKitHouseholdSync) {
            self.sync = sync
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            HouseholdTexts.title
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            sync.recordFailure(error, share: csc.share)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share { sync.shareDidChange(share) }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // Att sluta dela är att avsluta hushållet för alla.
            let sync = sync
            Task { await sync.sharingDidStop() }
        }
    }
}

extension UIApplication {
    /// Den översta vykontrollern i den aktiva scenen, också när ett ark eller en dialog visas.
    var topViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
