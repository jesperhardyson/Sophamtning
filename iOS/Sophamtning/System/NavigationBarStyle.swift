import CoreText
import SophamtningDesign
import SwiftUI
import UIKit

/// Systemets navigeringsfält med rubriken i appens typsnitt (Fredoka), både stor och liten. Bara texten ändras, så
/// att iOS 26 ritar fältet, glaset och övergången vid scroll som vanligt.
@MainActor
enum NavigationBarStyle {
    /// Körs en gång vid start, efter att typsnitten har registrerats.
    static func apply() {
        let bar = UINavigationBar.appearance()
        let color = UIColor(Color.Theme.text)
        if let large = font(size: 34, style: .largeTitle) {
            bar.largeTitleTextAttributes = [.font: large, .foregroundColor: color]
        }
        if let small = font(size: 18, style: .headline) {
            bar.titleTextAttributes = [.font: small, .foregroundColor: color]
        }
    }

    /// Fredoka i vikten 600, som `Font.brand`, skalad med Dynamic Type efter `style`.
    private static func font(size: CGFloat, style: UIFont.TextStyle) -> UIFont? {
        // Typsnittet har en viktaxel. `wght` ger vikten direkt, så att rubriken blir lika fet som i resten av appen.
        let weightAxis = 0x7767_6874
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Fredoka",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [weightAxis: 600],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        guard font.familyName == "Fredoka" else { return nil }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
}
