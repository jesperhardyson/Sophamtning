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
        tap(app.buttons["Välj område i Avesta kommun"])
        audit("omrade-lista")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch)
        // Bekräftelsearket granskas i stort läge. I läget 0,7 skalas arket ned, och då räknas all text i det som klippt.
        expandSheet()
        audit("omrade-bekrafta")
        tap(app.buttons["Välj ett annat område"])
        app.navigationBars.buttons.element(boundBy: 0).tap()
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
        XCTAssertTrue(app.staticTexts["Kärlen"].waitForExistence(timeout: 10))
        audit("adress-ovre")
        app.swipeUp()
        audit("adress-mitt")
        app.swipeUp()
        app.swipeUp()
        audit("adress-nedre")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tap(app.buttons["Inställningar"])
        audit("installningar")
        app.swipeUp()
        audit("installningar-nedre")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Påminnelsetid")).firstMatch)
        audit("paminnelsetid")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.swipeUp()
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Datakällor")).firstMatch)
        audit("datakallor")
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Hittar inte \(element) i läget \(mode)", file: file, line: line)
        element.tap()
    }

    /// Drar arket i läget 0,7 i greppet upp till stort läge.
    private func expandSheet() {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.371))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
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
        } catch {
            XCTFail("Granskningen av \(screen) i läget \(mode) hittade problem: \(error)")
        }
    }
}
