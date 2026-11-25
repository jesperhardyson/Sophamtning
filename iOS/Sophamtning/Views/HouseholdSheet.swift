import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

/// Arket Hushåll från Inställningar. Utan hushåll: en förklaring och **Bjud in till hushållet**. Med hushåll: deltagarna,
/// valen för notiser och **Lämna hushållet** eller **Avsluta hushållet**.
///
/// Ägaren bjuder in med en länk, som skapas när knappen trycks, och tar bort en deltagare med ett svep. Ett hushåll som
/// ligger kvar i iCloud har i stället **Hantera medlemmar**, som visar `UICloudSharingController` modalt ovanpå arket.
struct HouseholdSheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.cloudHousehold) private var cloud
    /// Inbjudan skapas. Knappen visar det, och arket byter inte innehåll under tiden.
    @State private var inviting = false
    /// Inbjudan skapades när det inte fanns något hushåll.
    @State private var startedInviting = false
    /// Raden som står öppen efter ett svep, och deltagaren som ska tas bort när det bekräftas.
    @State private var openRow: String?
    @State private var removing: HouseholdParticipant?
    @State private var revokes = 0
    @State private var confirmingLeave = false
    @State private var notifyPulse = 0
    /// Valet för notisen medan frågan om tillstånd pågår, så att reglaget inte hoppar tillbaka under tiden.
    @State private var pendingNotify: Bool?
    @State private var notifyDenied = false
    /// Fältet Ditt namn. Fylls från modellen när arket öppnas och sparas när fältet lämnas.
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    private var household: HouseholdState { model.household }
    private var isMember: Bool { household.role != .none && household.status != .removed }
    /// Förklaringen står kvar tills länken finns, även när jag just blivit ägare.
    private var showsMember: Bool { isMember && !(inviting && startedInviting) }
    private var isOwner: Bool { household.role == .owner }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    notices
                    if showsMember {
                        // Saknas mitt namn står fältet först, så att det är det första den som just gått med ser.
                        if model.householdNameMissing { nameSection }
                        participants
                        if !model.householdNameMissing { nameSection }
                        notifications
                        leaveSection
                    } else {
                        invite
                    }
                }
                .padding(.horizontal, PageMargin.horizontal)
                .padding(.bottom, 32)
            }
            // Tyst push kommer inte alltid. Arket hämtar därför själv, så att en ny deltagare syns utan omstart.
            .refreshable { await model.fetchHouseholdChanges() }
            .task { await model.fetchHouseholdChanges() }
            .onAppear { nameDraft = model.householdName }
            // Ett namn från Apple-kontot kan komma först efter hämtningen. Det fyller bara ett tomt fält.
            .onChange(of: model.householdName) { _, name in
                if nameDraft.isEmpty, !nameFocused { nameDraft = name }
            }
            .onChange(of: nameFocused) { _, focused in
                if !focused { saveName() }
            }
            .closesOpenSwipeRow($openRow)
            .background(Color.Theme.bg.ignoresSafeArea())
            .navigationTitle(HouseholdTexts.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .confirmationDialog(isOwner ? HouseholdTexts.endConfirm : HouseholdTexts.leaveConfirm, isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button(isOwner ? HouseholdTexts.end : HouseholdTexts.leave, role: .destructive) {
                    Task { await model.leaveHousehold() }
                }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text(isOwner ? HouseholdTexts.endConfirmMessage : HouseholdTexts.leaveConfirmMessage)
            }
            .confirmationDialog(
                removing.map { HouseholdTexts.removeConfirm(name: $0.name) } ?? "",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible,
                presenting: removing
            ) { participant in
                Button(HouseholdTexts.removeParticipant, role: .destructive) {
                    openRow = nil
                    Task { await model.removeParticipant(participant.id) }
                }
                Button("Avbryt", role: .cancel) { openRow = nil }
            } message: { participant in
                Text(HouseholdTexts.removeConfirmMessage(name: participant.name))
            }
            .sensoryFeedback(.success, trigger: revokes)
            // Raden om att man lämnat visas en gång. Nästa gång arket öppnas visas deltagarna.
            .onDisappear {
                saveName()
                model.clearHouseholdNotice()
                model.clearMembersNotice()
            }
        }
    }

    // MARK: Lägen

    /// Raden om vad som hänt och hushållets läge när något inte fungerar. Samma text visas bara en gång. Är det ett fel
    /// står statuskortet kvar, eftersom det har knappen Försök igen, och raden släpps.
    @ViewBuilder
    private var notices: some View {
        let status = HouseholdTexts.status(household.status)
        let duplicate = model.householdNotice != nil && model.householdNotice == status
        let notice = duplicate && household.status == .failed ? nil : model.householdNotice
        let shownStatus = duplicate && household.status != .failed ? nil : status
        if notice != nil || shownStatus != nil || model.householdMembersText != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let notice {
                    MessageCard(style: .neutral, icon: "person.2", title: HouseholdTexts.title, message: notice)
                }
                if let joined = model.householdMembersText {
                    MessageCard(style: .neutral, icon: "person.badge.plus", title: HouseholdTexts.title, message: joined)
                }
                if let shownStatus {
                    statusCard(shownStatus)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func statusCard(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch household.status {
            case .notSignedIn:
                MessageCard(style: .warning, icon: "icloud.slash", title: status, message: HouseholdTexts.notSignedInNote)
                Button { openAppSettings() } label: {
                    Text("Öppna Inställningar")
                        .font(.ui(17, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.primary)
                }
                .buttonStyle(.pressable)
            case .failed:
                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: HouseholdTexts.title, message: status)
                Button { Task { await model.fetchHouseholdChanges() } } label: { PrimaryButtonLabel(title: HouseholdTexts.retry) }
                    .buttonStyle(.pressable)
            default:
                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: HouseholdTexts.title, message: status)
            }
        }
    }

    // MARK: Utan hushåll

    private var invite: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(Color.Theme.brandText)
                // Plattan växer med symbolen vid stor text.
                .padding(12)
                .background(Color.Theme.brandSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text(HouseholdTexts.intro)
                .font(.ui(18, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Color.Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            // Namnet behövs innan inbjudan, så att de andra aldrig ser "Någon".
            VStack(alignment: .leading, spacing: 6) {
                Text(HouseholdTexts.nameTitle)
                    .font(.ui(16, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text)
                nameField
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(HouseholdTexts.nameNote)
                    .font(.ui(15, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Color.Theme.text2)
            }
            inviteButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SurfaceCard())
        .padding(.top, 16)
    }

    private var inviteButton: some View {
        let hasName = !nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button { invitePeople() } label: {
            PrimaryButtonLabel(title: HouseholdTexts.invite)
        }
        .buttonStyle(.pressable)
        .disabled(!hasName || inviting)
        .opacity(hasName && !inviting ? 1 : 0.5)
    }

    // MARK: Med hushåll

    private var participants: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(HouseholdTexts.participants)
            VStack(spacing: 0) {
                ForEach(Array(household.participants.enumerated()), id: \.element.id) { index, participant in
                    if index > 0 { ResultDivider() }
                    if model.canManageMembers, !participant.isOwner {
                        SwipeToDeleteRow(id: participant.id, openRow: $openRow, onDelete: { removing = participant }) {
                            participantRow(participant)
                                .accessibilityAction(named: HouseholdTexts.removeParticipant) { removing = participant }
                        }
                        // Luft mellan Ta bort och ytans kant.
                        .padding(.trailing, 8)
                    } else {
                        participantRow(participant)
                    }
                }
                // De som har bjudits in men inte svarat än. Bara ägaren får dem.
                ForEach(Array(household.invited.enumerated()), id: \.offset) { _, invitee in
                    ResultDivider()
                    HStack(spacing: 12) {
                        Text(HouseholdTexts.invitedName(invitee))
                            .font(.ui(19, weight: .heavy, relativeTo: .headline))
                            .foregroundStyle(Color.Theme.text2)
                        Spacer(minLength: 8)
                        Text(HouseholdTexts.waitingForAnswer)
                            .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Color.Theme.text2)
                    }
                    .padding(.horizontal, 20)
                    .frame(minHeight: 56)
                    .accessibilityElement(children: .combine)
                }
                if model.canManageMembers {
                    ResultDivider()
                    memberButton(HouseholdTexts.inviteMore, symbol: "person.badge.plus") { invitePeople() }
                        .disabled(inviting)
                    ResultDivider()
                    memberButton(HouseholdTexts.revokeInvites, symbol: "link") { revokeInvites() }
                } else if isOwner, !model.invitesWithLink {
                    ResultDivider()
                    memberButton(HouseholdTexts.manage, symbol: "person.badge.plus") { manageMembers() }
                }
            }
            // Raden som sveps får inte synas utanför ytan.
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .modifier(SurfaceCard())
            if model.canManageMembers {
                Text(HouseholdTexts.revokeInvitesFooter)
                    .font(.ui(16, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Color.Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    private func participantRow(_ participant: HouseholdParticipant) -> some View {
        HStack(spacing: 12) {
            Text(HouseholdTexts.participantName(participant, myId: household.myId))
                .font(.ui(19, weight: .heavy, relativeTo: .headline))
                .foregroundStyle(Color.Theme.text)
            Spacer(minLength: 8)
            if participant.isOwner {
                Text(HouseholdTexts.owner)
                    .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
        .background(Color.Theme.surface)
        .accessibilityElement(children: .combine)
    }

    private func memberButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Med största text står ikonen över texten, så att inget ord bryts mitt i.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
                Text(title)
                    .multilineTextAlignment(.leading)
            }
            .font(.ui(18, weight: .heavy, relativeTo: .headline))
            .foregroundStyle(Color.Theme.primary)
            .padding(.vertical, typeSize.isAccessibilitySize ? 12 : 0)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// Ditt namn, som de andra i hushållet ser. Saknas det står en uppmaning över fältet.
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(HouseholdTexts.nameTitle)
            if model.householdNameMissing {
                MessageCard(style: .warning, icon: "person.crop.circle.badge.exclamationmark", title: HouseholdTexts.nameTitle, message: HouseholdTexts.nameMissing)
                    .padding(.bottom, 12)
            }
            nameField
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .modifier(SurfaceCard())
            Text(HouseholdTexts.nameNote)
                .font(.ui(16, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.Theme.text2)
                .padding(.top, 12)
        }
    }

    private var nameField: some View {
        TextField(HouseholdTexts.namePlaceholder, text: $nameDraft)
            .font(.ui(19, weight: .heavy, relativeTo: .headline))
            .foregroundStyle(Color.Theme.text)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit { saveName() }
            .accessibilityLabel(HouseholdTexts.nameTitle)
    }

    /// Sparar namnet om det är ändrat. Ett tomt fält sparas inte, och det förra namnet står kvar.
    private func saveName() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != model.householdPreferences.myName || model.householdNameMissing else { return }
        Task { await model.setHouseholdName(name) }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(HouseholdTexts.notifications)
            if notifyDenied {
                VStack(alignment: .leading, spacing: 12) {
                    MessageCard(style: .warning, icon: "bell.slash", title: NotificationTexts.deniedTitle, message: NotificationTexts.deniedMessage)
                    Button { openNotificationSettings() } label: {
                        Text("Öppna Inställningar")
                            .font(.ui(17, weight: .heavy, relativeTo: .headline))
                            .foregroundStyle(Color.Theme.primary)
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.bottom, 12)
            }
            VStack(spacing: 0) {
                HouseholdToggle(
                    title: HouseholdTexts.silence,
                    symbol: "bell.slash",
                    pulse: 0,
                    isOn: Binding(
                        get: { model.householdPreferences.silenceWhenOthersPlaceOut },
                        set: { on in
                            model.clearStorageError()
                            model.setSilenceWhenOthersPlaceOut(on)
                        }
                    )
                )
                ResultDivider()
                HouseholdToggle(
                    title: HouseholdTexts.notify,
                    symbol: "bell.badge",
                    pulse: notifyPulse,
                    isOn: Binding(
                        get: { pendingNotify ?? model.householdPreferences.notifyWhenOthersPlaceOut },
                        set: { on in setNotify(on) }
                    )
                )
            }
            .modifier(SurfaceCard())
            if let error = model.lastStorageError {
                Text(error)
                    .font(.ui(16, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Color.Theme.warn)
                    .padding(.top, 12)
            }
            Text(HouseholdTexts.deliveryNote)
                .font(.ui(16, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    private var leaveSection: some View {
        Button(role: .destructive) { confirmingLeave = true } label: {
            Text(isOwner ? HouseholdTexts.end : HouseholdTexts.leave)
                .font(.ui(18, weight: .heavy, relativeTo: .headline))
                .foregroundStyle(Color.Theme.destructive)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .modifier(SurfaceCard())
        .padding(.top, 28)
    }

    /// Rubriken över en grupp, som i Inställningar.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.ui(24, weight: .heavy, relativeTo: .title2))
            .foregroundStyle(Color.Theme.text)
            .padding(.top, 28)
            .padding(.bottom, 14)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Åtgärder

    /// Frågan om tillstånd ställs bara när valet slås på, som för påminnelserna. Nekar iOS står valet kvar som av.
    private func setNotify(_ on: Bool) {
        model.clearStorageError()
        pendingNotify = on
        Task {
            let result = await model.setNotifyWhenOthersPlaceOut(on)
            pendingNotify = nil
            notifyDenied = on && result == .denied
            if on, result == .granted { notifyPulse += 1 }
        }
    }

    /// Skapar en inbjudan, och hushållet om det inte finns, och öppnar delningsarket med länken. Namnet sparas först, så
    /// att de andra aldrig ser "Någon".
    private func invitePeople() {
        guard !inviting else { return }
        startedInviting = !isMember
        inviting = true
        Task {
            if startedInviting { await model.setHouseholdName(nameDraft) }
            let url = await model.inviteURL()
            inviting = false
            if let url { InvitePresenter.present(url) }
        }
    }

    private func revokeInvites() {
        Task {
            if await model.revokeInvites() { revokes += 1 }
        }
    }

    /// Systemets vy för deltagarna i iCloud, modalt ovanpå arket. Utan CloudKit (UI-testerna) gör knappen ingenting.
    private func manageMembers() {
        guard let cloud, let share = cloud.share else { return }
        CloudSharingPresenter.present(share: share, sync: cloud)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { await UIApplication.shared.open(url) }
    }
}

/// Systemets delningsark med inbjudan. Länken skapas när knappen trycks, så arket öppnas från UIKit när den finns.
@MainActor
private enum InvitePresenter {
    static func present(_ url: URL) {
        guard let presenter = UIApplication.shared.topViewController else { return }
        let controller = UIActivityViewController(activityItems: [HouseholdTexts.inviteMessage, url], applicationActivities: nil)
        presenter.present(controller, animated: true)
    }
}

/// Ett val i hushållsarket: ikon, rubrik och reglage, som raderna för påminnelser. Med största text står ikonen och reglaget
/// överst och rubriken får hela bredden under dem, så att inget ord bryts mitt i.
private struct HouseholdToggle: View {
    let title: String
    let symbol: String
    let pulse: Int
    @Binding var isOn: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ReminderSymbol(symbol: symbol, pulse: pulse, color: Color.Theme.primary)
                        Spacer(minLength: 0)
                        toggle.labelsHidden()
                    }
                    label
                        .accessibilityHidden(true)
                }
            } else {
                Toggle(isOn: $isOn) {
                    HStack(alignment: .top, spacing: 12) {
                        ReminderSymbol(symbol: symbol, pulse: pulse, color: Color.Theme.primary)
                        label
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.Theme.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .sensoryFeedback(.impact(weight: .light), trigger: pulse)
    }

    private var label: some View {
        Text(title)
            .font(.ui(18, weight: .heavy, relativeTo: .headline))
            .foregroundStyle(Color.Theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var toggle: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .tint(Color.Theme.primary)
    }
}

/// Den vita ytan med kant som grupperna i Inställningar har.
private struct SurfaceCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
    }
}
