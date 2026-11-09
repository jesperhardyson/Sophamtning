import Foundation

/// Hushållets texter på svenska.
public enum HouseholdTexts {
    /// "Utställt av Kim, kl. 19:42". Klockslaget är svensk tid. Ett okänt id visas som "någon".
    public static func placedOut(_ mark: HouseholdMark, participants: [HouseholdParticipant], myId: String?) -> String {
        let (who, time) = whoAndTime(mark, participants: participants, myId: myId)
        return "Utställt av \(who), kl. \(time)"
    }

    /// Min egen bock som inte har skickats än, och vars tid appen inte vet.
    public static let placedOutByMe = "Utställt av dig"

    /// Rubriken i raden för en bock.
    public static let placedOutTitle = "Utställt"

    /// Raden under "Utställt": "av Kim · kl. 19:42", "av dig · kl. 19:42" eller "av någon · kl. 19:42".
    public static func placedOutSubtitle(_ mark: HouseholdMark, participants: [HouseholdParticipant], myId: String?) -> String {
        let (who, time) = whoAndTime(mark, participants: participants, myId: myId)
        return "av \(who) · kl. \(time)"
    }

    /// Undertexten för en bock som inte har nått iCloud än.
    public static let pendingSubtitle = "skickas när nätet finns"

    /// Vem som ställde ut, och klockslaget i svensk tid.
    private static func whoAndTime(_ mark: HouseholdMark, participants: [HouseholdParticipant], myId: String?) -> (String, String) {
        let who: String
        if mark.by == myId {
            who = "dig"
        } else {
            who = participants.first { $0.id == mark.by }?.name ?? "någon"
        }
        let parts = StockholmClock.calendar.dateComponents([.hour, .minute], from: mark.at)
        return (who, SwedishFormat.clock(minutes: parts.hour! * 60 + parts.minute!))
    }

    public static func othersPlacedOutNotification(name: String, address: String) -> String {
        "\(name) ställde ut kärlen för \(address)"
    }

    /// Texten för hushållets läge, eller `nil` när allt fungerar.
    public static func status(_ status: HouseholdStatus) -> String? {
        switch status {
        case .synced: nil
        case .notSignedIn: "Synkar inte just nu"
        case .quotaExceeded(let ownerName): "\(genitive(ownerName)) iCloud-lagring är full, så hushållet kan inte uppdateras."
        case .removed: leftNote
        case .failed: "Hushållet kunde inte uppdateras just nu"
        }
    }

    /// "Kims", men "Lars" och "Alex": namn som slutar på s, x eller z får ingen extra bokstav.
    private static func genitive(_ name: String) -> String {
        guard let last = name.last?.lowercased(), ["s", "x", "z"].contains(last) else { return name + "s" }
        return name
    }

    public static let invite = "Bjud in till hushållet"
    public static let manage = "Hantera medlemmar"
    public static let leave = "Lämna hushållet"
    public static let end = "Avsluta hushållet"
    public static let share = "Dela med hushållet"
    public static let placeOut = "Ställ ut kärlen"
    public static let undo = "Ångra"
    public static let retry = "Försök igen"
    public static let silence = "Tysta min påminnelse när någon annan har ställt ut"
    public static let notify = "Notis när någon ställer ut kärlen"
    public static let deliveryNote = "Fungerar när telefonen tillåter det. Ibland syns det först när du öppnar appen."
    public static let leftNote = "Du är inte längre med i hushållet. Adresserna finns kvar som dina egna."
    public static let leaveFirst = "Du är redan med i ett hushåll. Lämna det för att gå med i det här?"

    // MARK: Arket och vyerna

    public static let title = "Hushåll"
    /// Rubriken i Inställningar över raden Hushåll.
    public static let sharingHeading = "Delning"
    public static let undoHint = "Tar bort att kärlen är utställda"
    public static let intro = "Dela adresser med dem du bor med. Ni ser samma schema, och när någon ställer ut kärlen syns det för alla. Hushållet sparas i ert iCloud."
    public static let participants = "Deltagare"
    public static let owner = "Ägare"
    public static let notifications = "Notiser"
    public static let notSignedInNote = "Logga in på iCloud och låt Sophämtning använda iCloud i Inställningar. De delade adresserna visas som de senast sparades."
    public static let shared = "Delas med hushållet"
    public static let shareNote = "Alla i hushållet ser adressen och kan ställa ut kärlen."
    public static let widgetPlacedOut = "Utställt"
    public static let leaveConfirm = "Lämna hushållet?"
    public static let leaveConfirmMessage = "Adresserna finns kvar som dina egna. Bockarna för Utställt försvinner."
    public static let endConfirm = "Avsluta hushållet?"
    public static let endConfirmMessage = "Hushållet tas bort för alla. Adresserna finns kvar som egna adresser hos var och en."

    /// Värdet på raden Hushåll i Inställningar: "2 deltagare", eller tomt utan hushåll.
    public static func participantCount(_ count: Int) -> String {
        count > 0 ? "\(count) deltagare" : ""
    }

    /// En deltagare i listan: "Alex (du)" för mig själv, annars namnet.
    public static func participantName(_ participant: HouseholdParticipant, myId: String?) -> String {
        participant.id == myId ? "\(participant.name) (du)" : participant.name
    }
}
