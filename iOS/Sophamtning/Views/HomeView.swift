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
    /// Ökar när påminnelsen på huvudkortet faktiskt har slagits på.
    @State private var reminderPulse = 0

    private var content: HomeContent {
        HomeContent.make(
            addresses: model.addresses,
            schedules: model.cachedSchedules,
            settings: model.settings,
            now: model.currentDate,
            remindersAllowed: model.notificationAuthorization == .authorized,
            remindersDenied: model.notificationAuthorization == .denied,
            liveActivity: model.currentLiveActivity,
            liveActivitiesEnabled: model.liveActivitiesEnabled,
            liveActivityError: model.liveActivityError,
            missedReminder: model.addresses.first(where: \.isPrimary).flatMap { model.missedReminderText(for: $0) },
            reserveAt: model.addresses.first(where: \.isPrimary).flatMap { model.reserveNotificationDate(for: $0) }
        )
    }

    var body: some View {
        let content = content
        let filled = content.primary != nil && model.storageProblem == nil
        NavigationStack(path: $path) {
            screen(content)
                // Systemets fält: stor rubrik som krymper vid scroll, och knapparna i systemets glas. Tomt läge och
                // lagringsfel har ingen rubrik i fältet, bara knappen för inställningar.
                .navigationTitle(filled ? "Sophämtning" : "")
                // Alltid stort läge: iOS byter inte läge när det tomma läget blir ifyllt medan vyn visas.
                .navigationBarTitleDisplayMode(.large)
                .toolbar { homeToolbar(filled: filled) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
        .background(Color.Theme.bg.ignoresSafeArea())
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

    /// Knapparna uppe till höger delar en glaskapsel. Vid lagringsfel finns inga knappar.
    @ToolbarContentBuilder
    private func homeToolbar(filled: Bool) -> some ToolbarContent {
        if filled {
            // Den stora rubriken i appens typsnitt, med inträdet som korten. I det lilla fältet vid scroll står
            // `navigationTitle`.
            ToolbarItem(placement: .largeTitle) {
                HomeTitle(shown: !entrance.hidesCards)
            }
        }
        if model.storageProblem == nil {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sheet = .settings } label: { Label("Inställningar", systemImage: "gearshape") }
                if filled {
                    Button { sheet = .add } label: { Label("Lägg till", systemImage: "plus") }
                }
            }
        }
    }

    private func filled(primary: HomeContent.Entry, others: [HomeContent.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AddressQuickActions(model: model, key: primary.key, cornerRadius: 28, openRow: $openRow) {
                PrimaryCard(
                    entry: primary,
                    opening: opening(for: primary),
                    reminderPulse: reminderPulse,
                    onOpen: { path.append(primary.key) },
                    onReminderChange: { on in setNotifications(on, for: primary.key) },
                    onOpenSettings: { openNotificationSettings() }
                )
            }
            // En ny huvudadress får ett eget svep, så att inget läge följer med från den borttagna.
            .id(primary.key)
            .padding(.top, 8)
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
                        AddressQuickActions(model: model, key: entry.key, cornerRadius: 20, openRow: $openRow) {
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
    /// Samma flöde som reglaget i adressvyn: frågan om tillstånd ställs bara när valet slås på.
    private func setNotifications(_ on: Bool, for key: AddressKey) {
        model.clearStorageError()
        Task {
            let result = await model.setNotifications(on, for: key)
            // Bara när notiserna faktiskt slogs på, aldrig när iOS nekar eller valet stängs av.
            if on, result == .granted { reminderPulse += 1 }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        Task { await UIApplication.shared.open(url) }
    }

    private func opening(for primary: HomeContent.Entry) -> CalendarTile.Opening? {
        guard entrance.allowsOpeningFlip, case .upcoming(let pickup) = primary.status,
              let from = CalendarFlipTimeline.openingDate(today: StockholmClock.today(now: model.currentDate), pickup: pickup.date) else { return nil }
        let delay = EntranceTimeline.flipDelay(cardIndex: Self.primaryCardIndex, reduceMotion: reduceMotion)
        return CalendarTile.Opening(from: from, begin: entrance.begin?.addingTimeInterval(delay))
    }

    /// När kärlet i tomt läge spelar sitt första varv: när kortet har kommit in efter introt, direkt utan start från början,
    /// och inte medan korten väntar på introt.
    private var emptyBinFirstRound: Date? {
        if entrance.hidesCards { return nil }
        guard let begin = entrance.begin else { return .distantPast }
        return begin.addingTimeInterval(EntranceTimeline.flipDelay(cardIndex: 0, reduceMotion: reduceMotion))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kärlet spelar ett varv när det har kommit in, och efter introt. Ytan ovanför kärlet är till för fraktionen
            // som faller, så kärlet står ungefär där logotypen stod.
            BinRoundView(firstRound: emptyBinFirstRound)
                .frame(maxWidth: .infinity)
                .padding(.top, -24)
                .padding(.bottom, 33)
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

/// Den stora rubriken "Sophämtning" i systemets fält, i Fredoka som resten av appens rubriker. Den kommer in först av
/// allt, före korten.
private struct HomeTitle: View {
    let shown: Bool

    var body: some View {
        Text("Sophämtning")
            .font(.brand(34, relativeTo: .largeTitle))
            .lineLimit(1)
            // Krymper hellre än kapas med största text. Höjden är textens egen, så att fältet inte trycker ihop den.
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(Color.Theme.text)
            // Samma marginal som korten under.
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .cardEntrance(shown: shown, index: 0)
    }
}

enum HomeSheet: String, Identifiable {
    case settings, add, kommun
    var id: String { rawValue }
}

/// En adress under "Fler adresser". Kärlen visas som chips med färg, ikon och kort namn, och raden läses upp med
/// fraktionernas hela namn.
private struct AddressRow: View {
    let entry: HomeContent.Entry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFailure: Bool {
        if case .failed = entry.status { return true }
        return false
    }

    /// Namnet, platsen, datumet och påminnelsen får hela bredden, så att inga ord bryts mitt i. Chipsen står under
    /// texten och bryts mellan chips, och pilen står till höger om dem.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                title
                details
            }
            HStack(spacing: 12) {
                fractions
                    .frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([entry.accessibilityLabel, entry.rowReminder?.text].compactMap { $0 }.joined(separator: ", "))
    }

    private var title: some View {
        Text(entry.title)
            .font(.ui(22, weight: .heavy, relativeTo: .title3))
            .foregroundStyle(Color.Theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            AddressLinesView(lines: entry.lines, size: 17, addressStyle: .body)
            Text(entry.summary)
                .font(.ui(16, weight: .heavy, relativeTo: .callout))
                .foregroundStyle(isFailure ? Color.Theme.warn : Color.Theme.brandText)
                .rollingNumbers(value: entry.summary, reduceMotion: reduceMotion)
            // Bara när notis är på för adressen. Ingen klocka när notis är av.
            if let reminder = entry.rowReminder {
                Label {
                    Text(reminder.text)
                        .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(Color.Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: reminderIcon(reminder))
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(reminder == .denied ? Color.Theme.text2 : Color.Theme.brandText)
                }
                .labelStyle(.titleAndIcon)
                .padding(.top, 2)
            }
        }
    }

    /// Ifylld klocka för en planerad påminnelse, överstruken när iOS inte tillåter notiser, och huvudkortets klocka när
    /// kvällens påminnelse redan passerat.
    private func reminderIcon(_ reminder: HomeContent.RowReminder) -> String {
        switch reminder {
        case .scheduled: "bell.fill"
        case .denied: "bell.slash"
        case .missed: "bell.badge"
        }
    }

    /// Alla kärl för nästa tömning, som chipsen under Kommande i adressvyn.
    @ViewBuilder
    private var fractions: some View {
        switch entry.status {
        case .upcoming(let pickup):
            FlowLayout(spacing: 6) {
                ForEach(pickup.fractions) { fraction in
                    FractionChip(id: fraction.id, info: fraction.info, short: true)
                }
            }
            .accessibilityHidden(true)
        case .loading:
            // Ett litet kärl i stället för chipsen. Raden läses upp av sin egen etikett.
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
