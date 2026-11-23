# Android 6: Widgetar, snabbinställningar, genvägar och kalenderbladet

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** Sophämtning syns utanför appen:
- widgetar på hemskärmen i storlekarna liten och mellan, med **Ställ ut kärlen**,
- en ruta i snabbinställningarna, **Ställ ut kärlen**,
- genvägar på appikonen.

Dessutom får kalenderbrickan bläddringen från iOS, ett blad per dag fram till tömningen.

**Arkitektur:**
- Widgetarna ritas med Jetpack Glance och visar `WidgetContent` från `core` (plan 3b). De läser bara från `LocalStore` och gör inga nätanrop, som på iOS.
- Ställ ut i widgeten och i rutan anropar samma kod som **Klart** i Live Update, alltså `PlacedOutAction` via `AppModel`.
- Widgetar och ruta uppdateras när schemat, Utställt eller huvudadressen ändras, och vid midnatt i Stockholm.
- Bläddringens tidslinje skrivs om till `core` med testerna, och ritas i Compose.

**Teknik:** Jetpack Glance 1.2 (`glance-appwidget`, `glance-material3`, `glance-appwidget-testing`), `TileService`, `ShortcutManagerCompat` och Compose-animation.

**Spec:** `docs/specs/2026-11-23-android-app.md`, avsnittet Widgetar och snabbinställningar, och genvägarna i tabellen Med i första versionen. Facit för utseende och texter är iOS-målet `iOS/SophamtningWidgets/` (`NextPickupWidget.swift` och `PlaceOutControl.swift`), `WidgetContent.swift`, och för bläddringen `SophamtningDesign/CalendarFlipTimeline.swift`, `CalendarTile.swift` och iOS-specen `2026-11-06-ios-app.md`, avsnitten Widget och Animationer.

## Gemensamma krav

- Samma krav som i plan 4a, 4b och 5.
- **Inga nätanrop** från widgeten eller rutan. Saknas schemat visas samma läge som på iOS.
- **Widgetens färger** följer appens tema i ljust och mörkt läge, inte bakgrundsbildens dynamiska färger. Fraktionerna har alltid färg, ikon och text.
- **Reducera rörelse:** med "Ta bort animationer" påslaget ger bläddringen bara en toning.

## Granskningsfokus

1. **Dagen byts vid midnatt** med widgeten på hemskärmen. Förväntat: "i morgon" blir "i dag" utan att appen öppnas, räknat i Stockholm.
2. **Ställ ut i widgeten eller rutan med appen dödad.** Förväntat: bocken sparas med tid, notiserna för tömningen tas bort, Live Update avslutas, och widgeten, rutan och appen visar Utställt.
3. **Ingen huvudadress, lagringsfel eller ett schema som saknas.** Förväntat: samma lägen som `WidgetContent` på iOS, och aldrig ett tekniskt fel som ser ut som att adressen saknas.
4. **Största textstorleken och en smal widget.** Förväntat: inget klipps, och kärl som inte får plats blir "+2 till", som på iOS.
5. **Snabb bläddring med många dagar kvar** (till exempel 40). Förväntat: högst 8 blad, klart inom cirka 0,6 s, och brickan läses aldrig upp med mellanliggande datum.

---

### Uppgift 0: Kärlet bredvid rubriken efter den första adressen

Jesper såg att kärlet bredvid "Sophämtning" saknades direkt efter att den första adressen sparats, och att det kom tillbaka senare. Kärlet ritas bara när `ScreenScaffold` tror att den stora rubriken visas, och det avgörs med `LocalTextStyle.current.fontSize != largeStyle.fontSize` (`ui/components/Screens.kt`). Det är skört vid bytet från tomt läge (`large = false`) till fyllt läge.

**Filer:** `app/.../ui/components/Screens.kt` och `ui/home/HomeScreen.kt`. Test: `HomeScreenTest`.

- [ ] **Steg 1: Skriv testet** `karletSynsDirektEfterForstaAdressen`: börja i tomt läge, spara den första adressen, och kontrollera att kärlet bredvid rubriken finns (en nod med testtagg eller beskrivning) direkt och efter att skärmen ritats klart. Se det fallera. Fallerar det inte, återskapa felet i emulatorn med en ny installation, och skriv vad som skiljer.
- [ ] **Steg 2: Rätta.** Välj stor eller liten rubrik efter appfältets utfällning (`scrollBehavior.state.collapsedFraction`), eller efter vilken av Materials två rubrikplatser som ritas, och inte efter textstorleken. Byt också scroll-beteende när `large` växlar, så att ett nytt tillstånd inte ärver det gamla.
- [ ] **Steg 3: Kör** `./gradlew :app:testDebugUnitTest :app:lintDebug`. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: kärlet bredvid rubriken syns direkt efter den första adressen på Android`

### Uppgift 1: Kalenderbladets bläddring

**Filer:**
- Skriv om: `SophamtningDesign/CalendarFlipTimeline.swift` till `Android/core/.../bin/CalendarFlipTimeline.kt`, och bläddringen i `CalendarTile.swift` till `app/.../ui/components/CalendarTile.kt`
- Test: `CalendarFlipTests` till `core`, och `app/src/test/.../ui/CalendarFlipTest.kt`

- [ ] **Steg 1: Skriv om testerna**, och skriv testerna för appen:
  - `bladetVandsNarNastaTomningByterDatum`
  - `brickanLasesBaraMedTomningsdagen`
  - `utanAnimationerToningEndast`

  Se dem fallera.
- [ ] **Steg 2: Implementera**, enligt iOS-specen:
  - ett blad per dag, och högst 8 jämnt fördelade blad,
  - ungefär 0,25 s per blad, och allt klart inom ungefär 0,6 s, med inbromsning mot slutet,
  - nästa blad ligger redan under, och bladen viks upp och överlappar varandra,
  - en lätt vibration per blad och en tydligare när sista bladet landar,
  - bläddringen spelas när nästa tömning byter datum och vid varje start av appen. Den spelas på huvudkortet och i adressvyn.
- [ ] **Steg 3: Kör** `cd Android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug`. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: kalenderbladet bläddrar på Android`

### Uppgift 2: Widgetarna

**Filer:**
- Skapa: `app/.../widget/NextPickupWidget.kt` (`GlanceAppWidget` med storlekarna liten och mellan, `SizeMode.Responsive`), `NextPickupWidgetReceiver.kt`, `PlaceOutAction.kt` (`ActionCallback`), `WidgetUpdates.kt`, `res/xml/next_pickup_widget.xml` (med förhandsvisning och beskrivning) och strängar
- Ändra: `AndroidManifest.xml`, `AppModel` eller appens lager, som uppdaterar widgeten när data ändras, och `RescheduleReceiver` och `RefreshWorker`
- Test: `app/src/test/.../widget/NextPickupWidgetTest.kt`, med `glance-appwidget-testing`

- [ ] **Steg 1: Skriv testerna**:
  - `litenVisarDagOchKarl`
  - `mellanVisarEttKarlPerRadOchPlusTill`
  - `utanHuvudadressVisasUppmaning`
  - `utanSchemaVisasInteSomSaknadAdress`
  - `stallUtSparasOchWidgetenVisarUtstallt`
  - `widgetenUppdaterasVidMidnatt` (ett alarm vid midnatt i Stockholm, som läggs in igen efter omstart)

  Se dem fallera.
- [ ] **Steg 2: Implementera.** Texterna kommer från `WidgetContent`. Ett tryck på widgeten utanför knappen öppnar huvudadressen i appen.
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: widgetar på hemskärmen på Android`

### Uppgift 3: Rutan i snabbinställningarna och genvägarna

**Filer:**
- Skapa: `app/.../tile/PlaceOutTileService.kt` och `app/.../shortcuts/AppShortcuts.kt`
- Ändra: `AndroidManifest.xml` (tjänsten med `BIND_QUICK_SETTINGS_TILE`), och `res/xml/shortcuts.xml` för den fasta genvägen **Lägg till adress**
- Test: `app/src/test/.../tile/PlaceOutTileTest.kt` och `shortcuts/AppShortcutsTest.kt`

- [ ] **Steg 1: Skriv testerna**:
  - `rutanArAktivNarKarlenSkaStallasUt`, med undertexten nästa tömning
  - `rutanVisarUtstalltEfterTryck`
  - `rutanArAvstangdUtanTomningSnart`
  - `dynamiskGenvagTillHuvudadressen`, som uppdateras när huvudadressen byts
  - `genvagenLaggTillAdressOppnarSokningen`

  Se dem fallera.
- [ ] **Steg 2: Implementera.** Rutan följer reglerna i iOS `PlaceOutControl.swift` för när den är aktiv. Genvägarna öppnar appen via en `Intent` som navigeringen läser.
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: snabbinställningar och genvägar på Android`

### Uppgift 4: Prova i emulatorn och PR

- [ ] **Steg 1:** Kör hela sviten: `cd Android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` och `TZ=America/New_York ./gradlew :core:test --rerun`.
- [ ] **Steg 2:** I emulatorn med API 37:
  - lägg widgetarna på hemskärmen,
  - lägg rutan i snabbinställningarna,
  - håll inne appikonen för genvägarna,
  - tryck Ställ ut i widgeten med appen dödad,
  - flytta klockan över midnatt,
  - se bläddringen.

  Skriv resultatet i `docs/specs/2026-11-23-android-enhetschecklista.md`, och ställ tillbaka klockan.
- [ ] **Steg 3:** PR med titeln `build: Widgetar, snabbinställningar och genvägar i Android-appen`.
