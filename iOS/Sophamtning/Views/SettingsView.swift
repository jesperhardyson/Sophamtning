import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

/// Länken till integritetspolicyn på `sopor.hardyson.se`.
let privacyLink = WebLink(url: URL(string: "https://sopor.hardyson.se/integritet")!)!

private enum SettingsRoute: Hashable {
    case time, primary, sources
}

/// Inställningar i ett ark: påminnelsetid, huvudadress, Live Activity och om appen.
struct SettingsView: View {
    let model: AppModel
    let onClose: () -> Void

    @State private var sources: [Source]?
    @State private var sourcesLoading = true
    @State private var link: WebLink?

    private var sourceCount: Int? { sources.map { $0.filter { !$0.testData }.count } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let error = model.lastStorageError {
                            Button { model.clearStorageError() } label: {
                                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                        reminders
                        about
                        MessageCard(
                            style: .neutral,
                            icon: "info.circle",
                            title: "Inofficiell app",
                            message: "Sophämtning är inte kopplad till någon kommun eller något avfallsbolag. Vid avvikelser gäller alltid kommunens information."
                        )
                        .padding(.top, 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Inställningar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Stäng")
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .time: ReminderTimeView(model: model)
                case .primary: PrimaryAddressView(model: model)
                case .sources: SourcesView(sources: sources, loading: sourcesLoading, onRetry: { await loadSources() })
                }
            }
            .task { await loadSources() }
            .inAppBrowser(item: $link)
        }
    }

    private func loadSources() async {
        sourcesLoading = true
        sources = await model.sourceList()
        sourcesLoading = false
    }

    // MARK: Delar

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Påminnelser")
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.time) {
                    SettingsRow(title: "Påminnelsetid", value: SwedishFormat.clock(minutes: model.settings.reminderMinutes))
                }
                if let primary = model.addresses.first(where: \.isPrimary) {
                    ResultDivider()
                    NavigationLink(value: SettingsRoute.primary) {
                        SettingsRow(title: "Huvudadress", value: primary.displayName)
                    }
                }
                ResultDivider()
                LiveActivityToggleRow(model: model, text: AddressDetail.liveActivityText(settings: model.settings))
            }
            .buttonStyle(.plain)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
            LiveActivityNotices(model: model, edge: .top)
            if let missed = model.missedReminderText {
                MessageCard(style: .neutral, icon: "clock.badge.exclamationmark", title: "Påminnelsen har passerat", message: missed)
                    .padding(.top, 12)
            }
            Text("Påminnelsetiden gäller kvällen före, mellan 15:00 och 23:00. En Live Activity försvinner senast 12 timmar efter starten, så en sen tid håller den kvar längre på morgonen. Notiser väljer du per adress.")
                .font(.ui(16, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.Theme.text2)
                .padding(.top, 16)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Om appen")
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.sources) {
                    SettingsRow(title: "Datakällor", value: sourceCount.map(String.init) ?? "")
                }
                ResultDivider()
                Button { link = privacyLink } label: {
                    SettingsRow(title: "Integritet", value: "")
                }
                ResultDivider()
                SettingsRow(title: "Version", value: version, showsChevron: false)
            }
            .buttonStyle(.plain)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SophamtningKitInfo.version
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.ui(24, weight: .heavy, relativeTo: .title2))
            .foregroundStyle(Color.Theme.text)
            .padding(.top, 28)
            .padding(.bottom, 14)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Meddelanden om Live Activity. Valet behålls när iOS stänger av dem, och notisen står kvar.
/// Utan meddelanden tar vyn ingen plats, och `edge` får då inget avstånd.
struct LiveActivityNotices: View {
    let model: AppModel
    let edge: Edge.Set
    /// Hemkortet visar felet själv.
    var showsError = true

    private var systemOff: Bool { model.settings.liveActivityOn && !model.liveActivitiesEnabled }

    private var error: String? { showsError ? model.liveActivityError : nil }

    var body: some View {
        if systemOff || error != nil {
            VStack(alignment: .leading, spacing: 12) {
                if systemOff {
                    MessageCard(style: .warning, icon: "bell.slash", title: "Live Activities är avstängda", message: "Du har stängt av dem för Sophämtning i iOS.")
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        Task { await UIApplication.shared.open(url) }
                    } label: {
                        Text("Öppna Inställningar")
                            .font(.ui(17, weight: .heavy, relativeTo: .headline))
                            .foregroundStyle(Color.Theme.primary)
                    }
                    .buttonStyle(.plain)
                }
                if let error {
                    MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Live Activity saknas", message: error)
                }
            }
            .padding(edge, 12)
        }
    }
}

/// En rad i en inställningslista: rubrik, värde och pil.
private struct SettingsRow: View {
    let title: String
    let value: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            AdaptiveStack(spacing: 8, verticalSpacing: 2) {
                Text(title)
                    .font(.ui(20, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value)
                        .font(.ui(19, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.Theme.text2)
                }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.Theme.text2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Ett val i en lista med bock, som tid och huvudadress.
private struct ChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.ui(20, weight: selected ? .heavy : .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Color.Theme.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 15:00 till 23:00 i steg om 15 minuter. Går sparandet fel visas felet och valet är kvar som förut.
private struct ReminderTimeView: View {
    let model: AppModel
    private let times = Array(stride(from: 15 * 60, through: 23 * 60, by: 15))

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if let error = model.lastStorageError {
                        Button { model.clearStorageError() } label: {
                            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                        }
                        .buttonStyle(.plain)
                    }
                    ResultList {
                        ForEach(Array(times.enumerated()), id: \.element) { index, minutes in
                            if index > 0 { ResultDivider() }
                            ChoiceRow(title: SwedishFormat.clock(minutes: minutes), selected: minutes == model.settings.reminderMinutes) {
                                model.clearStorageError()
                                model.setReminderMinutes(minutes)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Påminnelsetid")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrimaryAddressView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if let error = model.lastStorageError {
                        Button { model.clearStorageError() } label: {
                            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                        }
                        .buttonStyle(.plain)
                    }
                    ResultList {
                        ForEach(Array(model.addresses.enumerated()), id: \.element.key) { index, address in
                            if index > 0 { ResultDivider() }
                            ChoiceRow(title: address.displayName, selected: address.isPrimary) {
                                model.clearStorageError()
                                model.setPrimary(address.key)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Huvudadress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Källorna från `/kallor`, som en enkel lista, och Wikidata för ortlistan.
private struct SourcesView: View {
    let sources: [Source]?
    let loading: Bool
    let onRetry: () async -> Void

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let sources {
                        let shown = sources.filter { !$0.testData }
                        Text("Schemat hämtas från \(shown.count) källor.")
                            .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Color.Theme.text2)
                        ResultList {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, source in
                                if index > 0 { ResultDivider() }
                                row(source.name)
                            }
                            ResultDivider()
                            row("Wikidata (CC0)", detail: "Ortlistan för kommunfrågan")
                        }
                    } else if loading {
                        // Medan listan hämtas visas ingen felruta.
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Hämtar källor…")
                                .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                                .foregroundStyle(Color.Theme.text2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        MessageCard(style: .warning, icon: "icloud.slash", title: "Kunde inte hämta källistan", message: "Försök igen om en stund.")
                        Button { Task { await onRetry() } } label: { PrimaryButtonLabel(title: "Försök igen") }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Datakällor")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.ui(18, weight: .heavy, relativeTo: .headline))
                .foregroundStyle(Color.Theme.text)
            if let detail {
                Text(detail)
                    .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
