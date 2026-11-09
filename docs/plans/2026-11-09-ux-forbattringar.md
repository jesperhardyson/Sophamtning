# UX-förbättringar efter granskningen: plan

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans, en PR i taget. Stegen har kryssrutor (`- [ ]`).

**Mål:** Rätta fel, förenkla och snygga till appen enligt granskningen 2026-11-09, med en PR per förbättring.

**Upplägg:** Varje PR görs på en egen gren från `main` och squash-mergas med titeln som står i dess rubrik. Ändras beteende eller text som specen bestämmer uppdateras specen i samma PR, i en första commit med `docs:`, och Jesper godkänner den innan koden skrivs. Ändras utseendet uppdateras Pencil-designen först, via Pencil MCP. Logik och texter läggs i `SophamtningKit` och testas där. Vyerna i appen förblir tunna.

**Teknik:** Swift 6, SwiftUI, Swift Testing (paketet), XCTest (UI-tester), xcodegen.

**Spec:** `docs/specs/2026-11-06-ios-app.md`

## Gemensamma krav

- Lägsta version är iOS 26. Inga tredjepartsbibliotek.
- All text i appen, alla kommentarer och alla commit-meddelanden är på svenska. Inga AI-attributionsrader.
- PR-titlar följer Conventional Commits: `fix:` för rättning, `feat:` för ny funktion, `docs:` för spec och plan.
- "I dag" och alla tider räknas i `Europe/Stockholm`.
- Fraktioner visas alltid med färg, ikon och text. `estimated: true` visas som "ca" överallt.
- Notiser och Live Activities är avstängda från början. Inget schemaläggs utan användarens val.
- Tekniska fel får aldrig se ut som att en adress eller kommun saknas.
- Varje PR kör `cd iOS/Packages/SophamtningKit && swift test` och bygget. UI-tester körs bara för det som ändras, och hela sviten en gång innan PR:en görs redo.

## Fokus vid granskning

1. **Största textstorleken.** Varje ändrad vy ska fungera med AX5. `LargestTextTests` körs i PR:er som ändrar layout.
2. **Mörkt läge.** Nya färger och tonade texter ska läsas mot `surface` och `bg` i båda lägena. `ThemeTests` täcker nya tokens.
3. **VoiceOver.** Ändrade rader och kort läses fortfarande som en enhet, med alla fraktioner som text. `AccessibilityAuditTests` körs.
4. **Sparad data efter ett fel.** Texter för "inga hämtningar" ska skilja på `afterError` och färskt svar, som i dag.
5. **Avvikelse på nästa tömning.** När Kommande inte längre visar nästa tömning får "Flyttad från …" inte försvinna. Testet `nastaTomningsAvvikelseStarIKortet` i PR 4 täcker det.
6. **Adress utan schema.** Ingen ändring får visa ett tomt kort eller en ensam pil.

## Ordning

| PR | Titel | Spec | Design |
|---|---|---|---|
| 1 | `fix: Pilen står till höger på adresser utan hämtningar` | Nej | Nej |
| 2 | `fix: Huvudkortet hoppar inte när schemat laddas` | Nej | Ja |
| 3 | `fix: Rubriken i fältet går att läsa vid scroll` | Nej | Nej |
| 4 | `fix: Kommande upprepar inte nästa tömning` | Ja | Nej |
| 5 | `feat: Nästa tömning per kärl som lista` | Ja | Ja |
| 6 | `fix: Samma namn på påminnelsen överallt` | Ja | Ja |
| 7 | `fix: Kortare text för Live Activity` | Ja | Ja |
| 8 | `fix: Fraktionernas hela namn under Kommande` | Ja | Nej |
| 9 | `fix: Inga kommande hämtningar visas neutralt` | Nej | Ja |
| 10 | `fix: Tydligare text när en live-källa saknar hämtningar` | Ja | Nej |
| 11 | `fix: Påminnelsen döljs när det inte finns hämtningar` | Ja | Nej |
| 12 | `feat: Huvudkortet säger till på tömningsdagen` | Ja | Ja |
| 13 | `feat: Förslag om påminnelse efter första adressen` | Ja | Ja |
| 14 | `fix: Tydligare färger för papper, tidningar och glas` | Nej | Ja |
| 15 | `fix: Lättare rubriker i adressvyn` | Nej | Ja |
| 16 | `fix: Lugnare länkar i kortet om källan` | Nej | Ja |
| 17–20 | Nya funktioner, se sist | Ja | Ja |

PR 1–3 är fristående och kan göras parallellt. PR 4 och 8 rör samma rader under Kommande och görs i den ordningen. PR 9–11 rör adresser utan hämtningar och görs i nummerordning.

---

## PR 1: Pilen på adresser utan hämtningar

**Gren:** `fix/pil-utan-hamtningar`

**Filer:**
- Ändra: `iOS/Sophamtning/Views/HomeView.swift` (`AddressRow.body`, rad 477–487)
- Test: `iOS/SophamtningUITests/CoreFlowTests.swift`

**Orsak:** `fractions` är tom när adressen saknar hämtningar. `.frame(maxWidth: .infinity)` på en tom vy tar ingen plats, så pilen hamnar till vänster.

- [ ] **Steg 1:** Skriv UI-testet `testPilenStarTillHogerUtanHamtningar`. Lägg till en adress vars stubbe i `UITestAPI` har tomt schema (lägg till `uitest-adress-tom.json` i `UITestData/` och en gren i `address(url:)` för `testgatan-tom`). Kontrollera att pilens `frame.maxX` ligger inom 40 punkter från radens `frame.maxX`. Ge pilen `accessibilityIdentifier("adressrad-pil")`.
- [ ] **Steg 2:** Kör `xcodebuild ... test -only-testing:SophamtningUITests/CoreFlowTests/testPilenStarTillHogerUtanHamtningar`. Väntat: FAIL.
- [ ] **Steg 3:** Lägg pilen till höger oavsett chips: när det inte finns några fraktioner står pilen i en `HStack` med `Spacer(minLength: 0)` före. När chips finns blir det som i dag.
- [ ] **Steg 4:** Kör testet igen, och dessutom `LargestTextTests`. Väntat: PASS.
- [ ] **Steg 5:** Commit `fix: Pilen står till höger på adresser utan hämtningar`.

## PR 2: Huvudkortet hoppar inte när schemat laddas

**Gren:** `fix/huvudkort-laddning`

**Filer:**
- Ändra: `iOS/Sophamtning/Views/PrimaryCard.swift` (läget `.loading`, rad 98–101)
- Ändra: `docs/design/sophamtning-design.pen` (huvudkortet i läget laddar)
- Test: `iOS/SophamtningUITests/CoreFlowTests.swift`

**Beslut:** Huvudkortet laddar med samma layout som det färdiga kortet: kalenderbrickan och raden **Nästa tömning** står som platshållare (`.redacted(reason: .placeholder)`), och ett litet kärl (`BinRoundView`, samma som bredvid rubriken) står i stället för chipsen med texten "Hämtar schema". Det stora kärlet visas bara i adressvyn, som i specen. Höjden ändras då bara med chipsraden, och "Fler adresser" kan inte hamna ovanpå kortet.

- [ ] **Steg 1:** Uppdatera huvudkortets laddningsläge i Pencil.
- [ ] **Steg 2:** Skriv UI-testet `testHuvudkortetBehallerHojdenNarSchematKommer`. Starta med `-uitest` och en fördröjning i stubben (`UITestSupport.slowAddress`, nytt argument `-uitest-langsam`, 1 sekund). Spara kortets höjd under laddning och efter. Väntat: skillnaden är under 60 punkter, och rubriken "Fler adresser" ligger under kortets `maxY` i båda lägena.
- [ ] **Steg 3:** Kör testet. Väntat: FAIL.
- [ ] **Steg 4:** Bygg laddningsläget enligt beslutet. VoiceOver läser "Hämtar schema", som i dag.
- [ ] **Steg 5:** Kör testet, `AccessibilityAuditTests` och `LargestTextTests`. Väntat: PASS.
- [ ] **Steg 6:** Specen ändras inte (den säger redan att kärlet laddar när inget sparat schema finns, men inte var). Commit `fix: Huvudkortet hoppar inte när schemat laddas`.

## PR 3: Rubriken i fältet går att läsa vid scroll

**Gren:** `fix/rubrik-vid-scroll`

**Filer:**
- Ändra: `iOS/Sophamtning/Views/HomeView.swift` (`screen(_:)`)
- Ändra: `iOS/Sophamtning/Views/AddressView.swift` (`content(for:)`) och vyn för Hela schemat i `ScheduleViews.swift`

**Beslut:** Sätt `.scrollEdgeEffectStyle(.hard, for: .top)` på de tre `ScrollView`. Fältet får då en tydlig kant mot innehållet i stället för en mjuk toning, och den vita rubriken hamnar inte ovanpå det gröna kortet. Om den hårda kanten ser fel ut mot designen provas i stället att behålla den mjuka och lägga `Color.Theme.bg` bakom fältet med `.toolbarBackground(.visible, for: .navigationBar)`. Välj den som klarar båda kontrollerna i steg 2.

- [ ] **Steg 1:** Ändra enligt beslutet.
- [ ] **Steg 2:** Kontrollera i simulatorn, i ljust och mörkt läge: scrolla hemskärmen tills huvudkortet ligger under fältet, och adressvyn tills Påminnelser ligger under. Rubriken ska kunna läsas, och knapparna i glas ska inte få grön ton. Ta skärmbilder till PR:en.
- [ ] **Steg 3:** Kör `CoreFlowTests/testInstradetMedAdressVisarKortetOchSchemaraderna`. Väntat: PASS.
- [ ] **Steg 4:** Commit `fix: Rubriken i fältet går att läsa vid scroll`.

## PR 4: Kommande upprepar inte nästa tömning

**Gren:** `fix/kommande-efter-nasta`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Adress, punkt 2)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Home/AddressDetail.swift` (`upcoming`, `hasFullSchedule`, rad 112–123)
- Test: `iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/AddressDetailTests.swift`

**Spectext:** "**Kommande:** de tre närmaste datumen efter nästa tömning, ett per rad …". Hela schemat visar som förut alla datum, nästa tömning inräknad. Avvikelsen för nästa tömning ("Flyttad från sön 8 nov") står i kortet **Nästa tömning**, under datumet, eftersom raden där den stod i dag försvinner.

- [ ] **Steg 1:** Commit `docs: Kommande börjar efter nästa tömning` med spectexten. Vänta på Jespers godkännande.
- [ ] **Steg 2:** Skriv testet `kommandeBorjarEfterNastaTomning`: ett schema med hämtningar 9, 11, 12 och 16 nov och i dag 9 nov ger `upcoming.map(\.date) == [11 nov, 12 nov, 16 nov]`. Skriv också `helaSchematVisasNarFlerAnKommandeFinns`: med fem datum är `hasFullSchedule == true`, med fyra (nästa och tre till) `false`. Skriv `nastaTomningsAvvikelseStarIKortet`: med schemat i testet på rad 245 är `nextDeviation == "Flyttad från sön 8 nov"`.
- [ ] **Steg 3:** Kör `swift test --filter AddressDetailTests`. Väntat: FAIL.
- [ ] **Steg 4:** `upcoming` hoppar över raden vars datum är `next?.date`. Hanteringen av varningen (`withoutWarning`) behövs då inte längre och tas bort. `hasFullSchedule` blir `rows.count > Self.upcomingCount + (next == nil ? 0 : 1)`. Lägg till `public var nextDeviation: String?` (avvikelsen på raden med `next?.date`) och visa den under datumet i kortet i `AddressView.swift`, i samma stil som avvikelsen på raderna. Kortets etikett för VoiceOver får den sist.
- [ ] **Steg 5:** Skriv om testet på rad 245–255 ("varningen står inte en gång till"), som inte längre gäller, så att det kontrollerar att `upcoming` bara har raden 12 nov med varningen "Ställ ut tidigt", och att `nextWarning == "Helgdag"`.
- [ ] **Steg 6:** Kör `swift test`, och `CoreFlowTests/testInstradetMedAdressVisarKortetOchSchemaraderna`. Väntat: PASS.
- [ ] **Steg 7:** Commit `fix: Kommande upprepar inte nästa tömning`.

## PR 5: Nästa tömning per kärl som lista

**Gren:** `feature/karlen-som-lista`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Adress, punkt 3)
- Ändra: `docs/design/sophamtning-design.pen` (adressvyn)
- Ändra: `iOS/Sophamtning/Views/AddressView.swift` (`bins(_:)`, rad 241–260)
- Ändra: `iOS/Sophamtning/Views/ScheduleViews.swift` (ersätt `BinCard` med `BinRow`, ta bort `BinCardMetrics`)
- Ta bort: `iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/BinCardWidthTests.swift` och det den testar
- Test: `iOS/SophamtningUITests/CoreFlowTests.swift`

**Beslut:** Delen heter **Per kärl** och är en lista i ett kort, som Kommande, med en rad per fraktion: chipset med hela namnet till vänster, "Mån 16 nov" och "om 7 dagar" till höger. Ingen scroll i sidled. Den behålls eftersom den svarar på något som Kommande inte gör: när ett kärl som töms sällan (glas, metall) töms nästa gång. `AddressDetail.Bin` ändras inte.

**Spectext:** "3. **Per kärl:** nästa tömning per fraktion, en rad per kärl i ett kort."

- [ ] **Steg 1:** Commit `docs: Nästa tömning per kärl som lista` med spectexten. Vänta på godkännande. Uppdatera Pencil.
- [ ] **Steg 2:** Skriv UI-testet `testPerKarlVisarEnRadPerFraktion`: med stubbens adress finns rubriken "Per kärl", och varje fraktion i stubben har en rad vars etikett börjar med fraktionens namn.
- [ ] **Steg 3:** Kör testet. Väntat: FAIL.
- [ ] **Steg 4:** Bygg `BinRow(bin: AddressDetail.Bin)` i `ScheduleViews.swift` och använd den i `bins(_:)`. Raden läses med `bin.accessibilityLabel`. Radernas inträde (`rowEntrance`) behålls.
- [ ] **Steg 5:** Kör testet, `swift test`, `LargestTextTests` och `AccessibilityAuditTests`. Väntat: PASS.
- [ ] **Steg 6:** Commit `feat: Nästa tömning per kärl som lista`.

## PR 6: Samma namn på påminnelsen överallt

**Gren:** `fix/paminnelsens-namn`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Hem, Adress punkt 4, snabbmenyn i Omfattning)
- Ändra: `iOS/Sophamtning/Views/AddressView.swift:292`
- Ändra: `iOS/Sophamtning/Views/AddressQuickActions.swift:110`
- Ändra: kommentarerna i `AddressDetail.swift:137` och `HomeContent.swift:58`
- Test: `iOS/SophamtningUITests/QuickActionsTests.swift`, `CoreFlowTests.swift`

**Beslut:** Valet heter **Påminn mig kvällen före** på huvudkortet, i adressvyn och i snabbmenyn. Live Activity behåller sitt namn. Rubriken Påminnelser i adressvyn står kvar.

- [ ] **Steg 1:** Commit `docs: Samma namn på påminnelsen överallt`. Vänta på godkännande.
- [ ] **Steg 2:** Uppdatera UI-testerna som letar efter "Notis kvällen före" (`grep -rn "Notis kvällen före" iOS/SophamtningUITests`) så att de letar efter "Påminn mig kvällen före". Kör dem. Väntat: FAIL.
- [ ] **Steg 3:** Byt texten i de två vyerna.
- [ ] **Steg 4:** Kör `QuickActionsTests`, `CoreFlowTests/testPaminnelserArAvstangdaFranBorjan` och `swift test`. Väntat: PASS.
- [ ] **Steg 5:** Commit `fix: Samma namn på påminnelsen överallt`.

## PR 7: Kortare text för Live Activity

**Gren:** `fix/live-activity-text`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Live Activity och Samspel)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Home/AddressDetail.swift` (`liveActivityText`, rad 258–261, och ny `liveActivityDetails`)
- Ändra: `iOS/Sophamtning/Views/ReminderToggleRow.swift` (`LiveActivityToggleRow`)
- Test: `AddressDetailTests.swift`

**Beslut:** Raden visar en mening: `"Visas på låsskärmen från kl. \(time) kvällen före."`. En ⓘ-knapp till höger om rubriken öppnar en popover (`.popover` med `.presentationCompactAdaptation(.popover)`) med resten, en mening per rad:

- "Starten aviseras med ljud."
- "Den försvinner senast efter 12 timmar."
- "Öppna appen ibland, så att nästa tömning kommer med."
- "Med notiser på får du en reserv om du inte bekräftar."

`public static func liveActivityDetails() -> [String]` returnerar de fyra raderna. Knappen heter "Mer om Live Activity" för VoiceOver.

- [ ] **Steg 1:** Commit `docs: Kortare text för Live Activity`. Vänta på godkännande. Uppdatera Pencil.
- [ ] **Steg 2:** Skriv testet `liveActivityTextenArEnMening`: med `reminderMinutes: 1080` är texten exakt `"Visas på låsskärmen från kl. 18:00 kvällen före."`, och `liveActivityDetails()` är de fyra raderna ovan.
- [ ] **Steg 3:** Kör `swift test --filter AddressDetailTests`. Väntat: FAIL.
- [ ] **Steg 4:** Ändra texten, lägg till `liveActivityDetails()` och knappen med popovern.
- [ ] **Steg 5:** Kör `swift test`, `AccessibilityAuditTests` och `LargestTextTests`. Väntat: PASS.
- [ ] **Steg 6:** Commit `fix: Kortare text för Live Activity`.

## PR 8: Fraktionernas hela namn under Kommande

**Gren:** `fix/hela-fraktionsnamn`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Adress, punkt 2)
- Ändra: `iOS/Sophamtning/Views/ScheduleViews.swift:80` och `iOS/Sophamtning/Views/HomeView.swift:545`

**Beslut:** Chipsen i appen visar alltid fraktionens hela namn (`name`) och bryts till nästa rad när de inte får plats. Källans korta namn (`short`) används bara i widgeten och Live Activityn, där platsen inte räcker. "Tidn." och "Papper" för pappersförpackningar försvinner då ur appen.

- [ ] **Steg 1:** Commit `docs: Fraktionernas hela namn i appen`. Vänta på godkännande.
- [ ] **Steg 2:** Ta bort `short: true` på båda ställena.
- [ ] **Steg 3:** Kör `LargestTextTests` och `CoreFlowTests/testInstradetMedAdressVisarKortetOchSchemaraderna`, och kontrollera i simulatorn att en rad med tre långa namn bryts utan att dagar kvar kapas. Väntat: PASS.
- [ ] **Steg 4:** Commit `fix: Fraktionernas hela namn under Kommande`.

## PR 9: Inga kommande hämtningar visas neutralt

**Gren:** `fix/neutral-inga-hamtningar`

**Filer:**
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Home/HomeContent.swift` (`Entry`)
- Ändra: `iOS/Sophamtning/Views/HomeView.swift` (`AddressRow.details`, rad 506–508)
- Test: `HomeContentTests.swift`

**Beslut:** `Entry` får `public var summaryTone: SummaryTone` med fallen `.date`, `.neutral` och `.warning`. `.noUpcoming` och `.loading` ger `.neutral` (färgen `text2`, vikten `.bold`). Misslyckad hämtning ger `.warning`, som i dag. Kommande hämtning ger `.date` (`brandText`, `.heavy`).

- [ ] **Steg 1:** Skriv testet `ingaKommandeHamtningarArNeutral`: en adress utan hämtningar ger `summaryTone == .neutral`, en med hämtning `.date`, och en vars hämtning misslyckats utan sparat schema `.warning`.
- [ ] **Steg 2:** Kör `swift test --filter HomeContentTests`. Väntat: FAIL.
- [ ] **Steg 3:** Lägg till `SummaryTone` och använd den i `AddressRow`. `isFailure` i vyn ersätts av tonen.
- [ ] **Steg 4:** Kör `swift test`. Kontrollera i simulatorn i ljust och mörkt läge. Väntat: PASS.
- [ ] **Steg 5:** Commit `fix: Inga kommande hämtningar visas neutralt`.

## PR 10: Tydligare text när en live-källa saknar hämtningar

**Gren:** `fix/live-kalla-utan-hamtningar`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Fel och tomma lägen, raden om tom `next`)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Home/AddressDetail.swift` (`noUpcomingMessage`, rad 221–230)
- Test: `AddressDetailTests.swift` (rad 327 och nytt test)

**Beslut:** Utan `schedule` (live-källa) och utan fel blir meddelandet: `"Källan visar inga hämtningar för adressen just nu. Stämmer det inte, kontakta \(sourceName)."`, och utan känt källnamn `"… kontakta den som ansvarar för hämtningen."`. Kortet om källan står längre ned på samma sida. `noUpcomingMessage` får parametern `sourceName: String?`. Texten efter fel och alla texter med period ändras inte.

- [ ] **Steg 1:** Commit `docs: Tydligare text när en live-källa saknar hämtningar`. Vänta på godkännande.
- [ ] **Steg 2:** Ändra testet på rad 327 så att det väntar sig den nya texten med "Stockholm Vatten och Avfall", och skriv `liveKallaUtanNamnHanvisarTillAnsvarig` för fallet utan namn.
- [ ] **Steg 3:** Kör `swift test --filter AddressDetailTests`. Väntat: FAIL.
- [ ] **Steg 4:** Ändra funktionen och skicka med `sourceName` från `AddressDetail.make`.
- [ ] **Steg 5:** Kör `swift test`. Väntat: PASS.
- [ ] **Steg 6:** Commit `fix: Tydligare text när en live-källa saknar hämtningar`.

## PR 11: Påminnelsen döljs när det inte finns hämtningar

**Gren:** `fix/paminnelse-utan-hamtningar`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Adress punkt 4, Fel och tomma lägen)
- Ändra: `iOS/Sophamtning/Views/AddressView.swift` (rad 103–105)
- Test: `CoreFlowTests.swift`

**Beslut:** I läget `.noUpcoming` visas Påminnelser bara om en påminnelse redan är på för adressen (eller Live Activity för huvudadressen), så att den går att stänga av. Annars döljs delen. Är den på visas under reglaget: "Inga hämtningar att påminna om just nu."

- [ ] **Steg 1:** Commit `docs: Påminnelsen döljs utan hämtningar`. Vänta på godkännande.
- [ ] **Steg 2:** Skriv UI-testet `testPaminnelserDoljsUtanHamtningar` med stubbadressen utan schema från PR 1: rubriken "Påminnelser" finns inte.
- [ ] **Steg 3:** Kör det. Väntat: FAIL.
- [ ] **Steg 4:** Ändra villkoret och lägg till raden.
- [ ] **Steg 5:** Kör testet och `testPaminnelserArAvstangdaFranBorjan`. Väntat: PASS.
- [ ] **Steg 6:** Commit `fix: Påminnelsen döljs när det inte finns hämtningar`.

## PR 12: Huvudkortet säger till på tömningsdagen

**Gren:** `feature/tomningsdagen`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Hem)
- Ändra: `docs/design/sophamtning-design.pen` (huvudkortet med tömning i dag)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Home/HomeContent.swift` (`Pickup` eller `Entry`)
- Ändra: `iOS/Sophamtning/Views/PrimaryCard.swift`
- Test: `HomeContentTests.swift`

**Beslut:** När nästa tömning är i dag står en rad under datumet på huvudkortet: "Kärlen ska stå ute i dag." Reglaget för påminnelsen står kvar, eftersom det gäller kommande tömningar. Står reglaget på visar det redan nästa påminnelse ("Tisdag kl. 18:00"). Ingen knapp **Utställt** på kortet: den finns i Live Activityn, och en till på kortet skulle ge två sätt att markera samma sak.

`Entry` får `public let dayNote: String?`, som är texten ovan när `pickup.date == today` och annars `nil`. Är datumet beräknat (`estimated`) blir texten "Kärlen ska stå ute i dag, om tömningen kommer som beräknat."

- [ ] **Steg 1:** Commit `docs: Huvudkortet säger till på tömningsdagen`. Vänta på godkännande. Uppdatera Pencil.
- [ ] **Steg 2:** Skriv testerna `tomningIDagGerRad`, `tomningIMorgonGerIngenRad` och `beraknadTomningIDagSagerCa` med fast klocka 9 nov 07:00 i Stockholm.
- [ ] **Steg 3:** Kör `swift test --filter HomeContentTests`. Väntat: FAIL.
- [ ] **Steg 4:** Räkna fram `dayNote` och visa den i `PrimaryCard`. Den läses med kortets etikett.
- [ ] **Steg 5:** Kör `swift test`, `AccessibilityAuditTests` och `LargestTextTests`. Väntat: PASS.
- [ ] **Steg 6:** Commit `feat: Huvudkortet säger till på tömningsdagen`.

## PR 13: Förslag om påminnelse efter första adressen

**Gren:** `feature/forslag-paminnelse`

**Filer:**
- Ändra: `docs/specs/2026-11-06-ios-app.md` (Hem, Notiser)
- Ändra: `docs/design/sophamtning-design.pen` (kortet på hemskärmen)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Storage/StoredModels.swift` (`ReminderSettings`)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/App/AppModel.swift`
- Ändra: `iOS/Sophamtning/Views/HomeView.swift`
- Test: `AppModelRemindersTests.swift`, `LocalStoreTests.swift`, `CoreFlowTests.swift`

**Beslut:** Efter att den första adressen har sparats visas ett kort överst på hemskärmen, ovanför huvudkortet: rubriken "Vill du bli påmind?", texten "Få en notis kvällen före varje tömning. Du kan ändra det när som helst.", och knapparna **Påminn mig** (slår på notisen för huvudadressen, med samma flöde som reglaget) och **Inte nu**. Kortet visas en gång. Båda knapparna och reglaget på huvudkortet gör att det inte visas igen. Inget schemaläggs förrän användaren trycker **Påminn mig**, så regeln om opt-in gäller.

`ReminderSettings` får `public var reminderOfferShown: Bool = false`. Avkodningen tål sparade inställningar utan fältet (`decodeIfPresent`, standard `false`). `AppModel` får `public var showsReminderOffer: Bool` (en adress, ingen påminnelse på, `reminderOfferShown == false`) och `public func dismissReminderOffer()`.

- [ ] **Steg 1:** Commit `docs: Förslag om påminnelse efter första adressen`. Vänta på godkännande. Uppdatera Pencil.
- [ ] **Steg 2:** Skriv testerna `forslagetVisasEfterForstaAdressen`, `forslagetVisasInteNarPaminnelsenArPa`, `forslagetVisasInteEfterInteNu` och `installningarUtanFaltetAvkodasSomEjVisat`.
- [ ] **Steg 3:** Kör `swift test`. Väntat: FAIL.
- [ ] **Steg 4:** Lägg till fältet, egenskapen och funktionen. Bygg kortet i `HomeView` med `MessageCard`-stilen och två knappar.
- [ ] **Steg 5:** Skriv UI-testet `testForslagOmPaminnelseVisasEnGang`: lägg till testgatan, kortet syns, tryck **Inte nu**, starta om appen, kortet syns inte.
- [ ] **Steg 6:** Kör `swift test`, det nya UI-testet och `testPaminnelserArAvstangdaFranBorjan`. Väntat: PASS.
- [ ] **Steg 7:** Commit `feat: Förslag om påminnelse efter första adressen`.

## PR 14: Tydligare färger för papper, tidningar och glas

**Gren:** `fix/fraktionsfarger`

**Filer:**
- Ändra: `docs/design/sophamtning-design.pen` (fraktionsfärger)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningDesign/Theme.swift` (nya `fracTidningar`, `fracTidningarBg`)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningDesign/FractionViews.swift:27`
- Test: `ThemeTests.swift`

**Beslut:** Tidningar får en egen färg i gult/ockra, så att den skiljer sig från papper (blå) och glas (turkos). Glas flyttas mot grönt om kontrasten mot papper fortfarande är för låg. De exakta värdena bestäms i Pencil och kopieras därifrån. Webben (Sopor) har samma färger, så ändringen bör göras där också. Det är en egen fråga i Sopor-repot.

- [ ] **Steg 1:** Ta fram färgerna i Pencil, ljust och mörkt läge. Kontrasten mellan förgrund och bakgrund ska vara minst 4,5:1 i båda lägena.
- [ ] **Steg 2:** Skriv testet `tidningarHarEgenFarg` (`FractionStyle(id: "tidningar", …).foreground != FractionStyle(id: "papper", …).foreground`) och lägg till de nya tokens i det befintliga kontrasttestet i `ThemeTests`.
- [ ] **Steg 3:** Kör `swift test --filter ThemeTests`. Väntat: FAIL.
- [ ] **Steg 4:** Lägg till tokens och ändra `themed["tidningar"]`.
- [ ] **Steg 5:** Kör `swift test`. Väntat: PASS.
- [ ] **Steg 6:** Commit `fix: Tydligare färger för papper, tidningar och glas`.

## PR 15: Lättare rubriker i adressvyn

**Gren:** `fix/lattare-rubriker`

**Filer:**
- Ändra: `docs/design/sophamtning-design.pen` (adressvyn och hemskärmen)
- Ändra: `iOS/Sophamtning/Views/AddressView.swift` (`sectionTitle`, rad 319–325) och "Fler adresser" i `HomeView.swift`

**Beslut:** Avsnittsrubrikerna (Kommande, Per kärl, Påminnelser, Fler adresser) får `.ui(20, weight: .bold, relativeTo: .title3)` och färgen `text2`. **Nästa tömning**, datumen och adressens namn behåller sin tyngd. Värdena stäms av mot Pencil innan koden ändras.

- [ ] **Steg 1:** Ändra i Pencil och få Jespers godkännande av skärmbilden.
- [ ] **Steg 2:** Ändra `sectionTitle` och rubriken på hemskärmen.
- [ ] **Steg 3:** Kör `LargestTextTests` och `AccessibilityAuditTests`. Rubrikerna har fortfarande `.isHeader`. Väntat: PASS.
- [ ] **Steg 4:** Commit `fix: Lättare rubriker i adressvyn`.

## PR 16: Lugnare länkar i kortet om källan

**Gren:** `fix/kallkortets-lankar`

**Filer:**
- Ändra: `docs/design/sophamtning-design.pen` (kortet Ansvarar för hämtningen)
- Ändra: `iOS/Sophamtning/Views/SourceCard.swift`

**Beslut:** Raderna ser ut som en iOS-lista: ikonen i accentfärg, texten i `text` och vikten `.regular`, och en pil (`chevron.right`, eller `arrow.up.right` för länkar som öppnas i webbvyn) till höger i `text2`. Telefonnumret behåller accentfärgen, eftersom det är det man oftast vill göra.

- [ ] **Steg 1:** Ändra i Pencil.
- [ ] **Steg 2:** Ändra raderna i `SourceCard`.
- [ ] **Steg 3:** Kör `AccessibilityAuditTests` och kontrollera i simulatorn att varje rad fortfarande är en knapp med samma etikett. Väntat: PASS.
- [ ] **Steg 4:** Commit `fix: Lugnare länkar i kortet om källan`.

---

## PR 17–20: Nya funktioner

De här är större än en uppgift och rör delar som specen uttryckligen har utanför första versionen. Var och en börjar med en PR som bara ändrar specen (`docs:`), och när Jesper godkänt den skrivs en egen plan i `docs/plans/` med samma upplägg som ovan. Planerna skrivs först när specen är godkänd, eftersom svaren på frågorna nedan styr dem.

### PR 17: `feat: Påminnelse på morgonen`

- **Spec:** Ta bort "Påminnelser på andra tider än kvällen före" från **Inte med**. Lägg till valet "Kvällen före" eller "Samma morgon" i Inställningar, med tiden 05:00–10:00 i steg om 15 minuter för morgonen.
- **Frågor till specen:** Gäller valet alla adresser, som tiden i dag? Ska Live Activity följa med till morgonen, eller bara gälla kvällen före? Hur ändras reservnotisen?
- **Berör:** `ReminderSettings`, `ReminderPlanner`, `AddressDetail` (texterna "inför onsdagens tömning"), `SettingsView`, `ReminderPlannerTests`.

### PR 18: `feat: Widgetar på låsskärmen`

- **Spec:** Ta bort "Widgets på låsskärmen" från **Inte med**. Lägg till `accessoryRectangular` (veckodag, datum och upp till tre fraktionsikoner) och `accessoryInline` ("Tors: Rest, Mat").
- **Frågor till specen:** Visas "ca" i den raka raden? Vad visas utan huvudadress?
- **Berör:** `NextPickupWidget.swift` (`supportedFamilies`), `WidgetContent` och `WidgetContentTests`.

### PR 19: `feat: Fråga Siri när soporna töms`

- **Spec:** Ett `AppIntent` "När töms soporna?" som svarar med huvudadressens nästa tömning, och ett `AppShortcutsProvider` med svenska fraser.
- **Frågor till specen:** Bara huvudadressen, eller en parameter för adressen? Vad svarar Siri när schemat är gammalt?
- **Berör:** nytt mål eller ny fil i appen, `WidgetContent` för texten.

### PR 20: `feat: Lägg till schemat i kalendern`

- **Spec:** En knapp i Hela schemat som exporterar kommande hämtningar som `.ics` via delningsbladet, med en händelse per datum över hela dagen och fraktionerna i rubriken.
- **Frågor till specen:** En ögonblicksbild eller en prenumeration? En prenumeration kräver en adress för `.ics` i Sopor API, och API:t har den inte i dag.
- **Berör:** ny `CalendarExport` i `SophamtningKit` med tester, `ScheduleViews.swift`.
