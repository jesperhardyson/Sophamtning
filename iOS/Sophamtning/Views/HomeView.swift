import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Hemskärmen: tomt läge utan adresser, annars huvudkort och övriga adresser.
struct HomeView: View {
    let model: AppModel
    /// Korten och kalenderbladet vid start från början.
    let entrance: StartEntrance
    let onEntranceFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: HomeSheet?
    @State private var path: [AddressKey] = []
    /// Adressen som ersätts när sökningen "Sök igen" sparar en ny, och adresserna som fanns innan sökningen öppnades.
    @State private var replacing: AddressKey?
    @State private var knownKeys: Set<AddressKey> = []
    @State private var confirmingStartOver = false
    /// Adressen som står öppen efter ett svep. Bara en åt gången, och scrollning stänger den.
    @State private var openRow: AddressKey?
    /// Ökar när en adress eller ett område har sparats. Räknaren ligger här, eftersom arket stängs i samma
    /// uppdatering, så att den lätta vibrationen alltid hinner spelas.
    @State private var saves = 0

    private var content: HomeContent {
        HomeContent.make(
            addresses: model.addresses,
            schedules: model.cachedSchedules,
            settings: model.settings,
            now: model.currentDate,
            remindersAllowed: model.notificationAuthorization == .authorized,
            liveActivity: model.currentLiveActivity,
            liveActivitiesEnabled: model.liveActivitiesEnabled,
            liveActivityError: model.liveActivityError,
            missedReminder: model.addresses.first(where: \.isPrimary).flatMap { model.missedReminderText(for: $0) },
            reserveAt: model.addresses.first(where: \.isPrimary).flatMap { model.reserveNotificationDate(for: $0) }
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
        .task(id: entrance.begin) {
            // Starten är klar när kalenderbladet har bläddrats klart, så länge som bläddringen faktiskt tar. Därefter visas
            // brickan som vanligt.
            guard entrance.begin != nil else { return }
            let flip = EntranceTimeline.flipDelay(cardIndex: Self.primaryCardIndex, reduceMotion: reduceMotion) + openingFlipDuration(content.primary)
            guard (try? await Task.sleep(for: .seconds(flip))) != nil else { return }
            onEntranceFinished()
        }
        .task {
            model.applyReminders()
            await model.refreshAll(manual: false)
        }
        .task {
            // Slås Live Activities på eller av i iOS medan appen lever räknas påminnelserna om.
            for await _ in LiveActivityEnablement.changes() {
                model.applyReminders()
            }
        }
        // En öppen rad stängs när en adress öppnas eller stängs, och när appen byter läge.
        .onChange(of: path) { openRow = nil }
        .onChange(of: scenePhase) { _, phase in
            openRow = nil
            // Påminnelserna räknas om när appen blir aktiv, och tillståndet läses om, så att ändringar i iOS Inställningar syns.
            if phase == .active {
                model.applyReminders()
                Task { await model.refreshAll(manual: false) }
            } else if phase == .background {
                // Bokar nästa bakgrundsuppdatering, tidigast om en timme.
                BackgroundRefresh.schedule()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: saves)
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
                        .buttonStyle(.pressable)
                        .padding(.top, 12)
                    }
                    if let error = model.reminderError, model.storageProblem == nil, content.primary != nil {
                        // Samma meddelande som i adressvyn, så att ett fel efter ett val i snabbmenyn syns.
                        MessageCard(style: .warning, icon: "bell.slash", title: "Påminnelser saknas", message: error)
                            .padding(.top, 12)
                    }
                    if let problem = model.storageProblem {
                        // En fil som inte går att läsa är inte ett tomt läge: inget är raderat, och inget skrivs över.
                        storageProblem(problem)
                    } else if let primary = content.primary {
                        LiveActivityNotices(model: model, edge: .top, showsError: false)
                        filled(primary: primary, others: content.others)
                    } else {
                        empty
                    }
                    disclaimer
                        // Sist i ordningen, oavsett hur många kort det finns.
                        .cardEntrance(shown: !entrance.hidesCards, index: min(2 + content.others.count + 1, 6))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .closesOpenSwipeRow($openRow)
            }
            // Ett tryck nedanför innehållet stänger också den öppna raden.
            .gesture(TapGesture().onEnded { openRow = nil }, including: openRow == nil ? .subviews : .all)
            .refreshable { await model.refreshAll(manual: true) }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { openRow = nil }
            }
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
            saves += 1
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
                .minimumScaleFactor(0.5)
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
                .buttonStyle(.pressable)
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
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private func filled(primary: HomeContent.Entry, others: [HomeContent.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sophämtning")
                .font(.brand(40, relativeTo: .largeTitle))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.Theme.text)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .accessibilityAddTraits(.isHeader)
                .cardEntrance(shown: !entrance.hidesCards, index: 0)
            AddressQuickActions(model: model, key: primary.key, cornerRadius: 28, buttonShape: .round, openRow: $openRow) {
                PrimaryCard(entry: primary, opening: opening(for: primary), onOpen: { path.append(primary.key) })
            }
            // En ny huvudadress får ett eget svep, så att inget läge följer med från den borttagna.
            .id(primary.key)
            .cardEntrance(shown: !entrance.hidesCards, index: Self.primaryCardIndex)
            if !others.isEmpty {
                Text("Fler adresser")
                    .font(.ui(22, weight: .heavy, relativeTo: .title2))
                    .foregroundStyle(Color.Theme.text)
                    .padding(.top, 28)
                    .padding(.bottom, 14)
                    .accessibilityAddTraits(.isHeader)
                    .cardEntrance(shown: !entrance.hidesCards, index: 2)
                VStack(spacing: 12) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, entry in
                        AddressQuickActions(model: model, key: entry.key, cornerRadius: 20, buttonShape: .fullHeight, openRow: $openRow) {
                            NavigationLink(value: entry.key) {
                                AddressRow(entry: entry)
                            }
                            .buttonStyle(.pressable)
                        }
                        .cardEntrance(shown: !entrance.hidesCards, index: 3 + index)
                    }
                }
            }
        }
    }

    /// Huvudkortets plats i ordningen, efter rubriken.
    private static let primaryCardIndex = 1

    /// Hur länge kalenderbladet bläddras vid starten, eller 0 när det inte bläddras.
    private func openingFlipDuration(_ primary: HomeContent.Entry?) -> TimeInterval {
        guard case .upcoming(let pickup) = primary?.status,
              let from = CalendarFlipTimeline.openingDate(today: StockholmClock.today(now: model.currentDate), pickup: pickup.date) else { return 0 }
        let pages = CalendarFlipTimeline.dates(from: from, to: pickup.date, reduceMotion: reduceMotion).count
        // Marginalen gör att brickan hinner vibrera vid landningen innan starten avslutas, även när båda väcks samtidigt.
        return CalendarFlipTimeline.duration(pages: pages, reduceMotion: reduceMotion) + Self.landingMargin
    }

    /// Tid efter sista bladets landning innan starten avslutas.
    private static let landingMargin: TimeInterval = 0.05

    /// Vändningen av kalenderbladet från dagens datum till tömningsdagen. Bara under starten, och inte om tömningen är i dag.
    private func opening(for primary: HomeContent.Entry) -> CalendarTile.Opening? {
        guard entrance.allowsOpeningFlip, case .upcoming(let pickup) = primary.status,
              let from = CalendarFlipTimeline.openingDate(today: StockholmClock.today(now: model.currentDate), pickup: pickup.date) else { return nil }
        let delay = EntranceTimeline.flipDelay(cardIndex: Self.primaryCardIndex, reduceMotion: reduceMotion)
        return CalendarTile.Opening(from: from, begin: entrance.begin?.addingTimeInterval(delay))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandSymbol()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .cardEntrance(shown: !entrance.hidesCards, index: 0)
            Text("När töms dina kärl?")
                .font(.brand(34, relativeTo: .largeTitle))
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.Theme.text)
                .accessibilityAddTraits(.isHeader)
                .cardEntrance(shown: !entrance.hidesCards, index: 1)
            Text("Skriv in din adress så ser du vilka kärl som töms och när. Inget konto behövs.")
                .font(.ui(18, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Color.Theme.text2)
                .padding(.top, 14)
                .cardEntrance(shown: !entrance.hidesCards, index: 1)
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
            .buttonStyle(.pressable)
            .padding(.top, 24)
            .cardEntrance(shown: !entrance.hidesCards, index: 2)
            Label {
                Text("Adressen sparas bara i din telefon.")
                    .font(.ui(15, weight: .bold, relativeTo: .subheadline))
            } icon: {
                Image(systemName: "checkmark.shield")
            }
            .foregroundStyle(Color.Theme.brandText)
            .padding(.top, 16)
            .cardEntrance(shown: !entrance.hidesCards, index: 3)
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
            .buttonStyle(.pressable)
            .padding(.top, 20)
            .cardEntrance(shown: !entrance.hidesCards, index: 4)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isFailure: Bool {
        if case .failed = entry.status { return true }
        return false
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Ikonerna under texten, så att platsen och påminnelsen får hela bredden och inga ord bryts mitt i.
                VStack(alignment: .leading, spacing: 12) {
                    texts
                    HStack(spacing: 12) {
                        icons
                        Spacer(minLength: 0)
                        chevron
                    }
                }
            } else {
                HStack(spacing: 12) {
                    texts
                    Spacer(minLength: 0)
                    icons
                    chevron
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([entry.accessibilityLabel, entry.reminderText].compactMap { $0 }.joined(separator: ", "))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.ui(22, weight: .heavy, relativeTo: .title3))
                .foregroundStyle(Color.Theme.text)
            Text(entry.subtitle)
                .font(.ui(17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(Color.Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.summary)
                .font(.ui(16, weight: .heavy, relativeTo: .callout))
                .foregroundStyle(isFailure ? Color.Theme.warn : Color.Theme.brandText)
                .rollingNumbers(value: entry.summary, reduceMotion: reduceMotion)
            // Bara när notis är på för adressen, med samma text som huvudkortet. Ingen klocka när notis är av.
            if let reminder = entry.reminderText {
                Label {
                    Text(reminder)
                        .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(Color.Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "bell.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Color.Theme.brandText)
                }
                .labelStyle(.titleAndIcon)
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var icons: some View {
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
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .foregroundStyle(Color.Theme.text2)
            .accessibilityHidden(true)
    }
}

#Preview("Tomt") {
    HomeView(model: AppModel(api: SoporClient(version: "preview"), store: LocalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-empty"))), entrance: StartEntrance(plays: false), onEntranceFinished: {})
}
