import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Finns min kommuns hämtningsschema?" Svaret kommer medan man skriver.
struct KommunCheckView: View {
    let model: AppModel

    private struct Trigger: Hashable {
        var query: String
        var attempt: Int
    }

    /// Svaret och, för en täckt kommun, områdena som `/omraden` gav.
    private struct KommunResult {
        var answer: KommunAnswer
        var areas: [SearchHit]
    }

    @State private var query = ""
    @State private var attempt = 0
    /// Sant medan ett nytt svar hämtas. Det gamla svaret tonas ned och går inte att trycka på.
    @State private var updating = false
    /// Det senaste svaret. Det ligger kvar medan ett nytt hämtas, så att rutan inte blinkar.
    @State private var result = KommunResult(answer: .empty, areas: [])
    @State private var latest = LatestOnly()
    @State private var webLink: WebLink?
    private let index = try? PlaceIndex.bundled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Finns min kommuns hämtningsschema?")
                    .font(.brand(34, relativeTo: .largeTitle))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color.Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Skriv din kommun eller ort. Svaret kommer medan du skriver.")
                    .font(.ui(18, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
                    .padding(.top, 14)
                FlowSearchField(placeholder: "Kommun eller ort", text: $query)
                    .padding(.top, 24)
                answerView
                    .opacity(updating ? 0.4 : 1)
                    .allowsHitTesting(!updating)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .inAppBrowser(item: $webLink)
        .background(Color.Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Trigger(query: query, attempt: attempt)) { await update() }
    }

    // MARK: Hämtning

    private func update() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            guard !Task.isCancelled else { return }
            result = KommunResult(answer: .empty, areas: [])
            updating = false
            return
        }
        updating = true
        // Väntar tills användaren slutat skriva. Ett nytt tangenttryck avbryter den här uppgiften.
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        guard let index else {
            result = KommunResult(answer: .unavailable, areas: [])
            updating = false
            return
        }
        let model = model
        let outcome = try? await latest.run { () -> KommunResult in
            let sources = await model.sourceList()
            let answer = KommunChecker.check(text, index: index, sources: sources)
            guard case .covered(let row, _) = answer else { return KommunResult(answer: answer, areas: []) }
            // Misslyckas anropet erbjuds adresssökning i stället för områdesval.
            let areas = (try? await model.api.areas(place: shortKommunName(row.name)).addresses) ?? []
            return KommunResult(answer: answer, areas: areas)
        }
        // Nil: ett nyare anrop har startat. Avbruten: texten ändrades, och en ny uppgift tar över.
        guard let outcome, !Task.isCancelled else { return }
        result = outcome
        updating = false
    }

    // MARK: Svar

    @ViewBuilder
    private var answerView: some View {
        switch result.answer {
        case .empty:
            Text("Till exempel Örebro eller Krylbo.")
                .font(.ui(16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(Color.Theme.text2)
                .padding(.horizontal, 4)
        case .covered(let row, let viaPlace):
            coveredCard(row: row, viaPlace: viaPlace)
        case .notYet(let row):
            notYetCard(row)
        case .multiple(let place, let rows):
            multipleCard(place: place, rows: rows)
        case .suggestions(let names):
            suggestionsCard(names)
        case .unknown:
            infoCard(icon: "magnifyingglass.circle", title: "Vi hittar ingen sådan plats",
                     message: "Kontrollera stavningen, eller skriv kommunens namn.")
        case .unavailable:
            unavailableCard
        }
    }

    private func coveredCard(row: KommunRow, viaPlace: String?) -> some View {
        let hasAreas = !result.areas.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(.title3))
                    .foregroundStyle(Color.Theme.brandText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viaPlace.map { "Ja, \(capitalizedFirst($0)) ligger i \(row.name)" } ?? "Ja, \(row.name) finns")
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.brandText)
                    if hasAreas {
                        Text("Här väljer du tömningsområde i stället för adress, eftersom källan inte publicerar alla adresser.")
                            .font(.ui(16, weight: .semibold, relativeTo: .callout))
                            .foregroundStyle(Color.Theme.text)
                    }
                }
            }
            if hasAreas {
                NavigationLink(value: AddRoute.areas(title: row.name, place: shortKommunName(row.name), hits: result.areas)) {
                    PrimaryButtonLabel(title: "Välj område i \(shortKommunName(row.name))")
                }
            } else {
                NavigationLink(value: AddRoute.search(source: row.sourceId)) {
                    PrimaryButtonLabel(title: "Sök din adress")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.brandSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func notYetCard(_ row: KommunRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "circle.dashed")
                    .font(.system(.title3))
                    .foregroundStyle(Color.Theme.text)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inte än")
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.text)
                    Text("\(row.name) finns inte med ännu. Sopor lägger till fler kommuner efter hand.")
                        .font(.ui(16, weight: .semibold, relativeTo: .callout))
                        .foregroundStyle(Color.Theme.text)
                }
            }
            Button { webLink = tipLink } label: {
                Label("Tipsa om din kommun", systemImage: "arrow.up.right.square")
                    .font(.ui(16, weight: .heavy, relativeTo: .callout))
                    .foregroundStyle(Color.Theme.brandText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func multipleCard(place: String, rows: [KommunRow]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(capitalizedFirst(place)) finns i flera kommuner")
                .font(.ui(20, weight: .heavy, relativeTo: .headline))
                .foregroundStyle(Color.Theme.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows, id: \.code) { row in
                AdaptiveStack(spacing: 12) {
                    Image(systemName: row.sourceId == nil ? "circle.dashed" : "checkmark.circle")
                        .foregroundStyle(row.sourceId == nil ? Color.Theme.text2 : Color.Theme.brandText)
                        .accessibilityHidden(true)
                    Text(row.name)
                        .font(.ui(17, weight: .bold, relativeTo: .body))
                        .foregroundStyle(Color.Theme.text)
                    Spacer(minLength: 8)
                    if let source = row.sourceId {
                        NavigationLink(value: AddRoute.search(source: source)) {
                            Text("Sök adress")
                                .font(.ui(16, weight: .heavy, relativeTo: .callout))
                                .foregroundStyle(Color.Theme.primary)
                        }
                        .accessibilityLabel("Sök adress i \(row.name)")
                    } else {
                        Text("Inte än")
                            .font(.ui(16, weight: .bold, relativeTo: .callout))
                            .foregroundStyle(Color.Theme.text2)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
    }

    private func suggestionsCard(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Menar du?")
                .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                .foregroundStyle(Color.Theme.text2)
            ForEach(names, id: \.self) { name in
                Button { query = name } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color.Theme.brandText)
                            .accessibilityHidden(true)
                        Text(name)
                            .font(.ui(18, weight: .heavy, relativeTo: .body))
                            .foregroundStyle(Color.Theme.text)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
    }

    private func infoCard(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(.title3))
                .foregroundStyle(Color.Theme.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.ui(20, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                Text(message)
                    .font(.ui(16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(Color.Theme.text)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "icloud.slash")
                    .font(.system(.title3))
                    .foregroundStyle(Color.Theme.warn)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kunde inte kontrollera just nu")
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.warn)
                    Text("Försök igen om en stund. Det betyder inte att kommunen saknas.")
                        .font(.ui(16, weight: .semibold, relativeTo: .callout))
                        .foregroundStyle(Color.Theme.text)
                }
            }
            Button { attempt += 1 } label: { PrimaryButtonLabel(title: "Försök igen") }
                .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.warnBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
