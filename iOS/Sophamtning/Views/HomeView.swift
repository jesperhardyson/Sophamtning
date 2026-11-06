import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Hemskärmen: tomt läge utan adresser, annars huvudkort och övriga adresser.
struct HomeView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: HomeSheet?
    @State private var path: [AddressKey] = []

    private var content: HomeContent {
        HomeContent.make(addresses: model.addresses, schedules: model.cachedSchedules, settings: model.settings, now: model.currentDate)
    }

    var body: some View {
        let content = content
        NavigationStack(path: $path) {
            screen(content)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AddressKey.self) { key in
                    AddressView(model: model, key: key, onSearchAgain: {
                        path = []
                        sheet = .add
                    })
                }
        }
        .task {
            model.applyReminders()
            await model.refreshAll(manual: false)
        }
        .onChange(of: scenePhase) { _, phase in
            // Påminnelserna räknas om när appen blir aktiv, och tillståndet läses om, så att ändringar i iOS Inställningar syns.
            if phase == .active {
                model.applyReminders()
                Task { await model.refreshAll(manual: false) }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings: SettingsView(model: model, onClose: { self.sheet = nil })
            case .add: addFlow(root: .search(source: nil))
            case .kommun: addFlow(root: .kommun)
            }
        }
    }

    private func screen(_ content: HomeContent) -> some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    toolbar(showsAdd: content.primary != nil)
                    if let error = model.lastStorageError {
                        // Ett felmeddelande i flödet, inte en ruta som stör mitt i användningen.
                        Button { model.clearStorageError() } label: {
                            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    }
                    if let primary = content.primary {
                        filled(primary: primary, others: content.others)
                    } else {
                        empty
                    }
                    disclaimer
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refreshAll(manual: true) }
        }
    }

    /// Adressflödet. Efter en sparad adress stängs arket, och hemskärmen hämtar schemat.
    private func addFlow(root: AddRoute) -> some View {
        AddFlowView(model: model, root: root, onClose: { sheet = nil }, onSaved: {
            sheet = nil
            Task { await model.refreshAll(manual: false) }
        })
    }

    // MARK: Delar

    private func toolbar(showsAdd: Bool) -> some View {
        HStack(spacing: 12) {
            Spacer()
            roundButton("gearshape", label: "Inställningar") { sheet = .settings }
            if showsAdd {
                roundButton("plus", label: "Lägg till") { sheet = .add }
            }
        }
        .padding(.top, 8)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Color.Theme.text)
                .frame(width: 44, height: 44)
                .background(Color.Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Color.Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func filled(primary: HomeContent.Entry, others: [HomeContent.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sophämtning")
                .font(.brand(40, relativeTo: .largeTitle))
                .foregroundStyle(Color.Theme.text)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .accessibilityAddTraits(.isHeader)
            PrimaryCard(entry: primary, onReminder: { path.append(primary.key) })
            if !others.isEmpty {
                Text("Fler adresser")
                    .font(.ui(22, weight: .heavy, relativeTo: .title2))
                    .foregroundStyle(Color.Theme.text)
                    .padding(.top, 28)
                    .padding(.bottom, 14)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    ForEach(others) { entry in
                        NavigationLink(value: entry.key) {
                            AddressRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandSymbol()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 36)
            Text("När töms dina kärl?")
                .font(.brand(34, relativeTo: .largeTitle))
                .foregroundStyle(Color.Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("Skriv in din adress så ser du vilka kärl som töms och när. Inget konto behövs.")
                .font(.ui(18, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Color.Theme.text2)
                .padding(.top, 14)
            // Fältet öppnar adressökningen.
            Button { sheet = .add } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(.body))
                        .accessibilityHidden(true)
                    Text("Gata och husnummer")
                        .font(.ui(18, weight: .semibold, relativeTo: .body))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.Theme.text2)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .background(Color.Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.Theme.border))
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            Label {
                Text("Adressen sparas bara i din telefon.")
                    .font(.ui(15, weight: .bold, relativeTo: .subheadline))
            } icon: {
                Image(systemName: "checkmark.shield")
            }
            .foregroundStyle(Color.Theme.brandText)
            .padding(.top, 16)
            Button { sheet = .kommun } label: {
                HStack(spacing: 14) {
                    Image(systemName: "map")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(Color.Theme.brandText)
                        .frame(width: 44, height: 44)
                        .background(Color.Theme.brandSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Finns min kommuns hämtningsschema?")
                        .font(.ui(18, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.Theme.text2)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
    }

    private var disclaimer: some View {
        Text("Inofficiell app, inte kopplad till någon kommun. Vid avvikelser gäller kommunens information.")
            .font(.ui(15, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(Color.Theme.text2)
            .padding(.top, 32)
    }
}

enum HomeSheet: String, Identifiable {
    case settings, add, kommun
    var id: String { rawValue }
}

/// En adress under "Fler adresser". Fraktionerna visas som ikoner, och raden läses upp med fraktionsnamnen.
private struct AddressRow: View {
    let entry: HomeContent.Entry

    private var isFailure: Bool {
        if case .failed = entry.status { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.ui(22, weight: .heavy, relativeTo: .title3))
                    .foregroundStyle(Color.Theme.text)
                Text(entry.subtitle)
                    .font(.ui(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
                Text(entry.summary)
                    .font(.ui(16, weight: .heavy, relativeTo: .callout))
                    .foregroundStyle(isFailure ? Color.Theme.warn : Color.Theme.brandText)
            }
            Spacer(minLength: 0)
            switch entry.status {
            case .upcoming(let pickup):
                HStack(spacing: 6) {
                    ForEach(pickup.fractions.prefix(3)) { fraction in
                        FractionIconView(id: fraction.id, info: fraction.info)
                    }
                }
                .accessibilityHidden(true)
            case .loading:
                // Ett litet kärl i stället för ikonerna. Raden läses upp av sin egen etikett.
                BinLoaderView(width: 48, showsText: false)
                    .accessibilityHidden(true)
            default:
                EmptyView()
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(Color.Theme.text2)
                .accessibilityHidden(true)
        }
        .padding(20)
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
    }
}

#Preview("Tomt") {
    HomeView(model: AppModel(api: SoporClient(version: "preview"), store: LocalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-empty"))))
}
