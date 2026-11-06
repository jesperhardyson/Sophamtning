import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

/// Adressvyn: nästa tömning, kärlen, påminnelser och hela schemat.
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
    @ScaledMetric(relativeTo: .headline) private var dateWidth: CGFloat = 100

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
        .alert("Byt namn", isPresented: $renaming) {
            TextField("Namn", text: $newName)
            Button("Spara") { rename() }
                .disabled(AddressList.validName(newName) == nil)
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Namnet får vara högst \(AddressList.maxNameLength) tecken.")
        }
        .confirmationDialog("Ta bort adressen?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Ta bort", role: .destructive) { remove() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Adressen, det sparade schemat och dess påminnelser tas bort från telefonen.")
        }
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
                    .buttonStyle(.plain)
                    .padding(.bottom, 16)
                }
                header(detail)
                notice(detail)
                switch detail.mode {
                case .loading:
                    BinLoaderView(textColor: Color.Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.top, 20)
                case .unavailable:
                    EmptyView()
                case .noUpcoming:
                    noUpcoming(detail)
                case .schedule:
                    schedule(detail)
                }
                if detail.mode == .schedule || detail.mode == .noUpcoming {
                    reminders(detail)
                }
                footer(detail)
            }
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

    @ViewBuilder
    private func notice(_ detail: AddressDetail) -> some View {
        switch detail.notice {
        case .savedShown(let fetched):
            MessageCard(
                style: .neutral,
                icon: "icloud.slash",
                title: "Visar senast hämtade schema",
                message: ["Källan svarar inte just nu.", fetched].compactMap { $0 }.joined(separator: " ")
            )
            .padding(.bottom, 20)
        case .sourceUnavailable:
            VStack(spacing: 12) {
                MessageCard(style: .warning, icon: "icloud.slash", title: "Källan svarar inte just nu", message: "Schemat kan inte hämtas. Det betyder inte att adressen saknas.")
                Button { Task { await model.refreshAll(manual: true) } } label: { PrimaryButtonLabel(title: "Försök igen") }
            }
            .padding(.bottom, 20)
        case .notFound:
            VStack(spacing: 12) {
                MessageCard(style: .warning, icon: "location.slash", title: "Adressen hittas inte längre", message: "Källan känner inte igen adressen. Sök upp den på nytt för att få schemat.")
                Button(action: onSearchAgain) { PrimaryButtonLabel(title: "Sök igen") }
            }
            .padding(.bottom, 20)
        case .badRequest:
            // Samma anrop upprepas inte, så det finns ingen Försök igen.
            MessageCard(
                style: .warning,
                icon: "exclamationmark.triangle",
                title: "Källan godtog inte förfrågan",
                message: "Förfrågan för den här adressen avvisades. Det betyder inte att adressen saknas. Appen hämtar schemat på nytt som vanligt, högst en gång i timmen."
            )
            .padding(.bottom, 20)
        case .storageFailed:
            VStack(spacing: 12) {
                MessageCard(style: .warning, icon: "externaldrive.badge.xmark", title: "Schemat kunde inte sparas", message: "Det går inte att spara på telefonen just nu, och schemat visas först när det har sparats. Det betyder inte att adressen saknas.")
                Button { Task { await model.refreshAll(manual: true) } } label: { PrimaryButtonLabel(title: "Försök igen") }
            }
            .padding(.bottom, 20)
        case nil:
            EmptyView()
        }
    }

    private func noUpcoming(_ detail: AddressDetail) -> some View {
        MessageCard(style: .neutral, icon: "calendar.badge.exclamationmark", title: "Inga kommande hämtningar", message: "Schemat kan ta slut tills kommunen har publicerat nästa period.")
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
        sectionTitle("Kärlen")
        VStack(spacing: 0) {
            ForEach(detail.bins) { bin in
                HStack(spacing: 14) {
                    FractionIconView(id: bin.id, info: bin.info)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bin.info.name)
                            .font(.ui(20, weight: .heavy, relativeTo: .headline))
                            .foregroundStyle(Color.Theme.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(bin.dateText)
                            .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Color.Theme.text2)
                    }
                    Spacer(minLength: 8)
                    Text(bin.daysText)
                        .font(.ui(16, weight: .heavy, relativeTo: .callout))
                        .foregroundStyle(Color.Theme.brandText)
                        .fixedSize()
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func nextCard(_ next: HomeContent.Pickup) -> some View {
        HStack(spacing: 20) {
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
                Text(next.longDate)
                    .font(.ui(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.Theme.border))
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
            toggleRow(
                title: "Notis kvällen före",
                text: detail.reminderText,
                isOn: Binding(
                    get: { address.map { model.remindersOn(for: $0) } ?? false },
                    set: { on in
                        model.clearStorageError()
                        Task { _ = await model.setNotifications(on, for: key) }
                    }
                )
            )
            // Live Activity gäller bara huvudadressen.
            if detail.isPrimary {
                ResultDivider()
                toggleRow(
                    title: "Live Activity",
                    text: detail.liveActivityText,
                    isOn: Binding(
                        get: { model.settings.liveActivityOn },
                        set: { model.clearStorageError(); model.setLiveActivity($0) }
                    )
                )
            }
        }
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
    }

    private func toggleRow(title: String, text: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.ui(20, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                Text(text)
                    .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
            }
        }
        .toggleStyle(.switch)
        .tint(Color.Theme.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: Kommande och fot

    @ViewBuilder
    private func footer(_ detail: AddressDetail) -> some View {
        if detail.mode == .schedule {
            sectionTitle("Kommande")
            ResultList {
                ForEach(Array(detail.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { ResultDivider() }
                    scheduleRow(row)
                }
            }
        }
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

    private func scheduleRow(_ row: AddressDetail.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                Text(row.dateText)
                    .font(.ui(18, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                    .frame(width: dateWidth, alignment: .leading)
                FlowLayout(spacing: 8) {
                    ForEach(row.fractions) { fraction in
                        FractionChip(id: fraction.id, info: fraction.info)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Avvikelse och varning tar hela radens bredd, så att ingen text trängs ihop.
            if let deviation = row.deviation {
                Text(deviation)
                    .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let warning = row.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
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
