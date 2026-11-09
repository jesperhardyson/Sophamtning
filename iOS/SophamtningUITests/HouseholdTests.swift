import XCTest

/// Hushållet med en synk i minnet. Appen startas med `-uitest-hushall`: jag är medlem, Kim är ägare och Testgatan 1 delas.
/// Nästa tömning är i morgon, så att **Ställ ut kärlen** visas. CloudKit körs aldrig här.
@MainActor
final class HouseholdTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitest-hushall", "-AppleLanguages", "(sv)", "-AppleLocale", "sv_SE"]
        app.launch()
    }

    func testHushallsarketVisarDeltagare() {
        XCTAssertTrue(homeCard.waitForExistence(timeout: 20), "Den delade adressen ska visas på hem")
        open("Inställningar")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hushåll")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Inställningar ska ha raden Hushåll")
        row.tap()

        XCTAssertTrue(app.staticTexts["Kim"].waitForExistence(timeout: 20), "Arket ska visa deltagarna")
        XCTAssertTrue(app.buttons["Lämna hushållet"].exists, "En medlem ska kunna lämna hushållet")
        XCTAssertFalse(app.buttons["Hantera medlemmar"].exists, "Bara ägaren hanterar medlemmar")
        XCTAssertFalse(app.buttons["Avsluta hushållet"].exists, "Bara ägaren avslutar hushållet")
    }

    func testStallUtOchAngra() {
        let placeOut = app.buttons["Ställ ut kärlen"]
        XCTAssertTrue(placeOut.waitForExistence(timeout: 20), "Knappen ska visas dagen före tömningen")
        placeOut.tap()

        let mark = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Utställt av dig, kl.")).firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 20), "Bocken ska säga vem som ställde ut och när")
        XCTAssertFalse(placeOut.exists, "Knappen ska vara borta när kärlen är utställda")
        // Ett tryck på bocken gör ingenting: kortet öppnar inte adressen.
        mark.tap()
        XCTAssertFalse(app.staticTexts["Kärlen"].waitForExistence(timeout: 2), "Bocken ska inte öppna adressen")

        let undo = app.buttons["Ångra"]
        XCTAssertTrue(undo.exists, "Bocken ska gå att ångra")
        undo.tap()
        XCTAssertTrue(placeOut.waitForExistence(timeout: 20), "Ångra ska ta tillbaka knappen")
        XCTAssertFalse(mark.exists)
    }

    func testDelaReglaget() {
        XCTAssertTrue(homeCard.waitForExistence(timeout: 20))
        homeCard.tap()
        XCTAssertTrue(app.staticTexts["Kärlen"].waitForExistence(timeout: 20))

        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Dela med hushållet")).firstMatch
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable, "Adressvyn ska ha reglaget Dela med hushållet")
        XCTAssertEqual(toggle.value as? String, "1", "Testgatan delas med hushållet")
    }

    func testVantandeBockHarKlocka() {
        app.terminate()
        app.launchArguments += ["-uitest-hushall-vantar"]
        app.launch()
        let mark = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Utställt av dig, kl.")).firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 20), "Min bock ska visas")
        XCTAssertTrue(mark.label.hasSuffix("skickas när nätet finns"), "En bock som inte skickats ska läsas så: \(mark.label)")
        XCTAssertTrue(app.buttons["Ångra"].exists)
    }

    // MARK: Hjälpare

    private var homeCard: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch
    }

    private func open(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Hittar inte \(label)")
        button.tap()
    }
}
