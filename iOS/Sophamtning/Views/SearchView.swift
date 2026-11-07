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

    /// Sökresultatet och, vid noll träffar och en angiven ort, områdena som `/omraden` gav.
    private struct Outcome: Sendable {
        var state: SearchState
        var areas: [SearchHit]
        /// Sant när `/omraden` anropades för en angiven ort men misslyckades.
        var areasFailed = false
    }

    @State private var query = ""
    @State private var attempt = 0
    @State private var outcome = Outcome(state: .idle, areas: [])
    @State private var sources: [Source]?
    @State private var chosenArea: HitSelection?
    @State private var saveFailed = false
    /// Sant medan ett nytt svar hämtas. Gamla träffar tonas ned och går inte att trycka på.
    @State private var updating = false
    @State private var latest = LatestOnly()
    /// Ökar när en träff har sparats, för den lätta vibrationen.
    @State private var saves = 0

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
        .sensoryFeedback(.impact(weight: .light), trigger: saves)
        .sheet(item: $chosenArea) { selection in
            let hit = selection.hit
            AreaConfirmSheet(saveFailed: saveFailed, hit: hit, onSave: {
                saveFailed = !save(hit, in: model, onSaved: onSaved)
            }, onOther: { chosenArea = nil })
        }
    }

    // MARK: Sökning

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Minst tre tecken innan /sok anropas.
        guard text.count >= 3 else {
            guard !Task.isCancelled else { return }
            outcome = Outcome(state: .idle, areas: [])
            updating = false
            return
        }
        updating = true
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        // Gamla träffar ligger kvar medan ett nytt svar hämtas. Bara en tom eller felande ruta byts mot "söker".
        switch outcome.state {
        case .idle, .failed, .sourcesFailed, .noHits: outcome = Outcome(state: .searching, areas: [])
        case .searching, .results: break
        }
        let api = model.api
        let source = presetSource
        let result: Outcome?
        do {
            result = try await latest.run { () -> Outcome in
                let response = try await api.search(query: text, source: source)
                let state = SearchState.from(response, query: text)
                guard case .noHits(let place?) = state else { return Outcome(state: state, areas: []) }
                // Misslyckas områdesanropet visas ändå "hittades inte", utan områdesval.
                do {
                    return Outcome(state: state, areas: try await api.areas(place: place).addresses)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    return Outcome(state: state, areas: [], areasFailed: true)
                }
            }
        } catch let error as APIError {
            guard !Task.isCancelled else { return }
            result = Outcome(state: .failed(error), areas: [])
        } catch {
            return
        }
        guard let result, !Task.isCancelled else { return }
        outcome = result
        updating = false
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
        case .noHits(let place):
            noHits(place: place)
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
            Text(hits.count == 1 ? "1 träff" : "\(hits.count) träffar")
                .font(.ui(17, weight: .heavy, relativeTo: .body))
                .foregroundStyle(Color.Theme.text2)
                .padding(.bottom, 12)
            ResultList {
                ForEach(Array(hits.enumerated()), id: \.offset) { offset, hit in
                    if offset > 0 { ResultDivider() }
                    Button { choose(hit) } label: { row(hit) }
                        .buttonStyle(.pressable)
                        .rowEntranceOnAppear(index: offset)
                }
            }
            // Nya träffar börjar om från första raden. Samma träffar igen gör ingenting.
            .id(hits)
        }
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
                Text(hit.locality.isEmpty ? hit.kommun : "\(hit.locality), \(hit.kommun)")
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
            saveFailed = !save(hit, in: model, onSaved: onSaved)
            if !saveFailed { saves += 1 }
        }
    }

    private func noHits(place: String?) -> some View {
        let areas = outcome.areas
        let kommun = areas.first.map { shortKommunName($0.kommun) }
        let publisher = areas.first.map { sourceName($0.source, in: sources) }
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
            if !areas.isEmpty, let kommun, let publisher {
                Text("\(publisher) publicerar inte alla adresser. Där väljer du i stället ditt tömningsområde.")
                    .font(.ui(18, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.Theme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                NavigationLink(value: AddRoute.areas(title: areas[0].kommun, place: place, hits: areas)) {
                    PrimaryButtonLabel(title: "Välj område i \(kommun)")
                }
                .buttonStyle(.pressable)
                .padding(.top, 24)
            } else if place != nil, outcome.areasFailed {
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
