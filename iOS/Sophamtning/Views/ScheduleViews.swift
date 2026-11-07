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
struct BinCard: View {
    let bin: AddressDetail.Bin

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FractionIconView(id: bin.id, info: bin.info)
            VStack(alignment: .leading, spacing: 2) {
                Text(bin.info.name)
                    .font(.ui(17, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(0.6)
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
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bin.accessibilityLabel)
    }
}

/// Hela det kommande schemat, i samma format som raderna under "Kommande".
struct FullScheduleView: View {
    let model: AppModel
    let key: AddressKey

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            if let address = model.addresses.first(where: { $0.key == key }) {
                let detail = AddressDetail.make(
                    address: address,
                    schedule: model.schedule(for: key),
                    settings: model.settings,
                    sourceName: nil,
                    now: model.currentDate
                )
                ScrollView {
                    ScheduleList(rows: detail.rows)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Hela schemat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
