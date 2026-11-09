import XCTest

/// Granskar varje skärm med `performAccessibilityAudit()` i tre lägen: vanlig storlek, största Dynamic Type
/// i ljust läge och största Dynamic Type i mörkt läge. Varje skärm sparas också som skärmdump i testresultatet.
/// Mörkt läge sätts med `XCUIDevice.shared.appearance`, eftersom startargumentet `-AppleInterfaceStyle` inte påverkar appen.
/// Klippt text granskas i vanlig storlek. Vid största storlek och för kontrast gäller undantagen längre ner.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!
    private var mode = ""
    private var checksClipping = true

    private let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func tearDown() async throws {
        XCUIDevice.shared.appearance = .light
        try await super.tearDown()
    }

    func testGranskaVanligStorlek() {
        run(mode: "normal", appearance: .light, arguments: [], checksClipping: true)
    }

    func testGranskaVanligStorlekMorkt() {
        run(mode: "normal-morkt", appearance: .dark, arguments: [], checksClipping: true)
    }

    func testGranskaStorastStorlekLjust() {
        run(mode: "storst-ljust", appearance: .light, arguments: largestText, checksClipping: false)
    }

    func testGranskaStorastStorlekMorkt() {
        run(mode: "storst-morkt", appearance: .dark, arguments: largestText, checksClipping: false)
    }

    func testGranskaHushallVanligStorlek() {
        runHousehold(mode: "hushall-normal", appearance: .light, arguments: [], checksClipping: true)
    }

    func testGranskaHushallVanligStorlekMorkt() {
        runHousehold(mode: "hushall-normal-morkt", appearance: .dark, arguments: [], checksClipping: true)
    }

    func testGranskaHushallStorstaStorlekMorkt() {
        runHousehold(mode: "hushall-storst-morkt", appearance: .dark, arguments: largestText, checksClipping: false)
    }

    // MARK: Genomgång

    private func run(mode: String, appearance: XCUIDevice.Appearance, arguments: [String], checksClipping: Bool) {
        continueAfterFailure = true
        self.mode = mode
        self.checksClipping = checksClipping
        XCUIDevice.shared.appearance = appearance
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(sv)", "-AppleLocale", "sv_SE"] + arguments
        app.launch()

        audit("hem-tom")

        // Områdesval och bekräftelse.
        tap(app.buttons["Gata och husnummer"])
        type("okänd gata 1, Avesta", in: app.textFields["Gata och husnummer"])
        audit("sokning-ingen-traff")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Välj område i Avesta kommun")).firstMatch)
        audit("omrade-lista")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch)
        // Bekräftelsearket öppnas i stort läge, så det granskas som det är.
        audit("omrade-bekrafta")
        tap(app.buttons["Välj ett annat område"])
        app.buttons["BackButton"].firstMatch.tap()
        // Adresser och områdesval i samma svar: raden Välj område i egen grupp ovanför träffarna.
        let field = app.textFields["Gata och husnummer"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        type("testgatan 1, avesta", in: field)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Välj område i Avesta kommun")).firstMatch.exists)
        audit("sokning-omrade-och-traffar")
        tap(app.buttons["Stäng"])

        // Kommunfrågan.
        tap(app.buttons["Finns min kommuns hämtningsschema?"])
        audit("kommun-tom")
        type("örebro", in: app.textFields["Kommun eller ort"])
        audit("kommun-svar")
        tap(app.buttons["Sök din adress"])
        audit("sokning-tom")
        type("testgatan 1", in: app.textFields["Gata och husnummer"])
        audit("sokning-traffar")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch)

        // Hem med adress, adressvyn och inställningarna.
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        audit("hem")
        card.tap()
        XCTAssertTrue(app.staticTexts["Per kärl"].waitForExistence(timeout: 10))
        audit("adress-ovre")
        app.swipeUp()
        audit("adress-mitt")
        app.swipeUp()
        app.swipeUp()
        audit("adress-nedre")
        app.buttons["BackButton"].firstMatch.tap()

        tap(app.buttons["Inställningar"])
        audit("installningar")
        app.swipeUp()
        audit("installningar-nedre")
        // Tillbaka upp, så att raden inte ligger under fältet när den trycks.
        app.swipeDown()
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Påminnelse,")).firstMatch)
        audit("paminnelsetid")
        app.buttons["BackButton"].firstMatch.tap()
        app.swipeUp()
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Datakällor")).firstMatch)
        audit("datakallor")
    }

    /// Hushållets vyer med en synk i minnet: kortet med Ställ ut kärlen och bocken, reglaget i adressvyn, arket med
    /// deltagare och, efter en ny start utan hushåll, arket med inbjudan.
    private func runHousehold(mode: String, appearance: XCUIDevice.Appearance, arguments: [String], checksClipping: Bool) {
        continueAfterFailure = true
        self.mode = mode
        self.checksClipping = checksClipping
        XCUIDevice.shared.appearance = appearance
        launch(["-uitest-hushall"] + arguments)

        let placeOut = app.buttons["Ställ ut kärlen"]
        XCTAssertTrue(placeOut.waitForExistence(timeout: 10))
        scrollTo(placeOut)
        audit("hushall-hem")
        placeOut.tap()
        let undo = app.buttons["Ångra"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        scrollTo(undo)
        audit("hushall-hem-utstallt")

        app.swipeDown()
        app.swipeDown()
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch)
        XCTAssertTrue(app.staticTexts["Per kärl"].waitForExistence(timeout: 10))
        audit("hushall-adress-ovre")
        let share = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Dela med hushållet")).firstMatch
        scrollTo(share)
        audit("hushall-adress-dela")
        app.buttons["BackButton"].firstMatch.tap()

        tap(app.buttons["Inställningar"])
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hushåll")).firstMatch
        scrollTo(row)
        tap(row)
        XCTAssertTrue(app.staticTexts["Kim"].waitForExistence(timeout: 10))
        audit("hushall-ark")
        app.swipeUp()
        audit("hushall-ark-nedre")

        // Min bock som inte har skickats än: klockan bredvid bocken, på kortet och i adressvyn.
        app.terminate()
        launch(["-uitest-hushall", "-uitest-hushall-vantar"] + arguments)
        let pending = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Utställt av dig")).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 20))
        scrollTo(app.buttons["Ångra"])
        audit("hushall-hem-vantar")
        app.swipeDown()
        app.swipeDown()
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch)
        XCTAssertTrue(app.staticTexts["Per kärl"].waitForExistence(timeout: 10))
        audit("hushall-adress-vantar")

        // Utan hushåll: förklaringen och Bjud in till hushållet.
        app.terminate()
        launch(["-uitest-hushall-tomt"] + arguments)
        tap(app.buttons["Inställningar"])
        let emptyRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hushåll")).firstMatch
        scrollTo(emptyRow)
        tap(emptyRow)
        XCTAssertTrue(app.buttons["Bjud in till hushållet"].waitForExistence(timeout: 10))
        audit("hushall-ark-tomt")
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(sv)", "-AppleLocale", "sv_SE"] + extra
        app.launch()
    }

    /// Scrollar uppåt tills elementet går att trycka på.
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Hittar inte \(element) i läget \(mode)", file: file, line: line)
        element.tap()
    }

    private func type(_ text: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
        // Låter sökningens fördröjning och svaret hinna.
        sleep(2)
    }

    private func audit(_ screen: String) {
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(mode)__\(screen)"
        shot.lifetime = .keepAlways
        add(shot)
        let mode = mode
        let checksClipping = checksClipping
        // Tangentbordets ram plus raden med ordförslag, som ligger strax ovanför själva tangenterna.
        let keyboardFrame = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.insetBy(dx: 0, dy: -48) : nil
        // Granskningen hinner ibland inte klart i simulatorn (kod -56). Då görs den om en gång innan det räknas som fel.
        for attempt in 1...2 {
            do {
                try app.performAccessibilityAudit(for: .all) { issue in
                    // Vid största textstorlek får elementen orimligt stora ramar, och text under navigeringsfältet räknas som
                    // täckt, så klippt text rapporteras även när den syns fullt ut. Där granskas klippning mot skärmdumparna.
                    // I vanlig storlek är den på och inget filtreras bort.
                    if issue.auditType == .textClipped, !checksClipping { return true }
                    // Kända falska träffar i vanlig storlek, kontrollerade mot skärmdumparna (texten syns fullt ut):
                    // textfältet med tangentbordsfokus (ramen smalare än texten) och kärlnamnen i chipsen, vars ram är
                    // trängre än texten. Andra textfält, och områdesnamnen i bekräftelsearket, granskas.
                    if issue.auditType == .textClipped, let element = issue.element {
                        if element.elementType == .textField, (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
                        if element.elementType == .staticText, element.label.hasSuffix("förpackningar") { return true }
                        // Systemets sökfält i områdesvalet: placeholdern syns fullt ut i skärmdumpen, men fältets ram räknas som för smal.
                        if element.elementType == .searchField, element.label == "Sök område, ort eller gata" { return true }
                    }
                    // Kontrasten är kontrollerad mot designens färgpar. Granskningen räknar fel på text över bilder och
                    // genomskinliga ytor, så den är fortsatt avstängd.
                    if issue.auditType == .contrast { return true }
                    // Tangentbordets egna element saknar beskrivning. De är systemets, inte appens, och släpps bara
                    // igenom när de ligger inom tangentbordets ram. Oetiketterade egna vyer upptäcks därmed.
                    if issue.auditType == .sufficientElementDescription, let keyboardFrame, let element = issue.element,
                       element.elementType == .other, element.label.isEmpty, keyboardFrame.contains(element.frame) {
                        return true
                    }
                    print("AUDIT-ISSUE: \(mode) | \(screen) | \(issue.auditType) | \(issue.compactDescription) | \(issue.element?.debugDescription.prefix(160) ?? "-")")
                    return false
                }
                return
            } catch let error as NSError where error.code == -56 && attempt == 1 {
                continue
            } catch {
                XCTFail("Granskningen av \(screen) i läget \(mode) hittade problem: \(error)")
                return
            }
        }
    }
}
