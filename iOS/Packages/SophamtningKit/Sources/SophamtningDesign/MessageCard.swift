import SwiftUI

/// Meddelanderuta med ikon, rubrik och förklaring.
public struct MessageCard: View {
    public enum Style: Sendable {
        case neutral
        case warning
    }

    let style: Style
    let icon: String
    let title: String
    let message: String
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 18

    /// `icon` är ett SF Symbol-namn.
    public init(style: Style, icon: String, title: String, message: String) {
        self.style = style
        self.icon = icon
        self.title = title
        self.message = message
    }

    private var background: Color { style == .warning ? Color.Theme.warnBg : Color.Theme.surface2 }
    private var tint: Color { style == .warning ? Color.Theme.warn : Color.Theme.text }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(tint)
                Text(message)
                    .font(.ui(14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(style == .warning ? Color.Theme.text : Color.Theme.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Meddelanden") {
    VStack(spacing: 12) {
        MessageCard(style: .neutral, icon: "info.circle", title: "Rubrik", message: "Förklaring i en eller två rader.")
        MessageCard(style: .warning, icon: "exclamationmark.triangle", title: "Kunde inte hämta", message: "Försök igen om en stund.")
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
