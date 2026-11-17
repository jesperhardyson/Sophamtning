import SwiftUI

/// Meddelanderuta med ikon, rubrik och förklaring. Valfritt en länk under texten och ett kryss som stänger rutan.
/// Krysset står i rutan, så att texten aldrig hamnar under det.
public struct MessageCard: View {
    public enum Style: Sendable {
        case neutral
        case warning
    }

    /// En länk under texten, till exempel "Läs mer hos Avesta Vatten och Avfall". `open` bestämmer var den öppnas,
    /// i appen i appens egen webbvy.
    public struct Link {
        public let title: String
        public let open: () -> Void

        public init(title: String, open: @escaping () -> Void) {
            self.title = title
            self.open = open
        }
    }

    let style: Style
    let icon: String
    let title: String
    let message: String
    let link: Link?
    let onClose: (() -> Void)?
    let closeLabel: String
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 18

    /// `icon` är ett SF Symbol-namn. Med `onClose` får rutan ett kryss, som VoiceOver läser som `closeLabel`.
    public init(style: Style, icon: String, title: String, message: String, link: Link? = nil, closeLabel: String = "Stäng", onClose: (() -> Void)? = nil) {
        self.style = style
        self.icon = icon
        self.title = title
        self.message = message
        self.link = link
        self.closeLabel = closeLabel
        self.onClose = onClose
    }

    private var background: Color { style == .warning ? Color.Theme.warnBg : Color.Theme.surface2 }
    private var tint: Color { style == .warning ? Color.Theme.warn : Color.Theme.text }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                            .foregroundStyle(tint)
                        Text(message)
                            .font(.ui(14, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(style == .warning ? Color.Theme.text : Color.Theme.text2)
                    }
                    .accessibilityElement(children: .combine)
                    if let link {
                        Button(action: link.open) {
                            Text(link.title)
                                .font(.ui(14, weight: .heavy, relativeTo: .footnote))
                                .foregroundStyle(Color.Theme.primary)
                                .underline()
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isLink)
                        .padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Color.Theme.text2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(closeLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: link == nil && onClose == nil ? .combine : .contain)
    }
}

#Preview("Meddelanden") {
    VStack(spacing: 12) {
        MessageCard(style: .neutral, icon: "info.circle", title: "Rubrik", message: "Förklaring i en eller två rader.")
        MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Kunde inte hämta", message: "Försök igen om en stund.")
        MessageCard(style: .neutral, icon: "megaphone", title: "Hämtrutterna läggs om", message: "Schemat här kan bli fel.",
                    link: .init(title: "Läs mer hos Avesta Vatten och Avfall", open: {}),
                    closeLabel: "Stäng meddelandet", onClose: {})
    }
    .padding()
    .background(Color.Theme.bg)
}

#Preview("Meddelanden mörkt") {
    MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Kunde inte hämta", message: "Försök igen om en stund.")
        .padding()
        .background(Color.Theme.bg)
        .preferredColorScheme(.dark)
}
