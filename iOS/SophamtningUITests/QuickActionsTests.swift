import XCTest

/// Svepet för adresserna på hemskärmen. Det är en egen gest, så den prövas här. Trösklarna och reglerna för tryck
/// prövas i `SwipeRevealTests`, och valen i snabbmenyn i `AddressActionTests`. Appen startas med `-uitest`, med stubben och en tom lagring.
@MainActor
final class QuickActionsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(sv)", "-AppleLocale", "sv_SE"]
    }

    // MARK: Svep

    func testSvepVisarTaBortOchAvbrytBehallerAdressen() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])
        let row = address("Testgatan 2")
        let start = row.frame.minX

        // Ett kort svep öppnar raden och visar knappen.
        drag(row, by: -140)
        let button = app.buttons["svep-ta-bort"]
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Svepet ska visa Ta bort")
        XCTAssertLessThan(row.frame.minX, start - 60, "Raden ska stå öppen")
        XCTAssertFalse(app.staticTexts["Kärlen"].exists, "Svepet får inte öppna adressen")
        button.tap()

        XCTAssertTrue(app.staticTexts["Ta bort adressen?"].waitForExistence(timeout: 3), "Bekräftelsen ska visas")
        cancelRemoval()

        XCTAssertTrue(row.waitForExistence(timeout: 3), "Avbryt ska behålla adressen")
        waitUntil(row, "Raden ska glida tillbaka") { abs($0.frame.minX - start) < 1 }
        XCTAssertFalse(app.buttons["svep-ta-bort"].exists)
    }

    // MARK: Hjälpare

    /// Huvudkortet eller raden för adressen.
    private func address(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND identifier != %@", name, "svep-ta-bort")).firstMatch
    }

    /// I iOS 26 visas bekräftelsen som en ruta vid kortet. Den har Avbryt bara när den visas som ark, annars stängs den
    /// med ett tryck utanför.
    private func cancelRemoval() {
        let cancel = app.buttons["Avbryt"]
        if cancel.exists {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.staticTexts["Ta bort adressen?"].waitForNonExistence(timeout: 3), "Bekräftelsen ska stängas")
    }

    /// Ett lugnt drag i sidled från radens mitt.
    private func drag(_ element: XCUIElement, by dx: CGFloat) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: dx, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    private func waitUntil(_ element: XCUIElement, _ message: String, _ condition: @escaping (XCUIElement) -> Bool) {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if condition(element) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail(message)
    }

    /// Lägger till adresserna i ordning. Den första blir huvudadress.
    private func addAddresses(_ names: [String]) {
        for (index, name) in names.enumerated() {
            let open = index == 0 ? app.buttons["Gata och husnummer"] : app.buttons["Lägg till"]
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            open.tap()
            let field = app.textFields["Gata och husnummer"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name.lowercased())
            let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(hit.waitForExistence(timeout: 10), "Sökningen ska ge \(name)")
            hit.tap()
            XCTAssertTrue(address(name).waitForExistence(timeout: 10), "\(name) ska visas på hem")
        }
    }
}
