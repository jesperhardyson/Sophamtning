import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "Ansvarar för hämtningen": källans namn, länkarna och när schemat hämtades, längst ned i adressvyn och i hela
/// schemat. Webbsidor öppnas i appens webbvy, telefon och e-post av iOS.
struct SourceCard: View {
    let name: String
    let links: [SourceLink]
    /// "Hämtat i dag 18:50", eller `nil` när schemat inte har hämtats.
    let fetched: String?
    @Binding var webLink: WebLink?

    /// Kortet för en adress, likadant i adressvyn och i hela schemat. Tiden för hämtningen visas inte medan schemat
    /// hämtas första gången.
    init(source: String, sources: [Source]?, detail: AddressDetail, webLink: Binding<WebLink?>) {
        name = sourceName(source, in: sources)
        links = SourceLink.links(for: sources?.first { candidate in candidate.id == source }, kommunInfo: detail.webLink)
        fetched = detail.mode == .loading ? nil : detail.fetchedText
        _webLink = webLink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ansvarar för hämtningen")
                    .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text2)
                    .accessibilityAddTraits(.isHeader)
                Text(name)
                    .font(.ui(20, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(Color.Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            ForEach(links) { link in
                ResultDivider()
                SourceLinkButton(link: link, webLink: $webLink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            if let fetched {
                ResultDivider()
                Text(fetched)
                    .font(.ui(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Color.Theme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.Theme.border))
    }
}

/// En länk till källan, med ikon. Webbsidor öppnas i appens webbvy, och telefon och e-post av iOS.
struct SourceLinkButton: View {
    let link: SourceLink
    @Binding var webLink: WebLink?
    /// Källans namn för VoiceOver, där flera källor står i samma lista: "Webbplats, Avesta Vatten och Avfall".
    var source: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let web = link.webLink { webLink = web } else { openURL(link.url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: link.icon)
                    .font(.system(.body, weight: .semibold))
                    .frame(minWidth: 24)
                    .accessibilityHidden(true)
                Text(link.title)
                    .font(.ui(17, weight: .heavy, relativeTo: .body))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.Theme.primary)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(source.map { "\(link.accessibilityLabel), \($0)" } ?? link.accessibilityLabel)
        .accessibilityHint(link.webLink == nil ? "" : "Öppnas i appen")
        .accessibilityAddTraits(.isLink)
    }
}
