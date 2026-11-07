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

        XCTAssertTrue(app.staticTexts["hem-rubrik"].waitForExistence(timeout: 5))
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

        let choose = app.buttons["Välj område i Avesta kommun"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()

        let area = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        area.tap()

        // Bekräftelsen visas, men inget är sparat än.
        XCTAssertTrue(app.staticTexts["Stämmer området?"].waitForExistence(timeout: 5))
        app.buttons["Välj ett annat område"].tap()
        // Tillbaka till sökningen, där arket kan stängas.
        app.buttons["BackButton"].firstMatch.tap()
        close()
        XCTAssertTrue(app.staticTexts["När töms dina kärl?"].waitForExistence(timeout: 5), "Inget får sparas före Spara området")

        // Spara området: först nu sparas det.
        open("Gata och husnummer")
        let again = app.textFields["Gata och husnummer"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        again.typeText("okänd gata 1, Avesta")
        XCTAssertTrue(app.buttons["Välj område i Avesta kommun"].waitForExistence(timeout: 10))
        app.buttons["Välj område i Avesta kommun"].tap()
        let sameArea = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(sameArea.waitForExistence(timeout: 5))
        sameArea.tap()
        let save = app.buttons["Spara området"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["När töms dina kärl?"].exists)
    }

    func testOmradeslistanVisarDetaljerOchKallansForklaring() {
        open("Gata och husnummer")
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("okänd gata 1, Avesta")
        open("Välj område i Avesta kommun")

        // Källans förklaring står överst, och hjälpraden med telefonnumret under.
        XCTAssertTrue(app.staticTexts["Avesta Vatten publicerar sophämtningen per område, men inte vilka adresser som hör till vilket område."].waitForExistence(timeout: 5))
        let help = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0226-64 55 00")).firstMatch
        XCTAssertTrue(help.exists, "Hjälpraden ska synas")

        // Raden läses som en enhet med etikett, dag och alla platser, också de som den korta raden inte visar.
        let area = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Askön, Nyhyttan m.fl., Område 1, Måndag, udda vecka.")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        XCTAssertTrue(area.label.contains("Platser: Askön, Nyhyttan"))
        XCTAssertTrue(area.label.contains("Högbo och Rutbo"), "VoiceOver ska läsa hela listan med platser")

        // Ett område med platser som har en annan dag läser också dem.
        let other = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bodgatan (onsdag, jämn vecka)")).firstMatch
        XCTAssertTrue(other.exists, "Platser med andra dagar ska visas")

        // Bekräftelsen visar alla platser när listan fälls ut.
        area.tap()
        XCTAssertTrue(app.staticTexts["Stämmer området?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Välj ett annat område"].isHittable, "Knapparna ska synas utan att listan fällts ut")
        app.buttons["Visa alla 18 platser"].tap()
        XCTAssertTrue(app.buttons["Visa färre platser"].waitForExistence(timeout: 5))
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Högbo och Rutbo")).firstMatch
        XCTAssertTrue(details.exists, "Bekräftelsen ska visa hela listan med platser")
    }

    func testSchematGallerTillVisasForAvestaMenInteForLivekalla() {
        // Live-källan har `schedule: null`, så raden syns inte.
        addAddress()
        XCTAssertTrue(homeCard.waitForExistence(timeout: 5))
        homeCard.tap()
        XCTAssertTrue(app.staticTexts["Kommande"].waitForExistence(timeout: 5))
        let period = NSPredicate(format: "label BEGINSWITH %@", "Schemat gäller till")
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(app.descendants(matching: .any).matching(period).firstMatch.exists, "Live-källor ska inte visa hur långt schemat gäller")
        app.buttons["BackButton"].firstMatch.tap()

        // Avesta anger hur långt schemat gäller och varför.
        open("Lägg till")
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("okänd gata 1, Avesta")
        open("Välj område i Avesta kommun")
        let area = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        area.tap()
        open("Spara området")
        let avesta = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(avesta.waitForExistence(timeout: 5))
        avesta.tap()
        XCTAssertTrue(app.staticTexts["Kommande"].waitForExistence(timeout: 5))
        let line = app.descendants(matching: .any).matching(period).firstMatch
        for _ in 0..<4 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 5), "Avesta ska visa hur långt schemat gäller")
        XCTAssertTrue(line.label.contains("Avesta Vatten publicerar hämtschemat ett år i taget."), "Orsaken ska stå under raden")
    }

    func testHittaOmradeKnappenSynsNarKalendernArUtfalld() {
        open("Gata och husnummer")
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("okänd gata 1, Avesta")
        open("Välj område i Avesta kommun")
        let finder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Vet du inte vilket område?")).firstMatch
        XCTAssertTrue(finder.waitForExistence(timeout: 5))
        finder.tap()

        // Kalendern är utfälld från början, och knappen står ovanför hemindikatorn utan att arket dras upp.
        let find = app.buttons["Hitta område"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertTrue(find.isHittable, "Hitta område ska synas när kalendern är utfälld")

        // Fäll ihop kalendern och ut igen: knappen ska fortfarande synas.
        let date = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Senaste tömning")).firstMatch
        date.tap()
        XCTAssertTrue(find.waitForNonExistence(timeout: 5))
        date.tap()
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertTrue(find.isHittable, "Hitta område ska synas när kalendern fällts ut igen")
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

    // MARK: Inträdet

    func testInstradetTomtLageVisarKorten() {
        relaunchWithEntrance()
        waitUntilHittable(app.buttons["Gata och husnummer"], "Korten i det tomma läget ska komma in")
    }

    func testInstradetMedAdressVisarKortetOchSchemaraderna() {
        addAddress()
        XCTAssertTrue(homeCard.waitForExistence(timeout: 5))
        relaunchWithEntrance()
        waitUntilHittable(homeCard, "Hemkortet ska komma in")

        homeCard.tap()
        // "Kommande" ligger direkt under nästa tömning, och raderna väntar tills listan syns. Raden som prövas är den
        // första under rubriken. Kortet för nästa tömning läser samma kärl, så det utesluts.
        let title = app.staticTexts["Kommande"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        for _ in 0..<6 where !(title.isHittable && title.frame.maxY < app.frame.maxY - 240) { app.swipeUp() }
        let row = app.otherElements.matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label BEGINSWITH %@)", "dagar. Plastförpackningar", "Nästa tömning")).element(boundBy: 0)
        XCTAssertTrue(row.exists, "Schemaraderna ska finnas")
        XCTAssertGreaterThan(row.frame.minY, title.frame.maxY, "Raden ska vara den första under rubriken")
        XCTAssertLessThan(row.frame.minY - title.frame.maxY, 120, "Raden ska vara den första under rubriken")
        // En rad med full genomskinlighet finns kvar och går att träffa, så bara pixlarna visar om den syns.
        waitUntilDrawn(row, "Schemaraderna ska synas efter scrollning")
    }

    // MARK: Hjälpare

    /// Startar om appen med det som sparats, och med introt och korten som vid en vanlig start.
    private func relaunchWithEntrance() {
        app.terminate()
        app.launchArguments = ["-uitest-intrade", "-AppleLanguages", "(sv)", "-AppleLocale", "sv_SE"]
        app.launch()
    }

    /// Introt tar 1,2 s och korten kommer in medan det lämnar, så elementet ska gå att trycka på inom 3 s.
    private func waitUntilHittable(_ element: XCUIElement, _ message: String) {
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        wait(for: [hittable], timeout: 3)
        XCTAssertTrue(element.isHittable, message)
    }

    /// Huvudkortet på hemskärmen.
    private var homeCard: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testgatan 1")).firstMatch
    }

    /// Väntar tills elementet har synligt innehåll i skärmbilden, och inte bara en tom bakgrund.
    private func waitUntilDrawn(_ element: XCUIElement, _ message: String) {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if hasContent(element.screenshot().image) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail(message)
    }

    /// Sant om någon pixel skiljer sig tydligt från den första, som är bakgrunden.
    private func hasContent(_ image: UIImage) -> Bool {
        guard let source = image.cgImage else { return false }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, pixels.count >= 4 else { return false }
        let first = Array(pixels[0..<3])
        return stride(from: 0, to: pixels.count, by: 4).contains { offset in
            (0..<3).contains { abs(Int(pixels[offset + $0]) - Int(first[$0])) > 64 }
        }
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
