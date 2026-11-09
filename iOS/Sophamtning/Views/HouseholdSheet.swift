import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

/// Arket Hushåll från Inställningar. Utan hushåll: en förklaring och **Bjud in till hushållet**. Med hushåll: deltagarna,
/// **Hantera medlemmar** för ägaren, valen för notiser och **Lämna hushållet** eller **Avsluta hushållet**.
/// **Bjud in till hushållet** är en `ShareLink` med CloudKit-samarbete, och **Hantera medlemmar** öppnar
/// `UICloudSharingController`. Utan synk med CloudKit (UI-testerna) gör knapparna ingenting.
struct HouseholdSheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloudHousehold) private var cloud
    @State private var invitation = InvitationInProgress()
    @State private var managing = false
    @State private var confirmingLeave = false
    @State private var notifyPulse = 0
    /// Valet för notisen medan frågan om tillstånd pågår, så att reglaget inte hoppar tillbaka under tiden.
    @State private var pendingNotify: Bool?
    @State private var notifyDenied = false

    private var household: HouseholdState { model.household }
    private var isMember: Bool { household.role != .none && household.status != .removed }
    /// Inbjudan står kvar medan delningsarket är öppet, även när jag just blivit ägare.
    private var showsMember: Bool { isMember && !invitation.active }
    private var isOwner: Bool { household.role == .owner }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    notices
                    if showsMember {
                        participants
                        notifications
                        leaveSection
                    } else {
                        invite
                    }
                }
                .padding(.horizontal, PageMargin.horizontal)
                .padding(.bottom, 32)
            }
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
            .sheet(isPresented: $managing) {
                if let cloud, let share = cloud.share {
                    CloudSharingView(share: share, sync: cloud)
                        .ignoresSafeArea()
                }
            }
            // Raden om att man lämnat visas en gång. Nästa gång arket öppnas visas deltagarna.
            .onDisappear {
                model.clearHouseholdNotice()
                invitation.active = false
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
        if notice != nil || shownStatus != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let notice {
                    MessageCard(style: .neutral, icon: "person.2", title: HouseholdTexts.title, message: notice)
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
            inviteButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SurfaceCard())
        .padding(.top, 16)
    }

    @ViewBuilder
    private var inviteButton: some View {
        if let cloud {
            let invitation = invitation
            ShareLink(
                item: HouseholdInvitation(container: cloud.container) {
                    await MainActor.run { invitation.active = true }
                    return try await cloud.makeShare()
                },
                preview: SharePreview(HouseholdTexts.title)
            ) {
                PrimaryButtonLabel(title: HouseholdTexts.invite)
            }
            .buttonStyle(.pressable)
        } else {
            Button {} label: { PrimaryButtonLabel(title: HouseholdTexts.invite) }
                .buttonStyle(.pressable)
        }
    }

    // MARK: Med hushåll

    private var participants: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(HouseholdTexts.participants)
            VStack(spacing: 0) {
                ForEach(Array(household.participants.enumerated()), id: \.element.id) { index, participant in
                    if index > 0 { ResultDivider() }
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
                    .accessibilityElement(children: .combine)
                }
                if isOwner {
                    ResultDivider()
                    Button { managing = cloud?.share != nil } label: {
                        Label(HouseholdTexts.manage, systemImage: "person.badge.plus")
                            .font(.ui(18, weight: .heavy, relativeTo: .headline))
                            .foregroundStyle(Color.Theme.primary)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .modifier(SurfaceCard())
        }
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

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { await UIApplication.shared.open(url) }
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
