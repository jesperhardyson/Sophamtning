import CloudKit
import CoreTransferable
import SophamtningKit
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Hushållets synk med CloudKit, för inbjudan och medlemmarna. `nil` under UI-testerna, där hushållet finns i minnet.
    @Entry var cloudHousehold: CloudKitHouseholdSync?
}

/// Inbjudan till hushållet för `ShareLink`. Systemets delningsark med CloudKit-samarbete anropar `prepare` när personen
/// väljer hur inbjudan ska skickas, och då skapas zonen och delningen, eller används den som redan finns.
struct HouseholdInvitation: Transferable {
    let container: CKContainer
    let prepare: @Sendable () async throws -> CKShare

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invitation in
            .prepareShare(container: invitation.container) {
                try await invitation.prepare()
            }
        }
    }
}

/// Håller kvar inbjudan i arket medan systemets delningsark är öppet. När delningen skapas blir jag ägare, och utan
/// spärren skulle arket byta till deltagarna och ta bort `ShareLink` mitt i delningen.
@MainActor
@Observable
final class InvitationInProgress {
    var active = false
}

/// **Hantera medlemmar**: systemets `UICloudSharingController` för ägarens delning.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let sync: CloudKitHouseholdSync

    func makeCoordinator() -> Coordinator {
        Coordinator(sync: sync)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: sync.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let sync: CloudKitHouseholdSync

        init(sync: CloudKitHouseholdSync) {
            self.sync = sync
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            HouseholdTexts.title
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            sync.recordFailure(error)
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
