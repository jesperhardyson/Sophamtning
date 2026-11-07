import XCTest

/// Största textstorleken: hem, adressvyn och hela schemat ryms i skärmens bredd. Rubriken står kvar vid marginalen,
/// och inget element går utanför höger kant. Kärlkorten ligger i en ScrollView i sidled och får gå utanför.
@MainActor
final class LargestTextTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = [
            "-uitest", "-AppleLanguages", "(sv)", "-AppleLocale", "sv_SE",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
    }

    func testStorstaTextenRymsIBredden() {
        // Hem, tomt läge och med en adress.
        let home = app.staticTexts["När töms dina kärl?"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        checkFits("hem-tom", title: home)
        addAddress()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Huvudkortet ska visa adressen")
        checkFits("hem", title: app.staticTexts["hem-rubrik"])

        // Adressvyn.
        // Kortet är högre än skärmen, så trycket görs nära dess överkant, när arket har stängts.
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: card)
        wait(for: [hittable], timeout: 10)
        card.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: card.frame.width / 2, dy: 400)).tap()
        XCTAssertTrue(app.staticTexts["Kärlen"].waitForExistence(timeout: 10))
        // Huvudadressen heter "Hemma".
        let title = app.staticTexts["Hemma"]
        checkFits("adress", title: title)

        // Hela schemat.
        let link = app.buttons["Hela schemat"]
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable, "Länken till hela schemat ska finnas")
        link.tap()
        let row = app.otherElements.matching(NSPredicate(format: "label CONTAINS %@", "Plastförpackningar")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Hela schemat ska visa raderna")
        checkFits("hela-schemat", title: row)
    }

    // MARK: Hjälpare

    /// Rubriken börjar vid marginalen, och inget element utom kärlkorten slutar till höger om fönstret.
    private func checkFits(_ screen: String, title: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let width = app.windows.firstMatch.frame.width
        XCTAssertGreaterThanOrEqual(title.frame.minX, 24 - 0.5, "\(screen): rubriken ska börja vid marginalen", file: file, line: line)
        let bins = binBand()
        guard let root = try? app.snapshot() else { return XCTFail("\(screen): ingen ögonblicksbild", file: file, line: line) }
        for element in flatten(root) where element.frame.maxX > width + 0.5 && !element.frame.isEmpty {
            let frame = element.frame
            if let bins, frame.minY >= bins.lowerBound - 1, frame.maxY <= bins.upperBound + 1 { continue }
            XCTFail("\(screen): \(element.elementType.rawValue) '\(element.label)' slutar vid \(frame.maxX), fönstret är \(width) brett", file: file, line: line)
        }
    }

    private func flatten(_ element: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        [element] + element.children.flatMap { flatten($0) }
    }

    /// Höjden där kärlkorten ligger, mellan rubriken "Kärlen" och "Påminnelser".
    private func binBand() -> ClosedRange<CGFloat>? {
        let top = app.staticTexts["Kärlen"]
        let bottom = app.staticTexts["Påminnelser"]
        guard top.exists, bottom.exists else { return nil }
        return top.frame.maxY...bottom.frame.minY
    }

    /// Söker och sparar Testgatan 1 från det tomma hemläget.
    private func addAddress() {
        let open = app.buttons["Gata och husnummer"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("testgatan 1")
        let hit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10), "Sökningen ska ge träffar")
        hit.tap()
    }
}
