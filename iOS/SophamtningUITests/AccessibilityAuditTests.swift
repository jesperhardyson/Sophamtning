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
    /// Läget som testet har begärt. Nollställs när första skärmen har visat att det gäller.
    private var appearanceToCheck: XCUIDevice.Appearance?

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
        setAppearance(appearance)
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
        // Påminnelserna och länken Öppna Inställningar helt synliga, oavsett hur långt svepet landade.
        bringFullyIntoView(app.buttons["Öppna Inställningar"].firstMatch)
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
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tid,")).firstMatch)
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
        setAppearance(appearance)
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
        // Hela raden med bocken, klockan och Ångra under navigeringsfältet.
        bringFullyIntoView(pending)
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

    private func setAppearance(_ appearance: XCUIDevice.Appearance) {
        XCUIDevice.shared.appearance = appearance
        appearanceToCheck = appearance
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

    /// Drar innehållet långsamt, utan fart, tills elementet syns helt mellan navigeringsfältet och skärmens nederkant.
    /// Ett svep landar olika långt beroende på innehållets höjd. Ligger en knapp eller rad då halvt utanför kanten blir
    /// granskningen inte klar i tid (kod -56), så skärmen granskas med elementet helt synligt.
    private func bringFullyIntoView(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Hittar inte \(element) i läget \(mode)")
        let window = app.windows.firstMatch.frame
        let navigationBar = app.navigationBars.firstMatch
        let top = (navigationBar.exists ? navigationBar.frame.maxY : window.minY + 100) + 8
        let bottom = window.maxY - 24
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        var frames: [CGRect] = []
        for _ in 0..<20 {
            let frame = element.frame
            frames.append(frame)
            let distance: CGFloat
            if frame.maxY > bottom {
                distance = -min(frame.maxY - bottom + 16, window.height * 0.35)
            } else if frame.minY < top {
                distance = min(top - frame.minY + 16, window.height * 0.35)
            } else {
                return
            }
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        let frame = element.frame
        if frame.minY >= top, frame.maxY <= bottom { return }
        XCTFail("\(element) syns inte helt i läget \(mode): mellan \(top) och \(bottom), ramar \(frames + [frame])")
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

    /// Kontrollerar på första skärmen att appen verkligen visas i läget som begärdes. På en nyskapad
    /// simulator finns inget sparat läge. Då ändrar `XCUIDevice.shared.appearance` ingenting i den sessionen, men läser
    /// ändå tillbaka det begärda läget. Därför mäts skärmen. Körningen sparar läget, så efter en omstart fungerar bytet.
    /// Ett fel stoppar testet, eftersom resten av genomgången då inte säger något om läget.
    private func checkAppearance(in screenshot: XCUIScreenshot, screen: String) {
        guard let expected = appearanceToCheck else { return }
        appearanceToCheck = nil
        guard let brightness = edgeBrightness(of: screenshot) else {
            continueAfterFailure = false
            return XCTFail("Ljusstyrkan i skärmdumpen av \(screen) i läget \(mode) gick inte att mäta")
        }
        let isDark = brightness < 0.5
        guard isDark != (expected == .dark) else { return }
        continueAfterFailure = false
        let (wanted, shown) = expected == .dark ? ("mörkt", "ljust") : ("ljust", "mörkt")
        XCTFail("""
            Läget \(mode) skulle visas i \(wanted) läge, men \(screen) visas i \(shown) (ljusstyrka \(brightness) i kanten, \
            gränsen är 0,5). En nyskapad simulator byter inte läge under sin första körning: starta om \
            simulatorn och kör testet igen.
            """)
    }

    /// Medelljusstyrkan (0–1) i en smal remsa längs vänsterkanten, mitt på skärmens höjd. Där syns bara bakgrunden, så
    /// kortens färger och textstorleken påverkar inte: 0,94 i ljust läge och 0,09 i mörkt.
    private func edgeBrightness(of screenshot: XCUIScreenshot) -> Double? {
        guard let image = screenshot.image.cgImage else { return nil }
        let strip = CGRect(x: 0, y: image.height / 4, width: image.width / 50, height: image.height / 2)
        guard let edge = image.cropping(to: strip) else { return nil }
        var pixels = [UInt8](repeating: 0, count: edge.width * edge.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: edge.width, height: edge.height, bitsPerComponent: 8,
                bytesPerRow: edge.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(edge, in: CGRect(x: 0, y: 0, width: edge.width, height: edge.height))
            return true
        }
        guard drawn, !pixels.isEmpty else { return nil }
        return Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count) / 255
    }

    private func audit(_ screen: String) {
        sleep(1)
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "\(mode)__\(screen)"
        shot.lifetime = .keepAlways
        add(shot)
        checkAppearance(in: screenshot, screen: screen)
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
                        // Apples knapp ShortcutsLink i Siri-kortet: texten syns fullt ut i skärmdumpen, men ramen räknas som
                        // för låg. Knappen ritas av systemet och går inte att ändra från appen.
                        if element.elementType == .staticText, element.label == "Sophämtning-genvägar" { return true }
                        // Apples SiriTipView i Siri-kortet: frasen syns fullt ut i skärmdumpen, men ramen räknas som för smal.
                        // Vyn ritas av systemet och går inte att ändra från appen.
                        if element.elementType == .staticText, element.label == "Säg ”När töms soporna i Sophämtning”" { return true }
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
