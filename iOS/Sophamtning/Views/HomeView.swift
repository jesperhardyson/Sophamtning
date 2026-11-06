import SophamtningDesign
import SophamtningKit
import SwiftUI

/// Hemskärmen: tomt läge utan adresser, annars huvudkort och övriga adresser.
struct HomeView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: HomeSheet?

    private var content: HomeContent {
        HomeContent.make(addresses: model.addresses, schedules: model.cachedSchedules, settings: model.settings, now: model.currentDate)
    }

    var body: some View {
        let content = content
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    toolbar(showsAdd: content.primary != nil)
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
        .task { await model.refreshAll(manual: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshAll(manual: false) } }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings: SettingsSheet()
            case .add: TemporarySheet(title: "Lägg till adress")
            case .kommun: TemporarySheet(title: "Finns min kommuns hämtningsschema?")
            }
        }
        .alert("Något gick fel", isPresented: Binding(get: { model.lastStorageError != nil }, set: { if !$0 { model.clearStorageError() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastStorageError ?? "")
        }
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
                .font(.system(size: 18, weight: .semibold))
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
            // Påminnelsekortet kopplas i uppgift 12. Tills dess gör det ingenting.
            PrimaryCard(entry: primary, onReminder: {})
            if !others.isEmpty {
                Text("Fler adresser")
                    .font(.ui(22, weight: .heavy, relativeTo: .title2))
                    .foregroundStyle(Color.Theme.text)
                    .padding(.top, 28)
                    .padding(.bottom, 14)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    ForEach(others) { entry in
                        // Raden öppnar inget än. Adressvyn kopplas i uppgift 12.
                        AddressRow(entry: entry)
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            EmptyHero()
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
            // Sökfältet beter sig som Lägg till tills uppgift 11 ersätter arket.
            Button { sheet = .add } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
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
            // Raden öppnar ett tillfälligt ark tills uppgift 11 ersätter det.
            Button { sheet = .kommun } label: {
                HStack(spacing: 14) {
                    Image(systemName: "map")
                        .font(.system(size: 20, weight: .semibold))
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
                    .foregroundStyle(entry.status == .failed ? Color.Theme.warn : Color.Theme.brandText)
            }
            Spacer(minLength: 0)
            if case .upcoming(let pickup) = entry.status {
                HStack(spacing: 6) {
                    ForEach(pickup.fractions.prefix(3)) { fraction in
                        FractionIconView(id: fraction.id, info: fraction.info)
                    }
                }
                .accessibilityHidden(true)
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

/// Appens märke för tomt läge: en kalender i en rundad pil.
private struct EmptyHero: View {
    private let size: CGFloat = 150
    private let line: CGFloat = 20
    private let startDegrees = 10.0
    private let sweep = 0.875

    var body: some View {
        let radius = (size - line) / 2
        let end = Angle.degrees(startDegrees + sweep * 360)
        ZStack {
            Circle()
                .inset(by: line / 2)
                .trim(from: 0, to: sweep)
                .stroke(Color.Theme.primary, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(startDegrees))
            // Pilspetsen sitter i slutet av bågen och pekar längs den.
            Image(systemName: "triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.Theme.primary)
                .rotationEffect(end + .degrees(180))
                .offset(x: radius * cos(end.radians), y: radius * sin(end.radians))
            Image(systemName: "calendar")
                .font(.system(size: 62, weight: .bold))
                .foregroundStyle(Color.Theme.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Inställningar i sin enklaste form tills uppgift 12 bygger skärmen. Visar bara att appen är inofficiell.
private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                MessageCard(
                    style: .neutral,
                    icon: "info.circle",
                    title: "Inofficiell app",
                    message: "Appen är inte kopplad till någon kommun. Vid avvikelser gäller kommunens information."
                )
                Spacer()
            }
            .padding(24)
            .background(Color.Theme.bg)
            .navigationTitle("Inställningar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Klar") { dismiss() } }
        }
    }
}

/// Tillfälligt ark som uppgift 11 ersätter med sökning och kommunkontroll.
private struct TemporarySheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Kommer snart.")
                .font(.ui(17, weight: .semibold))
                .foregroundStyle(Color.Theme.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.Theme.bg)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Stäng") { dismiss() } }
        }
    }
}

#Preview("Tomt") {
    HomeView(model: AppModel(api: SoporClient(version: "preview"), store: LocalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-empty"))))
}
