import SophamtningKit
import UIKit

/// Tar emot länkar till hushåll i brevlådan. Den som redan är med i ett hushåll får först frågan
/// `HouseholdTexts.leaveFirst`, som för en inbjudan via iCloud. Länken innehåller hushållets nyckel och loggas aldrig.
@MainActor
final class HouseholdLinkAcceptance {
    static let shared = HouseholdLinkAcceptance()

    private var model: AppModel?
    /// En länk som kom innan appen hade startat klart, till exempel när appen öppnades av den.
    private var early: HouseholdInviteLink?

    func configure(model: AppModel) {
        self.model = model
        guard let early else { return }
        self.early = nil
        receive(early)
    }

    /// Svarar med om adressen var en inbjudan.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let link = HouseholdInviteLink(url: url) else { return false }
        receive(link)
        return true
    }

    private func receive(_ link: HouseholdInviteLink) {
        guard let model else {
            early = link
            return
        }
        Task {
            await model.receiveInvite(link)
            if model.pendingInvite != nil { ask(model) }
        }
    }

    /// Frågan visas som en dialog från UIKit ovanpå det som visas, även när Inställningar eller Hushåll är öppet.
    private func ask(_ model: AppModel) {
        let isOwner = model.household.role == .owner
        let alert = UIAlertController(title: HouseholdTexts.leaveFirst(isOwner: isOwner), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel) { _ in Task { await model.answerInvite(leaveFirst: false) } })
        alert.addAction(UIAlertAction(title: HouseholdTexts.leaveFirstAction(isOwner: isOwner), style: .destructive) { _ in Task { await model.answerInvite(leaveFirst: true) } })
        guard let top = UIApplication.shared.topViewController else { return }
        if let shown = top as? UIAlertController, let below = shown.presentingViewController {
            // En obesvarad fråga byts mot den nya.
            shown.dismiss(animated: false) { below.present(alert, animated: true) }
        } else {
            top.present(alert, animated: true)
        }
    }
}
