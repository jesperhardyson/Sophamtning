import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Lägg till adress". `presetSource` begränsar sökningen till en källa (`kalla`).
struct SearchView: View {
    let model: AppModel
    let presetSource: String?
    let onSaved: () -> Void

    private struct Trigger: Hashable {
        var query: String
        var attempt: Int
    }

    @State private var query = ""
    @State private var attempt = 0
    /// Sökresultatet och områdena som `/omraden` gav för orterna i söktexten.
    @State private var outcome = SearchOutcome(state: .idle, areas: nil)
    @State private var sources: [Source]?
    @State private var chosenArea: HitSelection?
    @State private var saveFailed = false
    /// Sant medan ett nytt svar hämtas. Gamla träffar tonas ned och går inte att trycka på.
    @State private var updating = false
    @State private var latest = LatestOnly()
    @State private var latestAreas = LatestOnly()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FlowSearchField(placeholder: "Gata och husnummer", text: $query)
                    .padding(.top, 8)
                content
                    .opacity(updating ? 0.4 : 1)
                    .allowsHitTesting(!updating)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.Theme.bg.ignoresSafeArea())
        .navigationTitle("Lägg till adress")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Trigger(query: query, attempt: attempt)) { await search() }
        .onChange(of: query) { saveFailed = false }
        .sheet(item: $chosenArea) { selection in
            let hit = selection.hit
            AreaConfirmSheet(saveFailed: saveFailed, hit: hit, onSave: {
                let saved = save(hit, in: model, onSaved: onSaved)
                saveFailed = !saved
            }, onOther: { chosenArea = nil })
        }
    }

    // MARK: Sökning

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Minst tre tecken innan /sok anropas.
        guard text.count >= 3 else {
            guard !Task.isCancelled else { return }
            outcome = SearchOutcome(state: .idle, areas: nil)
            updating = false
            return
        }
        updating = true
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        // Gamla träffar ligger kvar medan ett nytt svar hämtas. Bara en tom eller felande ruta byts mot "söker".
        switch outcome.state {
        case .idle, .failed, .sourcesFailed, .noHits: outcome = SearchOutcome(state: .searching, areas: nil)
        case .searching, .results: break
        }
        // /omraden frågas samtidigt för orterna i söktexten. Träffarna visas utan att vänta på områdena, och ett
        // svar som kommer efter att söktexten ändrats visas inte.
        await AddressSearch.run(query: text, source: presetSource, api: model.api, searches: latest,
                                areaLookups: latestAreas) { result in
            outcome = result
            updating = false
        }
        guard !Task.isCancelled else { return }
        // Källnamnen behövs bara för texterna, så träffarna visas utan att vänta på `/kallor`.
        let names = await model.sourceList()
        if !Task.isCancelled { sources = names }
    }

    // MARK: Innehåll

    @ViewBuilder
    private var content: some View {
        switch outcome.state {
        case .idle:
            guidance
        case .searching:
            HStack(spacing: 12) {
                ProgressView()
                Text("Söker …")
                    .font(.ui(17, weight: .bold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        case .results(let hits, let failed):
            results(hits, failed: failed)
        case .sourcesFailed(let failed):
            VStack(alignment: .leading, spacing: 12) {
                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Kunde inte söka hos alla källor",
                            message: "Försök igen. Det betyder inte att adressen saknas.")
                Button { attempt += 1 } label: { PrimaryButtonLabel(title: "Försök igen") }
                    .buttonStyle(.pressable)
                    .accessibilityHint(failedNames(failed))
            }
        case .noHits:
            noHits()
        case .failed(let error):
            failure(error)
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Skriv gata och husnummer, gärna med ort.")
                .font(.ui(16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(Color.Theme.text2)
            kommunLink
        }
        .padding(.horizontal, 4)
    }

    private var kommunLink: some View {
        NavigationLink(value: AddRoute.kommun) {
            Label("Finns min kommuns hämtningsschema?", systemImage: "mappin.and.ellipse")
                .font(.ui(18, weight: .heavy, relativeTo: .body))
                .foregroundStyle(Color.Theme.primary)
                .multilineTextAlignment(.leading)
        }
    }

    private func failedNames(_ failed: [String]) -> String {
        failed.map { sourceName($0, in: sources) }.joined(separator: ", ")
    }

    private func results(_ hits: [SearchHit], failed: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !failed.isEmpty {
                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Alla källor svarade inte",
                            message: "\(failedNames(failed)) svarade inte just nu. Saknas din adress kan du försöka igen om en stund.")
                    .padding(.bottom, 20)
            }
            if saveFailed {
                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Något gick fel", message: saveFailedMessage)
                    .padding(.bottom, 20)
            }
            if case .found(let place, let areas)? = outcome.areas {
                // Knappen kommer ofta efter träffarna, och glider då in i stället för att skjuta ned listan i ett ryck.
                areaButton(place: place, areas: areas)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            let rows = visibleHits(hits)
            if !rows.isEmpty {
                Text(rows.count == 1 ? "1 träff" : "\(rows.count) träffar")
                    .font(.ui(17, weight: .heavy, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
                    .contentTransition(.numericText())
                    .padding(.bottom, 12)
                ResultList {
                    // Varje rad behåller sin plats i svaret som identitet, så att en bortfiltrerad områdesrad inte
                    // startar om de andra radernas inträde.
                    ForEach(Array(rows.enumerated()), id: \.element.offset) { position, row in
                        // Avgränsaren följer sin rad, så att den inte syns i en tom ruta.
                        VStack(spacing: 0) {
                            if position > 0 { ResultDivider() }
                            Button { choose(row.element) } label: { self.row(row.element) }
                                .buttonStyle(.pressable)
                        }
                        .rowEntranceOnAppear(index: position)
                    }
                }
                // Nya träffar börjar om från första raden. Samma träffar igen, eller samma med en områdesrad mindre,
                // gör ingenting.
                .id(hits)
            }
        }
        .animation(Motion.transition(reduceMotion: reduceMotion), value: outcome.areas)
    }

    /// Träffarna, med sin plats i svaret, utan områdesrader för en kommun vars områden redan nås med knappen.
    private func visibleHits(_ hits: [SearchHit]) -> [EnumeratedSequence<[SearchHit]>.Element] {
        let all = Array(hits.enumerated())
        guard case .found(_, let areas)? = outcome.areas else { return all }
        let kommuner = Set(areas.map(\.kommun))
        return all.filter { !($0.element.isArea && kommuner.contains($0.element.kommun)) }
    }

    /// "Välj område i X": samma knapp och flöde vid träffar som vid noll träffar.
    private func areaButton(place: String, areas: [SearchHit]) -> some View {
        NavigationLink(value: AddRoute.areas(title: areas[0].kommun, place: place, hits: areas)) {
            PrimaryButtonLabel(title: "Välj område i \(kommunDisplayName(areas[0].kommun))")
        }
        .buttonStyle(.pressable)
    }

    private func row(_ hit: SearchHit) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(.title3))
                .foregroundStyle(Color.Theme.brandText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.street)
                    .font(.ui(20, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                // Samma regel som kortens undertitel: kommunen upprepar inte orten.
                Text(localityAndKommun(locality: hit.locality, kommun: hit.kommun))
                    .font(.ui(16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(Color.Theme.text2)
                if let detail = hit.detail {
                    Text(detail)
                        .font(.ui(16, weight: .heavy, relativeTo: .callout))
                        .foregroundStyle(Color.Theme.earth)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Color.Theme.text2).accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func choose(_ hit: SearchHit) {
        if hit.isArea {
            saveFailed = false
            chosenArea = HitSelection(hit: hit)
        } else {
            // Vibrationen spelas av hemskärmen när sparandet lyckats.
            saveFailed = !save(hit, in: model, onSaved: onSaved)
        }
    }

    private func noHits() -> some View {
        var found: (place: String, areas: [SearchHit])?
        if case .found(let place, let areas)? = outcome.areas, !areas.isEmpty { found = (place, areas) }
        return VStack(spacing: 0) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 44))
                .foregroundStyle(Color.Theme.text2)
                .accessibilityHidden(true)
                .padding(.top, 12)
            Text("Adressen hittades inte")
                .font(.ui(24, weight: .heavy, relativeTo: .title2))
                .foregroundStyle(Color.Theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)
            if let found {
                Text("\(sourceName(found.areas[0].source, in: sources)) publicerar inte alla adresser. Där väljer du i stället ditt tömningsområde.")
                    .font(.ui(18, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                areaButton(place: found.place, areas: found.areas)
                    .padding(.top, 24)
            } else if outcome.areas == .failed {
                MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Kunde inte hämta områden",
                            message: "Försök igen. Det betyder inte att kommunen saknar områdesval.")
                    .padding(.top, 10)
                Button { attempt += 1 } label: { PrimaryButtonLabel(title: "Försök igen") }
                    .buttonStyle(.pressable)
                    .padding(.top, 12)
            } else {
                Text("Kontrollera stavningen och skriv gata, husnummer och gärna ort. Alla adresser finns inte hos alla källor.")
                    .font(.ui(18, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            Text("Skriv gata och husnummer, gärna med ort.")
                .font(.ui(16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(Color.Theme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
            kommunLink
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
        }
    }

    private func failure(_ error: APIError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if error == .badRequest {
                // 400 är inget nätfel, och samma anrop upprepas inte.
                MessageCard(style: .neutral, icon: "questionmark.circle", title: "Sökningen gick inte att tolka",
                            message: "Kontrollera texten och försök med gata och husnummer.")
            } else {
                MessageCard(style: .warning, icon: "icloud.slash", title: "Kunde inte söka just nu",
                            message: "Källan svarar inte. Det betyder inte att adressen saknas.")
                Button { attempt += 1 } label: { PrimaryButtonLabel(title: "Försök igen") }
                    .buttonStyle(.pressable)
            }
        }
    }
}
