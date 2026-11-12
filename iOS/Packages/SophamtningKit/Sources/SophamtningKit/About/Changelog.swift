import Foundation

/// Nyheterna i appen, tolkade från `CHANGELOG.md` som Release Please skriver. Bara texten visas: PR-nummer, commit-länkar
/// och jämförelselänkar tas bort, eftersom de är till för utvecklarna.
public enum Changelog {
    public struct Version: Equatable, Sendable, Identifiable {
        public let version: String
        /// "1.1.0 · 10 november 2026", eller bara versionen när datumet saknas.
        public let title: String
        public let sections: [Section]
        public var id: String { version }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public let title: String
        public let items: [String]
        public var id: String { title }
    }

    /// Delarna som visas, i Release Please-konfigurationens namn. Övriga, som brytande ändringar, är för utvecklare.
    static let shownSections: Set<String> = ["Nytt", "Rättat", "Snabbare"]

    /// Versioner som inte visas. `CHANGELOG.md` skrivs av Release Please och ändras aldrig för hand, så det som inte är för
    /// användarna döljs här. 1.0.0 innehåller bara "Milstolpe 4, redo för App Store".
    public static let hiddenVersions: Set<String> = ["1.0.0"]

    /// Versionerna i filens ordning, som är nyast först. Versioner utan någon visad rad, och de i `hiding`, hoppas över.
    public static func parse(_ markdown: String, hiding: Set<String> = hiddenVersions) -> [Version] {
        var versions: [Version] = []
        var current: (version: String, title: String)?
        var sections: [Section] = []
        var section: (title: String, items: [String])?

        func closeSection() {
            if let open = section, shownSections.contains(open.title), !open.items.isEmpty {
                sections.append(Section(title: open.title, items: open.items))
            }
            section = nil
        }
        func closeVersion() {
            closeSection()
            if let open = current, !sections.isEmpty, !hiding.contains(open.version) {
                versions.append(Version(version: open.version, title: open.title, sections: sections))
            }
            current = nil
            sections = []
        }

        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                closeVersion()
                current = heading(String(line.dropFirst(3)))
            } else if line.hasPrefix("### ") {
                closeSection()
                if current != nil { section = (String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces), []) }
            } else if line.hasPrefix("* ") || line.hasPrefix("- "), section != nil {
                let text = item(String(line.dropFirst(2)))
                if !text.isEmpty { section?.items.append(text) }
            }
        }
        closeVersion()
        return versions
    }

    /// "[1.1.0](url) (2026-11-10)" eller "1.0.0 (2026-11-08)" blir versionen och rubriken.
    private static func heading(_ text: String) -> (version: String, title: String) {
        let version = (text.firstMatch(of: /\[([^\]]+)\]/)?.output.1).map(String.init)
            ?? String(text.prefix { $0 != " " })
        guard let match = text.firstMatch(of: /\((\d{4}-\d{2}-\d{2})\)/), let day = DayDate(String(match.output.1)) else {
            return (version, version)
        }
        return (version, "\(version) · \(SwedishFormat.dayMonthYear(day))")
    }

    /// "**scope:** Text ([#53](url)) ([b7e13ad](url))" blir "Text".
    private static func item(_ text: String) -> String {
        var result = text.replacing(/\s*\(\[[^\]]*\]\([^)]*\)\)/, with: "")
        result = result.replacing(/^\*\*[^*]+:\*\*\s*/, with: "")
        return result.trimmingCharacters(in: .whitespaces)
    }
}
