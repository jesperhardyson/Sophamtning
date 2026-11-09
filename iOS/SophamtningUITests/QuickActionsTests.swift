import XCTest

/// Svep och snabbmeny för adresserna på hemskärmen. Appen startas med `-uitest`, med stubben och en tom lagring.
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

    func testFulltSvepTarBortEfterBekraftelse() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])
        let row = address("Testgatan 2")

        drag(row, by: -320)
        XCTAssertTrue(app.staticTexts["Ta bort adressen?"].waitForExistence(timeout: 3), "Ett fullt svep ska öppna bekräftelsen")
        confirmRemoval()

        waitUntil(row, "Adressen ska försvinna") { !$0.exists }
        XCTAssertFalse(app.staticTexts["Fler adresser"].exists)
        XCTAssertTrue(address("Testgatan 1").exists, "Huvudadressen ska vara kvar")
    }

    func testBorttagenHuvudadressGerAldstaKvarvarandeOchSistaGerTomtLage() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2", "Testgatan 3"])

        // Huvudkortet ligger över "Fler adresser".
        XCTAssertTrue(address("Testgatan 1").waitForExistence(timeout: 5))
        let start = address("Testgatan 1").frame.minX
        drag(address("Testgatan 1"), by: -320)
        confirmRemoval()
        waitUntil(address("Testgatan 1"), "Huvudadressen ska försvinna") { !$0.exists }
        let header = app.staticTexts["Fler adresser"]
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertLessThan(address("Testgatan 2").frame.maxY, header.frame.minY, "Den äldsta kvarvarande ska bli huvudadress")
        // Svepet följer inte med till den nya huvudadressen.
        waitUntil(address("Testgatan 2"), "Den nya huvudadressen ska stå i startläget") { abs($0.frame.minX - start) < 1 }
        XCTAssertFalse(app.buttons["svep-ta-bort"].exists, "Ingen knapp ska synas efter borttagningen")
        XCTAssertGreaterThan(address("Testgatan 3").frame.minY, header.frame.maxY)

        drag(address("Testgatan 2"), by: -320)
        confirmRemoval()
        waitUntil(header, "Bara en adress ska vara kvar") { !$0.exists }
        drag(address("Testgatan 3"), by: -320)
        confirmRemoval()
        XCTAssertTrue(app.staticTexts["När töms dina kärl?"].waitForExistence(timeout: 5), "Sista adressen ska ge tomt läge")
    }

    func testTryckPaKortetOppnarFortfarandeAdressen() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])
        address("Testgatan 1").tap()
        XCTAssertTrue(app.staticTexts["Kärlen"].waitForExistence(timeout: 5), "Huvudkortet ska öppna adressvyn")
        app.buttons["BackButton"].firstMatch.tap()

        address("Testgatan 2").tap()
        XCTAssertTrue(app.staticTexts["Kärlen"].waitForExistence(timeout: 5), "Raden ska öppna adressvyn")
    }

    func testTryckPaOppenRadStangerDen() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])
        let row = address("Testgatan 2")
        let start = row.frame.minX
        drag(row, by: -140)
        XCTAssertTrue(app.buttons["svep-ta-bort"].waitForExistence(timeout: 3))

        row.tap()
        waitUntil(row, "Raden ska stängas") { abs($0.frame.minX - start) < 1 }
        XCTAssertFalse(app.staticTexts["Kärlen"].exists, "Ett tryck på en öppen rad ska stänga den, inte öppna adressen")
    }

    func testBaraEnRadArOppen() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])
        let card = address("Testgatan 1"), row = address("Testgatan 2")
        let cardStart = card.frame.minX, rowStart = row.frame.minX

        drag(row, by: -140)
        waitUntil(row, "Raden ska stå öppen") { $0.frame.minX < rowStart - 60 }

        // Ett svep på huvudkortet öppnar det och stänger raden.
        drag(card, by: -100)
        waitUntil(card, "Huvudkortet ska stå öppet") { $0.frame.minX < cardStart - 30 }
        waitUntil(row, "Raden ska stängas") { abs($0.frame.minX - rowStart) < 1 }
        XCTAssertEqual(app.buttons.matching(identifier: "svep-ta-bort").count, 1, "Bara en rad ska vara öppen")
    }

    func testScrollningStangerOppenRad() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])
        let row = address("Testgatan 2")
        let start = row.frame.minX
        drag(row, by: -140)
        waitUntil(row, "Raden ska stå öppen") { $0.frame.minX < start - 60 }

        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -200)), withVelocity: .slow, thenHoldForDuration: 0.1)
        waitUntil(row, "Scrollningen ska stänga raden") { abs($0.frame.minX - start) < 1 }
        XCTAssertFalse(app.buttons["svep-ta-bort"].exists)
    }

    func testTryckUtanforStangerRadenOchGorIngetAnnat() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])
        let row = address("Testgatan 2")
        let start = row.frame.minX
        drag(row, by: -140)
        waitUntil(row, "Raden ska stå öppen") { $0.frame.minX < start - 60 }

        // Ett tryck på huvudkortet stänger raden utan att öppna adressen.
        address("Testgatan 1").tap()
        waitUntil(row, "Raden ska stängas") { abs($0.frame.minX - start) < 1 }
        XCTAssertFalse(app.staticTexts["Kärlen"].exists, "Trycket utanför ska bara stänga raden")

        // Ett tryck på Lägg till gör inte heller något annat.
        drag(row, by: -140)
        waitUntil(row, "Raden ska stå öppen") { $0.frame.minX < start - 60 }
        app.buttons["Lägg till"].tap()
        waitUntil(row, "Raden ska stängas") { abs($0.frame.minX - start) < 1 }
        XCTAssertFalse(app.textFields["Gata och husnummer"].exists, "Trycket utanför ska inte öppna sökningen")

        // Ett tryck nedanför innehållet stänger också raden.
        drag(row, by: -140)
        waitUntil(row, "Raden ska stå öppen") { $0.frame.minX < start - 60 }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        waitUntil(row, "Raden ska stängas") { abs($0.frame.minX - start) < 1 }
    }

    func testVertikalScrollningFranKortet() {
        // Största textstorleken gör hemskärmen högre än skärmen.
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])
        let card = address("Testgatan 1")
        let before = card.frame

        // Kortet är högre än skärmen, så rörelsen börjar en bit ned på kortets synliga del.
        let from = card.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: card.frame.width / 2, dy: 300))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -250)), withVelocity: .slow, thenHoldForDuration: 0.3)

        XCTAssertLessThan(card.frame.minY, before.minY - 100, "Hemskärmen ska scrolla när rörelsen börjar på kortet")
        XCTAssertEqual(card.frame.minX, before.minX, accuracy: 1, "Kortet ska inte svepas i sidled")
        XCTAssertFalse(app.buttons["svep-ta-bort"].exists)
        XCTAssertFalse(app.staticTexts["Kärlen"].exists, "Scrollningen får inte öppna adressen")
    }

    // MARK: Snabbmeny

    func testLangtTryckOppnarSnabbmenyn() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])

        address("Testgatan 1").press(forDuration: 1.2)
        XCTAssertTrue(menuItem("Byt namn").waitForExistence(timeout: 3), "Snabbmenyn ska öppnas")
        XCTAssertTrue(menuItem("Notis kvällen före").exists)
        XCTAssertFalse(isOn(menuItem("Notis kvällen före")), "Notisen ska vara av från början")
        XCTAssertTrue(menuItem("Live Activity").exists, "Live Activity finns för huvudadressen")
        // XCUITest visar inte undertexten i en meny, men den gör valet en rad högre än de andra.
        XCTAssertGreaterThan(menuItem("Live Activity").frame.height, menuItem("Byt namn").frame.height + 10, "Live Activity ska ha en undertext")
        XCTAssertFalse(isOn(menuItem("Live Activity")), "Live Activity ska vara av från början")
        XCTAssertFalse(menuItem("Gör till huvudadress").exists, "Huvudadressen är redan huvudadress")
        XCTAssertTrue(menuItem("Ta bort").exists)
        dismissMenu()

        address("Testgatan 2").press(forDuration: 1.2)
        XCTAssertTrue(menuItem("Gör till huvudadress").waitForExistence(timeout: 3))
        XCTAssertFalse(isOn(menuItem("Notis kvällen före")), "Notisen ska vara av från början")
        XCTAssertFalse(menuItem("Live Activity").exists, "Live Activity gäller bara huvudadressen")
        menuItem("Gör till huvudadress").tap()

        let header = app.staticTexts["Fler adresser"]
        waitUntil(address("Testgatan 2"), "Testgatan 2 ska bli huvudadress") { $0.frame.maxY < header.frame.minY }
    }

    func testSnabbmenynByterNamnOchTarBort() {
        app.launch()
        addAddresses(["Testgatan 1", "Testgatan 2"])

        address("Testgatan 2").press(forDuration: 1.2)
        menuItem("Byt namn").tap()
        let field = app.textFields["Namn"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Samma dialog som i adressvyn")
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Markera alla"].waitForExistence(timeout: 2) { app.menuItems["Markera alla"].tap() }
        field.typeText("Stugan")
        app.buttons["Spara"].tap()
        XCTAssertTrue(address("Stugan").waitForExistence(timeout: 3), "Det nya namnet ska synas")

        address("Stugan").press(forDuration: 1.2)
        menuItem("Ta bort").tap()
        XCTAssertTrue(app.staticTexts["Ta bort adressen?"].waitForExistence(timeout: 3))
        cancelRemoval()
        XCTAssertTrue(address("Stugan").waitForExistence(timeout: 3), "Avbryt ska behålla adressen")

        address("Stugan").press(forDuration: 1.2)
        menuItem("Ta bort").tap()
        confirmRemoval()
        waitUntil(address("Stugan"), "Adressen ska försvinna") { !$0.exists }
    }

    // MARK: Hjälpare

    /// Huvudkortet eller raden för adressen.
    private func address(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND identifier != %@", name, "svep-ta-bort")).firstMatch
    }

    /// Ett val i snabbmenyn. Reglagen i menyn kan visas som knappar eller som reglage.
    private func menuItem(_ label: String) -> XCUIElement {
        app.collectionViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Ett reglage i menyn är på när det är valt.
    private func isOn(_ element: XCUIElement) -> Bool {
        element.isSelected || (element.value as? String) == "1"
    }

    /// Ett tryck vid skärmens kant, utanför menyn och kortet, stänger menyn.
    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        XCTAssertTrue(menuItem("Byt namn").waitForNonExistence(timeout: 3))
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

    private func confirmRemoval() {
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Ta bort", "svep-ta-bort")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "Bekräftelsen ska visas")
        confirm.tap()
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
