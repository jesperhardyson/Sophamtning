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

        // Varningen står kvar, och källans förklaring står under sin rubrik med hjälpraden och telefonnumret.
        XCTAssertTrue(app.staticTexts["Du väljer området själv"].waitForExistence(timeout: 5), "Varningen med notice ska stå kvar")
        XCTAssertTrue(app.staticTexts["Därför väljer du område i stället för adress"].exists)
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
        XCTAssertTrue(other.label.contains("Vissa gator har en annan hämtdag. Till exempel"), "Raderna ska ha rubriken som på webben")

        // Bekräftelsen visar alla platser först när listan fälls ut. Raden prövas som synlig text, eftersom VoiceOver-texten
        // alltid har alla platser. Den korta raden prövas inte, eftersom listan bakom arket har samma text.
        area.tap()
        XCTAssertTrue(app.staticTexts["Stämmer området?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Välj ett annat område"].isHittable, "Knapparna ska synas utan att listan fällts ut")
        let fullLine = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Askön, Nyhyttan, Klintbo, Snickarbo, Knallasbenning", "Högbo och Rutbo")).firstMatch
        XCTAssertFalse(fullLine.exists, "Hela listan ska inte synas före utfällningen")
        app.buttons["Visa alla 18 platser"].tap()
        XCTAssertTrue(fullLine.waitForExistence(timeout: 5), "Bekräftelsen ska visa hela listan med platser")
        XCTAssertTrue(app.buttons["Visa färre platser"].exists)
    }

    func testOmradeslistanGarAttSoka() {
        open("Gata och husnummer")
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("okänd gata 1, Avesta")
        open("Välj område i Avesta kommun")

        // Systemets sökfält står överst, och varningen står kvar under det.
        let search = app.searchFields["Sök område, ort eller gata"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Du väljer området själv"].exists, "Varningen ska stå kvar")
        let askon = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Askön, Nyhyttan")).firstMatch
        XCTAssertTrue(askon.waitForExistence(timeout: 5))

        // En plats som bara står i listan över platser hittar rätt område.
        search.tap()
        search.typeText("klintbo")
        XCTAssertTrue(askon.waitForExistence(timeout: 5))
        let kaplansgarden = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kaplansgården")).firstMatch
        XCTAssertFalse(kaplansgarden.exists, "Bara området med platsen ska finnas kvar")

        // Inga träffar: en tydlig text, och Hitta område står kvar.
        search.clearAndTypeText("zzz")
        XCTAssertTrue(app.staticTexts["Inga områden matchar ”zzz”."].waitForExistence(timeout: 5))
        XCTAssertFalse(askon.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Vet du inte vilket område?")).firstMatch.exists)

        // Tomt fält ger alla områden igen.
        search.clearAndTypeText("")
        XCTAssertTrue(askon.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Du väljer området själv"].waitForExistence(timeout: 5), "Varningen ska komma tillbaka")
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

    func testSchematSomSnartSlutarVisarRutanOchRadenPaHem() {
        // Avestas schema gäller bara 10 dagar till.
        app.terminate()
        app.launchArguments += ["-uitest-schemat-slutar"]
        app.launch()
        open("Gata och husnummer")
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("okänd gata 1, Avesta")
        open("Välj område i Avesta kommun")
        let area = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        area.tap()
        open("Spara området")

        // Hemkortet: en kort rad utan år. Kortet läses som en enhet.
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Schemat slutar "), "Hemkortet ska säga att schemat slutar")
        card.tap()

        // Adressvyn: orsaken står en gång, under raden "Schemat gäller till", och rutan säger att nya tider visas när källan
        // publicerar dem.
        XCTAssertTrue(app.staticTexts["Kommande"].waitForExistence(timeout: 5))
        let box = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Schemat tar snart slut")).firstMatch
        for _ in 0..<4 where !box.exists { app.swipeUp() }
        XCTAssertTrue(box.waitForExistence(timeout: 5), "Rutan ska synas när schemat slutar inom 14 dagar")
        XCTAssertFalse(box.label.contains("Avesta Vatten publicerar"), "Orsaken ska inte upprepas i rutan")
        let reason = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Avesta Vatten publicerar hämtschemat ett år i taget.")).firstMatch
        XCTAssertTrue(reason.exists, "Orsaken ska stå under raden Schemat gäller till")
        XCTAssertTrue(box.label.contains("Nya tider visas när källan publicerar dem."))
        XCTAssertFalse(box.label.localizedCaseInsensitiveContains("påminnelse"), "Inget löfte om påminnelser")
    }

    func testGatorMedAnnanHamtdagVisasOverst() {
        open("Gata och husnummer")
        let field = app.textFields["Gata och husnummer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("okänd gata 1, Avesta")
        open("Välj område i Avesta kommun")
        let area = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        area.tap()
        open("Spara området")
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Askön")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()

        // Adressvyn: rubriken som rubrik och raden ordagrant, ovanför Kommande.
        let kommande = app.staticTexts["Kommande"]
        XCTAssertTrue(kommande.waitForExistence(timeout: 5))
        let heading = app.staticTexts["Vissa gator har en annan hämtdag"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "Rubriken ska synas i adressvyn")
        XCTAssertTrue(app.otherElements["otherDaysCard"].exists)
        XCTAssertTrue(app.staticTexts["Till exempel Stallgatan och Storbogatan (måndag, udda vecka) och Bodgatan (onsdag, jämn vecka)."].exists)
        XCTAssertLessThan(heading.frame.minY, kommande.frame.minY, "Rutan ska stå före Kommande")

        // Hela schemat visar samma ruta.
        for _ in 0..<2 where !app.buttons["Hela schemat"].exists { app.swipeUp() }
        app.buttons["Hela schemat"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Vissa gator har en annan hämtdag"].waitForExistence(timeout: 5), "Hela schemat ska visa rubriken")
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

private extension XCUIElement {
    /// Tömmer fältet och skriver ny text. En tom text lämnar fältet tomt.
    func clearAndTypeText(_ text: String) {
        guard let current = value as? String, !current.isEmpty else { if !text.isEmpty { typeText(text) }; return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        if !text.isEmpty { typeText(text) }
    }
}
