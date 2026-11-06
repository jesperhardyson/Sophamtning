import CoreText
import Foundation
import SwiftUI

/// Registrerar paketets typsnitt (Nunito och Fredoka). Appen och widgeten anropar `register()` en gång vid start.
/// Utan registrering faller vyerna tillbaka på systemets typsnitt.
public enum Fonts {
    /// Paketets resurser (för tester).
    static var bundle: Bundle { .module }

    private static let files = ["Nunito", "Fredoka"]

    private static let registered: Bool = {
        files.reduce(true) { ok, name in
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { return false }
            var error: Unmanaged<CFError>?
            // Redan registrerat räknas som lyckat.
            let done = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            let alreadyThere = (error?.takeRetainedValue()).map { CFErrorGetCode($0) == CTFontManagerError.alreadyRegistered.rawValue } ?? false
            return ok && (done || alreadyThere)
        }
    }()

    /// Registrerar typsnitten för processen. Går att anropa flera gånger. Ger `false` om något inte gick att registrera.
    @discardableResult
    public static func register() -> Bool { registered }
}

extension Font {
    /// Gränssnittstext i Nunito (600 till 800). Skalar med Dynamic Type relativt `textStyle`.
    public static func ui(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("Nunito", size: size, relativeTo: textStyle).weight(weight)
    }

    /// Varumärke och rubriker i Fredoka (600).
    public static func brand(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        .custom("Fredoka", size: size, relativeTo: textStyle).weight(weight)
    }
}
