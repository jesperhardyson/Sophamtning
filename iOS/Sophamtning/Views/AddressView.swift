import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

/// Adresserna vars schemarader redan har kommit in i den här processen.
@MainActor
private enum ShownSchedules {
    static var keys = ShownOnce<AddressKey>()
}

/// Adressvyn, med det viktigaste först: nästa tömning, de närmaste datumen, kärlen, påminnelser och sist källan.
struct AddressView: View {
    let model: AppModel
    let key: AddressKey
    /// Stänger vyn och öppnar sökningen, för en adress som källan inte längre känner igen.
    let onSearchAgain: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sources: [Source]?
    @State private var link: WebLink?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingRemoval = false
    @State private var notificationPulse = 0
    /// Raderna under "Kommande" och korten för kärlen väntar tills de syns, eftersom de kan ligga nedanför skärmen.
    @State private var rowsRevealed = false
    @State private var binsRevealed = false
    /// Raderna och korten kommer in första gången adressen visas i processen. Bestäms en gång, så att de aldrig blinkar.
    @State private var entrancePlays: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize

    init(model: AppModel, key: AddressKey, onSearchAgain: @escaping () -> Void) {
        self.model = model
        self.key = key
        self.onSearchAgain = onSearchAgain
        _entrancePlays = State(initialValue: !StartIntroState.skipsIntro && ShownSchedules.keys.shouldPlay(key))
    }

    private var address: SavedAddress? { model.addresses.first { $0.key == key } }

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            if let address {
                content(for: address)
            }
        }
        .navigationTitle("Adress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let address { ToolbarItem(placement: .primaryAction) { moreMenu(address) } } }
        .task { sources = await model.sourceList() }
        .inAppBrowser(item: $link)
        .renameAddressAlert(isPresented: $renaming, name: $newName) { rename() }
        .removeAddressConfirmation(isPresented: $confirmingRemoval) { remove() }
    }

    // MARK: Innehåll

    private func content(for address: SavedAddress) -> some View {
        let detail = AddressDetail.make(
            address: address,
            schedule: model.schedule(for: key),
            settings: model.settings,
            sourceName: sources.map { sourceName(address.key.source, in: $0) },
            now: model.currentDate,
            remindersOn: model.missedReminderApplies(to: address),
            reserveAt: model.reserveNotificationDate(for: address)
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error = model.lastStorageError {
                    Button { model.clearStorageError() } label: {
                        MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                    }
                    .buttonStyle(.pressable)
                    .padding(.bottom, 16)
                }
                header(detail)
                Group { notice(detail) }
                    .transition(.opacity)
                switch detail.mode {
                case .loading:
                    ScheduleLoadingCard()
                        .padding(.top, 20)
                        .transition(.opacity)
                case .unavailable:
                    EmptyView()
                case .noUpcoming:
                    noUpcoming(detail)
                        .transition(.opacity)
                case .schedule:
                    Group { schedule(detail) }
                        .transition(.opacity)
                }
                if detail.mode == .schedule || detail.mode == .noUpcoming {
                    reminders(detail)
                }
                footer(detail)
            }
            .animation(Motion.transition(reduceMotion: reduceMotion), value: detail.mode)
            .animation(Motion.transition(reduceMotion: reduceMotion), value: detail.notice)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .refreshable { await model.refreshAll(manual: true) }
    }

    private func header(_ detail: AddressDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.title)
                .font(.ui(34, weight: .black, relativeTo: .largeTitle))
                .foregroundStyle(Color.Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text(detail.subtitle)
                .font(.ui(18, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Color.Theme.text2)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: Lägen

    private func notice(_ detail: AddressDetail) -> some View {
        AddressNoticeView(model: model, notice: detail.notice, onSearchAgain: { onSearchAgain() })
    }

    private func noUpcoming(_ detail: AddressDetail) -> some View {
        NoUpcomingCard()
            .padding(.bottom, 4)
    }

    // MARK: Schema

    @ViewBuilder
    private func schedule(_ detail: AddressDetail) -> some View {
        if let next = detail.next {
            nextCard(next)
        }
        if let warning = detail.nextWarning {
            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Varning från källan", message: warning)
                .padding(.top, 12)
        }
        upcoming(detail)
        bins(detail)
    }

    private func nextCard(_ next: HomeContent.Pickup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AdaptiveStack(spacing: 20) {
                CalendarTile(date: next.date)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NÄSTA TÖMNING")
                        .font(.ui(13, weight: .heavy, relativeTo: .caption))
                        .tracking(1.2)
                        .foregroundStyle(Color.Theme.brandText)
                    Text(next.headline)
                        .font(.ui(32, weight: .heavy, relativeTo: .title))
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                        .foregroundStyle(Color.Theme.text)
                        .rollingNumbers(value: next.headline, reduceMotion: reduceMotion)
                    Text(next.longDate)
                        .font(.ui(17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.Theme.text2)
                }
            }
            // Kärlen som töms den dagen, med färg, ikon och text. Raderna bryts när de inte får plats.
            FlowLayout(spacing: 8) {
                ForEach(next.fractions) { fraction in
                    FractionChip(id: fraction.id, info: fraction.info)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.Theme.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(next.accessibilityLabel)
    }

    /// De tre närmaste datumen, och länken till hela schemat när det finns fler.
    @ViewBuilder
    private func upcoming(_ detail: AddressDetail) -> some View {
        if typeSize.isAccessibilitySize {
            // Under varandra med största text, så att inget ord bryts mitt i.
            sectionTitle("Kommande")
            if detail.hasFullSchedule {
                fullScheduleLink
                    .padding(.bottom, 12)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                sectionTitle("Kommande")
                Spacer(minLength: 0)
                if detail.hasFullSchedule { fullScheduleLink }
            }
        }
        ScheduleList(rows: detail.upcoming, shown: rowsRevealed || !entrancePlays || voiceOver)
            .onScrollVisibilityChange(threshold: 0.02) { visible in
                guard visible, !rowsRevealed else { return }
                rowsRevealed = true
                ShownSchedules.keys.markShown(key)
            }
    }

    private var fullScheduleLink: some View {
        NavigationLink {
            FullScheduleView(model: model, key: key, onSearchAgain: { onSearchAgain() })
        } label: {
            HStack(spacing: 4) {
                Text("Hela schemat")
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(.ui(16, weight: .heavy, relativeTo: .callout))
            .foregroundStyle(Color.Theme.primary)
        }
        .buttonStyle(.pressable)
    }

    /// Nästa tömning per kärl, som kort i sidled. Nästa kort syns till hälften, så att det märks att det går att scrolla.
    @ViewBuilder
    private func bins(_ detail: AddressDetail) -> some View {
        sectionTitle("Kärlen")
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: BinCardMetrics.spacing) {
                ForEach(Array(detail.bins.enumerated()), id: \.element.id) { index, bin in
                    // Kortet väljer själv sin bredd efter namnet.
                    BinCard(bin: bin)
                        .rowEntrance(shown: binsRevealed || !entrancePlays || voiceOver, index: index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 24, for: .scrollContent)
        // Korten går ut till skärmens kant, medan resten av vyn har marginal.
        .padding(.horizontal, -24)
        .onScrollVisibilityChange(threshold: 0.02) { visible in
            if visible { binsRevealed = true }
        }
    }

    // MARK: Påminnelser

    @ViewBuilder
    private func reminders(_ detail: AddressDetail) -> some View {
        sectionTitle("Påminnelser")
        if let error = model.reminderError {
            MessageCard(style: .warning, icon: "bell.slash", title: "Påminnelser saknas", message: error)
                .padding(.bottom, 12)
        }
        if let missed = detail.missedReminder {
            MessageCard(style: .neutral, icon: "clock.badge.exclamationmark", title: "Påminnelsen har passerat", message: missed)
                .padding(.bottom, 12)
        }
        if model.notificationAuthorization == .denied {
            VStack(alignment: .leading, spacing: 12) {
                MessageCard(style: .warning, icon: "bell.slash", title: "Notiser är avstängda", message: "Du har stängt av notiser för Sophämtning i iOS.")
                Button { openNotificationSettings() } label: {
                    Text("Öppna Inställningar")
                        .font(.ui(17, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.primary)
                }
            }
            .padding(.bottom, 12)
        }
        if detail.isPrimary {
            LiveActivityNotices(model: model, edge: .bottom)
        }
        VStack(spacing: 0) {
            ReminderToggleRow(
                title: "Notis kvällen före",
                text: detail.reminderText,
                symbol: "bell.badge",
                pulse: notificationPulse,
                isOn: Binding(
                    get: { address.map { model.remindersOn(for: $0) } ?? false },
                    set: { on in
                        model.clearStorageError()
                        Task {
                            let result = await model.setNotifications(on, for: key)
                            // Bara när notiserna faktiskt slogs på, aldrig när iOS nekar eller valet stängs av.
                            if on, result == .granted { notificationPulse += 1 }
                        }
                    }
                )
            )
            // Live Activity gäller bara huvudadressen.
            if detail.isPrimary {
                ResultDivider()
                LiveActivityToggleRow(model: model, text: detail.liveActivityText)
            }
        }
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
    }

    // MARK: Fot

    @ViewBuilder
    private func footer(_ detail: AddressDetail) -> some View {
        if let fetched = detail.fetchedText, detail.mode != .loading {
            Text(fetched)
                .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.Theme.text2)
                .padding(.top, 20)
        }
        if let web = detail.webLink.flatMap({ WebLink(url: $0) }) {
            Button { link = web } label: {
                Text("Kommunens information")
                    .font(.ui(18, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.primary)
            }
            .padding(.top, detail.fetchedText == nil ? 20 : 8)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.ui(22, weight: .heavy, relativeTo: .title2))
            .foregroundStyle(Color.Theme.text)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Meny

    private func moreMenu(_ address: SavedAddress) -> some View {
        Menu {
            Button { newName = address.displayName; renaming = true } label: { Label("Byt namn", systemImage: "pencil") }
            if !address.isPrimary {
                Button { model.clearStorageError(); model.setPrimary(key) } label: { Label("Gör till huvudadress", systemImage: "house") }
            }
            Button(role: .destructive) { confirmingRemoval = true } label: { Label("Ta bort", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Mer")
    }

    private func rename() {
        model.clearStorageError()
        model.rename(key, to: newName)
    }

    private func remove() {
        model.clearStorageError()
        model.remove(key)
        // Gick borttagningen inte att spara är adressen kvar, och felet visas här.
        if address == nil { dismiss() }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        Task { await UIApplication.shared.open(url) }
    }
}
