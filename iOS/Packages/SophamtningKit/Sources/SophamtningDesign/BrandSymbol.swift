import SwiftUI

/// Appens märke: en kalender i en rundad pil. Ritas i temats primärfärg, som är ljusare i mörkt läge.
public struct BrandSymbol: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 150

    public init(size: CGFloat = 150) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    public var body: some View {
        Image("brand-symbol", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.Theme.primary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Märke") {
    HStack {
        BrandSymbol()
        BrandSymbol().preferredColorScheme(.dark)
    }
    .padding()
    .background(Color.Theme.bg)
}
