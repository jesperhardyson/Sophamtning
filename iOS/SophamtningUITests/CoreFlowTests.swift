import XCTest

/// Kärnflödena i simulatorn. Appen startas med `-uitest`, som ger en stubb utan nät och en tom lagring.
/// Testdatat ligger i `Sophamtning/UITestData/` och innehåller inga riktiga hemadresser.
@MainActor
final class CoreFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(sv)", "-AppleLocale", "sv_SE"]
        app.launch()
    }

    // MARK: Flöden

    func testKommunfraganLederTillSokning() {
        open("Finns min kommuns hämtningsschema?")
        let field = app.textFields["Kommun eller ort"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("örebro")

        let search = app.buttons["Sök din adress"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Svaret för Örebro ska erbjuda adresssökning")
        search.tap()

        XCTAssertTrue(app.navigationBars["Lägg till adress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Gata och husnummer"].exists)
    }

    func testLaggaTillAdressVisasPaHem() {
        addAddress()

        XCTAssertTrue(app.staticTexts["Sophämtning"].waitForExistence(timeout: 5))
        XCTAssertTrue(homeCard.waitForExistence(timeout: 5), "Huvudkortet ska visa den sparade adressen")
        XCTAssertFalse(app.staticTexts["När töms dina kärl?"].exists, "Det tomma läget ska vara borta")
    }

    func testOmradeKraverBekraftelse() {
        open("Gata och husnummer")
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // Ingen adress matchar, och orten har områden i stället för adresser.
        field.typeText("okänd gata 1, Avesta")

        let choose = app.buttons["Välj område i Avesta"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()

        let area = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        area.tap()

        // Bekräftelsen visas, men inget är sparat än.
        XCTAssertTrue(app.staticTexts["Stämmer området?"].waitForExistence(timeout: 5))
        app.buttons["Välj ett annat område"].tap()
        // Tillbaka till sökningen, där arket kan stängas.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        close()
        XCTAssertTrue(app.staticTexts["När töms dina kärl?"].waitForExistence(timeout: 5), "Inget får sparas före Spara området")

        // Spara området: först nu sparas det.
        open("Gata och husnummer")
        let again = app.textFields["Gata och husnummer"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        again.typeText("okänd gata 1, Avesta")
        XCTAssertTrue(app.buttons["Välj område i Avesta"].waitForExistence(timeout: 10))
        app.buttons["Välj område i Avesta"].tap()
        let sameArea = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(sameArea.waitForExistence(timeout: 5))
        sameArea.tap()
        let save = app.buttons["Spara området"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["När töms dina kärl?"].exists)
    }

    func testPaminnelserArAvstangdaFranBorjan() {
        addAddress()
        XCTAssertTrue(homeCard.waitForExistence(timeout: 5))
        homeCard.tap()

        let notification = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Notis kvällen före")).firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: 5))
        XCTAssertEqual(notification.value as? String, "0", "Notis ska vara avstängd från början")

        let liveActivity = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Live Activity")).firstMatch
        XCTAssertTrue(liveActivity.exists)
        XCTAssertEqual(liveActivity.value as? String, "0", "Live Activity ska vara avstängd från början")
    }

    // MARK: Hjälpare

    /// Huvudkortet på hemskärmen.
    private var homeCard: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch
    }

    private func open(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Hittar inte \(label)")
        button.tap()
    }

    private func close() {
        app.buttons["Stäng"].tap()
    }

    /// Söker och sparar Testgatan 1 från det tomma hemläget.
    private func addAddress() {
        open("Gata och husnummer")
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("testgatan 1")
        let hit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10), "Sökningen ska ge träffar")
        hit.tap()
    }
}
