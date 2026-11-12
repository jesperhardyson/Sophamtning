import Foundation
import Testing
import SophamtningKit

private let sample = """
# Changelog

## [1.1.0](https://github.com/x/y/compare/v1.0.2...v1.1.0) (2026-11-10)


### Nytt

* Förslag om påminnelse efter första adressen ([#53](https://github.com/x/y/issues/53)) ([b7e13ad](https://github.com/x/y/commit/b7e13ad))
* **hushåll:** Hushåll med delade adresser ([#60](https://github.com/x/y/issues/60)) ([1dad2b0](https://github.com/x/y/commit/1dad2b0))


### Rättat

* Pilen står till höger ([#41](https://github.com/x/y/issues/41)) ([2e9d52f](https://github.com/x/y/commit/2e9d52f))

## 1.0.0 (2026-11-08)


### ⚠ BREAKING CHANGES

* inställningarna sparas på nytt sätt

### Nytt

* Milstolpe 4, redo för App Store ([#24](https://github.com/x/y/issues/24)) ([4b1ca42](https://github.com/x/y/commit/4b1ca42))
"""

@Test func versionerNyastFörst() {
    let versions = Changelog.parse(sample)
    #expect(versions.map(\.version) == ["1.1.0", "1.0.0"])
    #expect(versions[0].title == "1.1.0 · 10 november 2026")
    #expect(versions[1].title == "1.0.0 · 8 november 2026")
}

@Test func raderUtanLänkar() {
    let first = Changelog.parse(sample)[0]
    #expect(first.sections.map(\.title) == ["Nytt", "Rättat"])
    #expect(first.sections[0].items == ["Förslag om påminnelse efter första adressen", "Hushåll med delade adresser"])
    #expect(first.sections[1].items == ["Pilen står till höger"])
}

@Test func tekniskaDelarVisasInte() {
    // Delar som inte är Nytt, Rättat eller Snabbare visas inte, till exempel listan över brytande ändringar.
    let old = Changelog.parse(sample)[1]
    #expect(old.sections.map(\.title) == ["Nytt"])
    #expect(old.sections[0].items == ["Milstolpe 4, redo för App Store"])
}

@Test func tomOchTrasigText() {
    #expect(Changelog.parse("").isEmpty)
    #expect(Changelog.parse("# Changelog\n\nnågot annat").isEmpty)
    // En version utan datum visas med bara versionen.
    #expect(Changelog.parse("## 2.0.0\n\n### Nytt\n\n* Något").first?.title == "2.0.0")
}

@Test func riktigaChangelogenGårAttLäsa() throws {
    // Repots CHANGELOG.md, som följer med appen. Ändrar Release Please formatet ska det märkas här.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../../CHANGELOG.md").standardizedFileURL
    let versions = Changelog.parse(try String(contentsOf: root, encoding: .utf8))
    #expect(!versions.isEmpty)
    #expect(versions.allSatisfy { $0.title.contains(" · ") && !$0.sections.isEmpty })
    #expect(versions.flatMap(\.sections).flatMap(\.items).allSatisfy { !$0.contains("](") && !$0.contains("([#") })
}
