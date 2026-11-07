import SophamtningDesign
import SophamtningKit
import SwiftUI

/// En dag i schemat: liten datumbricka, kärlen som chips och dagar kvar till höger. Avvikelse och varning står under.
/// Används under "Kommande" och i hela schemat.
struct ScheduleRowView: View {
    let row: AddressDetail.Row

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var badgeWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                // Under varandra, så att chipsen och dagarna får hela bredden.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        badge
                        days
                    }
                    chips
                }
            } else {
                HStack(spacing: 14) {
                    badge
                    chips
                    days
                }
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var badge: some View {
        VStack(spacing: 0) {
            Text(row.dayNumber)
                .font(.brand(22, relativeTo: .title3))
                .foregroundStyle(Color.Theme.text)
            Text(row.month)
                .font(.ui(11, weight: .heavy, relativeTo: .caption2))
                .foregroundStyle(Color.Theme.text2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 6)
        .frame(width: badgeWidth)
        .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chips: some View {
        FlowLayout(spacing: 6) {
            ForEach(row.fractions) { fraction in
                FractionChip(id: fraction.id, info: fraction.info, short: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var days: some View {
        Text(row.shortDaysText)
            .font(.ui(15, weight: .heavy, relativeTo: .callout))
            .foregroundStyle(Color.Theme.brandText)
            .multilineTextAlignment(.trailing)
            .fixedSize()
    }
}

/// Raderna i en vit ruta. Avgränsaren följer sin rad, så att den aldrig syns i en tom ruta.
struct ScheduleList: View {
    let rows: [AddressDetail.Row]
    /// Om raderna ska synas. `nil` låter varje rad komma in när den visas första gången.
    var shown: Bool?

    var body: some View {
        ResultList {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let item = VStack(spacing: 0) {
                    if index > 0 { ResultDivider() }
                    ScheduleRowView(row: row)
                }
                if let shown {
                    item.rowEntrance(shown: shown, index: index)
                } else {
                    item.rowEntranceOnAppear(index: index)
                }
            }
        }
    }
}

/// Kort för ett kärl: ikon, namn, dagar kvar och datum. Läses som ett element av VoiceOver.
/// Kortet är minst 3/7 av bredden och blir bredare, högst 2/3, när ett ord i namnet inte ryms i full storlek.
struct BinCard: View {
    let bin: AddressDetail.Bin

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Bredden det längsta ordet i namnet behöver i full storlek.
    @State private var wordWidth: CGFloat = 0

    private var words: [String] {
        bin.info.name.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Lika många rader som namnet har ord, högst tre.
    private var nameLines: Int {
        min(max(words.count, 1), 3)
    }

    private var nameFont: Font { .ui(17, weight: .heavy, relativeTo: .headline) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FractionIconView(id: bin.id, info: bin.info)
            VStack(alignment: .leading, spacing: 2) {
                // Högst en rad per ord, så att ett ord aldrig bryts mitt i. Ryms ordet inte ens i det bredaste kortet
                // krymper det, i stället för att brytas.
                Text(bin.info.name)
                    .font(nameFont)
                    .foregroundStyle(Color.Theme.text)
                    .lineLimit(nameLines)
                    .minimumScaleFactor(0.4)
                Text(bin.daysText)
                    .font(.ui(15, weight: .heavy, relativeTo: .callout))
                    .foregroundStyle(Color.Theme.brandText)
                    .rollingNumbers(value: bin.daysText, reduceMotion: reduceMotion)
                Text(bin.dateText)
                    .font(.ui(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(BinCardMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topLeading) { wordMeasure }
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bin.accessibilityLabel)
        .containerRelativeFrame(.horizontal) { length, _ in
            BinCardMetrics.width(
                container: length,
                content: wordWidth + BinCardMetrics.horizontalPadding * 2,
                accessibilitySize: typeSize.isAccessibilitySize
            )
        }
    }

    /// Orden i namnet i full storlek, osynliga och utan plats i layouten. Det bredaste bestämmer kortets bredd. Bara
    /// bredden mäts, typsnittet följer alltid textstorleken.
    private var wordMeasure: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word).font(nameFont).lineLimit(1).fixedSize()
            }
        }
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
        .onGeometryChange(for: CGFloat.self, of: { proxy in proxy.size.width }, action: { width in wordWidth = width })
    }
}

/// Hela det kommande schemat, i samma format som raderna under "Kommande". Saknas schemat visas samma meddelanden som i
/// adressvyn, och försvinner adressen medan vyn är öppen står det varför. Vyn är aldrig tom.
struct FullScheduleView: View {
    let model: AppModel
    let key: AddressKey
    let onSearchAgain: () -> Void

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let address = model.addresses.first(where: { $0.key == key }) {
                        content(for: address)
                    } else {
                        missingAddress
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable { await model.refreshAll(manual: true) }
        }
        .navigationTitle("Hela schemat")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(for address: SavedAddress) -> some View {
        let detail = AddressDetail.make(
            address: address,
            schedule: model.schedule(for: key),
            settings: model.settings,
            sourceName: nil,
            now: model.currentDate
        )
        AddressNoticeView(model: model, notice: detail.notice, onSearchAgain: { onSearchAgain() })
        switch detail.mode {
        case .loading:
            ScheduleLoadingCard()
        case .unavailable:
            // Felet står i meddelandet ovan.
            EmptyView()
        case .noUpcoming:
            NoUpcomingCard()
        case .schedule:
            ScheduleList(rows: detail.rows)
        }
    }

    /// Adressen togs bort, eller adresserna går inte att läsa just nu. Ett läsfel får aldrig se ut som en borttagen adress.
    @ViewBuilder
    private var missingAddress: some View {
        if model.storageProblem == .addressesUnreadable || model.storageProblem == .addressesUnavailable {
            MessageCard(style: .warning, icon: "externaldrive.badge.xmark", title: "Dina adresser kan inte läsas just nu", message: "Inget har raderats. Gå tillbaka till hemskärmen och försök igen.")
        } else {
            MessageCard(style: .neutral, icon: "mappin.slash", title: "Adressen är borttagen", message: "Den finns inte längre bland dina sparade adresser.")
        }
    }
}

/// Meddelandet högst upp i adressvyn och i hela schemat när hämtningen eller sparandet har misslyckats.
struct AddressNoticeView: View {
    let model: AppModel
    let notice: AddressDetail.Notice?
    /// Öppnar sökningen igen, för en adress som källan inte längre känner igen.
    let onSearchAgain: () -> Void

    var body: some View {
        switch notice {
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
                    .buttonStyle(.pressable)
            }
            .padding(.bottom, 20)
        case .notFound:
            VStack(spacing: 12) {
                MessageCard(style: .warning, icon: "location.slash", title: "Adressen hittas inte längre", message: "Källan känner inte igen adressen. Sök upp den på nytt för att få schemat.")
                Button { onSearchAgain() } label: { PrimaryButtonLabel(title: "Sök igen") }
                    .buttonStyle(.pressable)
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
                    .buttonStyle(.pressable)
            }
            .padding(.bottom, 20)
        case nil:
            EmptyView()
        }
    }
}

/// Schemat hämtas för första gången.
struct ScheduleLoadingCard: View {
    var body: some View {
        BinLoaderView(textColor: Color.Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Schemat finns men har inga hämtningar från och med i dag.
struct NoUpcomingCard: View {
    var body: some View {
        MessageCard(style: .neutral, icon: "calendar.badge.exclamationmark", title: "Inga kommande hämtningar", message: "Schemat kan ta slut tills kommunen har publicerat nästa period.")
    }
}
