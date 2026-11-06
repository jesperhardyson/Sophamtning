import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Hemskärmen: tomt läge utan adresser, annars huvudkort och övriga adresser.
struct HomeView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: HomeSheet?
    @State private var path: [AddressKey] = []
    /// Adressen som ersätts när sökningen "Sök igen" sparar en ny, och adresserna som fanns innan sökningen öppnades.
    @State private var replacing: AddressKey?
    @State private var knownKeys: Set<AddressKey> = []
    @State private var confirmingStartOver = false

    private var content: HomeContent {
        HomeContent.make(
            addresses: model.addresses,
            schedules: model.cachedSchedules,
            settings: model.settings,
            now: model.currentDate,
            remindersAllowed: model.notificationAuthorization == .authorized
        )
    }

    var body: some View {
        let content = content
        NavigationStack(path: $path) {
            screen(content)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AddressKey.self) { key in
                    AddressView(model: model, key: key, onSearchAgain: {
                        path = []
                        replacing = key
                        knownKeys = Set(model.addresses.map(\.key))
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
            } else if phase == .background {
                // Bokar nästa bakgrundsuppdatering, tidigast om en timme.
                BackgroundRefresh.schedule()
            }
        }
        .sheet(item: $sheet, onDismiss: { replacing = nil }) { sheet in
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
                    if model.storageProblem == nil { toolbar(showsAdd: content.primary != nil) }
                    if let error = model.lastStorageError {
                        // Ett felmeddelande i flödet, inte en ruta som stör mitt i användningen.
                        Button { model.clearStorageError() } label: {
                            MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: "\(error) Tryck för att stänga.")
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    }
                    if let problem = model.storageProblem {
                        // En fil som inte går att läsa är inte ett tomt läge: inget är raderat, och inget skrivs över.
                        storageProblem(problem)
                    } else if let primary = content.primary {
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
            // "Sök igen": den gamla adressen ersätts först nu, när den nya är sparad.
            if let old = replacing, let new = model.addresses.first(where: { !knownKeys.contains($0.key) })?.key {
                model.replace(old, with: new)
            }
            sheet = nil
            Task { await model.refreshAll(manual: false) }
        })
    }

    // MARK: Delar

    private func storageProblem(_ problem: AppModel.StorageProblem) -> some View {
        let addresses = problem == .addressesUnreadable || problem == .addressesUnavailable
        // Bara en skadad fil kan göras om. En fil som bara är otillgänglig just nu (till exempel före upplåsning) rörs aldrig.
        let corrupt = problem == .addressesUnreadable || problem == .settingsUnreadable
        let title: String
        switch problem {
        case .addressesUnreadable: title = "Dina sparade adresser kunde inte läsas"
        case .addressesUnavailable: title = "Dina adresser kan inte läsas just nu"
        case .settingsUnreadable: title = "Dina inställningar kunde inte läsas"
        case .settingsUnavailable: title = "Dina inställningar kan inte läsas just nu"
        }
        return VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.brand(30, relativeTo: .largeTitle))
                .foregroundStyle(Color.Theme.text)
                .padding(.top, 32)
                .accessibilityAddTraits(.isHeader)
            MessageCard(
                style: .warning,
                icon: "externaldrive.badge.xmark",
                title: "Inget har raderats",
                message: corrupt
                    ? "Filen på telefonen är skadad. Försök igen. Fungerar det inte kan du börja om."
                    : "Lås upp telefonen och försök igen. Är den upplåst kan filen vara skyddad en kort stund efter en omstart."
            )
            Button { model.retryStorage() } label: { PrimaryButtonLabel(title: "Försök igen") }
            if corrupt {
                Button { confirmingStartOver = true } label: {
                    Text("Börja om")
                        .font(.ui(17, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
        }
        .confirmationDialog(addresses ? "Börja om utan sparade adresser?" : "Använda standardinställningarna?", isPresented: $confirmingStartOver, titleVisibility: .visible) {
            Button(addresses ? "Ta bort sparade adresser och börja om" : "Använd standardinställningar", role: .destructive) {
                model.clearStorageError()
                Task { await model.startOver() }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text(addresses
                ? "Dina sparade adresser tas bort från appen och appens väntande påminnelser avbryts. Den skadade filen sparas åt sidan på telefonen. Därefter kan du lägga till adresser igen."
                : "Påminnelsetid och Live Activity återställs till standard (kl. 18:00, Live Activity av). Dina adresser behålls. Den skadade filen sparas åt sidan på telefonen.")
        }
    }

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
            PrimaryCard(entry: primary, onOpen: { path.append(primary.key) })
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
