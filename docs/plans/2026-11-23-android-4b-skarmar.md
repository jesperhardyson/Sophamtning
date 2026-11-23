# Android 4b: Inställningar, Nyheter, kärlet och tillgänglighet

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** Android-appen får resten av skärmarna från iOS, utom påminnelserna (plan 5): inställningarna med datakällor, integritet och Nyheter, Sopors animerade kärl med pratbubblorna, snabbmenyerna på adresserna, och en granskning av tillgänglighet och största text i hela appen. De mindre anmärkningarna från plan 4a rättas också.

**Arkitektur:** samma som i 4a, med en `ViewModel` per skärm som läser `AppModel` och innehållstyperna i `core`, nya nycklar i Navigation 3, och komponenter i `ui/components`. Kärlet ritas i Compose med `Canvas` och animeras med `Animatable` och tidslinjerna från iOS. Tidslinjerna är ren logik och skrivs om till `core`, med testerna.

**Teknik:** Jetpack Compose, Navigation 3, Compose-animation, Robolectric, och Compose UI-testernas kontroller av tillgänglighet (`enableAccessibilityChecks`, Accessibility Test Framework).

**Spec:** `docs/specs/2026-11-23-android-app.md`. Facit för utseende, texter och beteende är iOS-vyerna `SettingsView.swift`, `ChangelogSheet.swift` och `AddressQuickActions.swift`, och `SophamtningDesign/BinLoader/` och `StartIntro/`.

## Gemensamma krav

- Samma krav som i plan 4a, avsnittet Gemensamma krav.
- **Påminnelserna** är dolda så länge `AppState.remindersAvailable` är falsk. Det gäller raderna under Notiser i inställningarna, reglaget Meddelanden från källan, och Påminn mig och Live Update i snabbmenyn. Koden finns, så att plan 5 bara behöver slå på flaggan.
- **Reducera rörelse:** när "Ta bort animationer" är på i Android (`Settings.Global.ANIMATOR_DURATION_SCALE == 0`) gör kärlet som på iOS med Reducera rörelse: det spelar inget varv, och pratbubblan tonas bara in och ut.

## Granskningsfokus

1. **Någon trycker snabbt och många gånger på kärlet.** Förväntat: varje tryck tas emot, högst tre bubblor syns, och två tryck i rad ger aldrig samma text (`BinBubbleTests`, `BinBubbleStackTests`).
2. **Animationer avstängda i systemet.** Förväntat: inget varv, bara toning.
3. **Nyheter utan Android-changelog.** Android har ingen `CHANGELOG.md` förrän den första releasen. Förväntat: arket visar en vänlig tom text och kraschar inte.
4. **TalkBack och största text i alla skärmar.** Förväntat: kontrollerna av tillgänglighet ger inga fel, och inget klipps vid 200 %.
5. **Långt tryck på en adress, och val i menyn som tar bort eller byter huvudadress.** Förväntat: samma val och samma följd som i adressvyns meny, och samma bekräftelse för Ta bort.

---

### Uppgift 1: Kärlets tidslinjer i kärnan

**Filer:**
- Skriv om: `SophamtningDesign/BinLoader/BinLoaderTimeline.swift`, `BinBubbleTimeline.swift`, `BinBubbleStack.swift` (logiken), `BinLoaderTexts.swift` och `StartIntro/EntranceTimeline.swift`. Det är bara den rena logiken, utan SwiftUI.
- Till: `Android/core/src/main/kotlin/se/hardyson/sophamtning/core/bin/`
- Test: `BinLoaderTests`, `BinBubbleTests`, `BinBubbleStackTests`, `BinRoundWidthTests` och `MotionTests` (den del som är logik)

- [ ] **Steg 1: Skriv om testerna** och se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör** `cd Android && ./gradlew :core:test`. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: kärlets tidslinjer i Android-kärnan`

### Uppgift 2: Kärlet och pratbubblorna

**Filer:**
- Skriv om: `BinArtwork.swift`, `BinLoaderView.swift`, `BinRoundView.swift` och `BinSpeechBubble.swift`
- Till: `app/.../ui/bin/`. Kärlet används som laddningsvy, bredvid rubriken på hemskärmen och i tomt läge, som på iOS.
- Test: `app/src/test/.../ui/BinTest.kt`

- [ ] **Steg 1: Skriv testerna**:
  - `trycketVisarEnBubbla`
  - `fyraSnabbaTryckVisarHogstTreBubblor`
  - `kartaOchBubblaArDoldaForTalkBackMenTextenLases` (live region med låg prioritet)
  - `utanAnimationerSpelasIngetVarv`

  Se dem fallera.
- [ ] **Steg 2: Implementera.** Formen och färgerna följer `BinArtwork.swift` exakt, i samma koordinater omräknade till `Canvas`.
- [ ] **Steg 3: Kör** `./gradlew :app:testDebugUnitTest :app:lintDebug`. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: Sopors kärl med pratbubblor på Android`

### Uppgift 3: Inställningarna, datakällorna och Nyheter

**Filer:**
- Skriv om: `SettingsView.swift` och `ChangelogSheet.swift`, utom påminnelserna, som är dolda
- Till: `app/.../ui/settings/`, med nycklarna `Settings`, `DataSources` och `Changelog`. Inställningarna nås från en ikon i hemskärmens appfält, som på iOS.
- Ändra: `app/build.gradle.kts`, så att `Android/CHANGELOG.md` följer med som tillgång (asset) när filen finns
- Test: `app/src/test/.../ui/SettingsScreenTest.kt`

- [ ] **Steg 1: Skriv testerna**:
  - `installningarnaVisarHuvudadressInofficiellIntegritetOchVersion`
  - `datakallornaVisarKallorUtanTestdata` (med `FakeSoporApi` och `uitest-kallor.json`)
  - `versionOppnarNyheter`
  - `nyheterUtanChangelogVisarTomText`
  - `nyheterMedChangelogVisarVersionerna` (med en testchangelog)
  - `paminnelserVisasInteNarDeInteFinns`

  Se dem fallera.
- [ ] **Steg 2: Implementera**, med samma texter som iOS och Androids ord, till exempel "Notiser är avstängda för appen". Raden Version visar `BuildConfig.VERSION_NAME`.
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: inställningarna, datakällorna och Nyheter på Android`

### Uppgift 4: Snabbmenyn på adresserna

**Filer:**
- Skriv om: `AddressQuickActions.swift`, utom hushållet
- Till: `app/.../ui/home/AddressMenu.kt`. Den öppnas med ett långt tryck på huvudkortet och på raderna under Fler adresser, och har samma val som adressvyns meny.
- Test: `HomeScreenTest`

- [ ] **Steg 1: Skriv testerna**:
  - `langtTryckOppnarMenyn`
  - `gorTillHuvudadressFranMenyn`
  - `taBortFranMenynFragarForst`

  Se dem fallera.
- [ ] **Steg 2: Implementera.** TalkBack får valen som anpassade åtgärder (`customActions`), som på iOS.
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: snabbmenyn på adresserna på Android`

### Uppgift 5: Rättningar från plan 4a

**Filer:** de som anmärkningarna gäller

- [ ] **Steg 1: Skriv ett test per punkt** och se det fallera:
  - **Rubriken:** avståndet ovanför den stora rubriken blir som på iOS. Appfältets utfällda höjd följer rubrikens höjd, och den översta tomma ytan försvinner. Kontrollera med en skärmbild i emulatorn och med ett test av rubrikens position.
  - **Ortlistan** läses och avkodas på `Dispatchers.Default`, inte på huvudtråden.
  - **Ångra på raden Utställt** stänger snackbaren.
  - **Knappen i Hitta område** har bara en marginal mot gestfältet.
  - **Hitta område efter att processen dödats:** resultatet hämtas igen, eller så återgår vyn till sitt första läge med knappen synlig.
- [ ] **Steg 2: Rätta.**
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: rättningar från granskningen av de första skärmarna på Android`

### Uppgift 6: Tillgänglighet och största text i hela appen

**Filer:** `app/src/test/.../ui/AccessibilityTest.kt`, och de skärmar som behöver rättas

- [ ] **Steg 1: Skriv testet:** varje skärm, alltså startvyn, sökningen, kommunfrågan, områdesvalet, Hitta område, bekräftelsen, hemskärmen med en och flera adresser, adressvyn, hela schemat, inställningarna, datakällorna och Nyheter, ritas med `enableAccessibilityChecks()` i ljust och mörkt läge och med `fontScale = 2f`. Testet går igenom utan fel och utan klippt text (samma kontroll som `LargeTextTest`).
- [ ] **Steg 2: Kör, och rätta det som hittas.**
- [ ] **Steg 3: Commit** `build: tillgänglighet och största text i Android-appen`

### Uppgift 7: Prova i emulatorn och PR

- [ ] **Steg 1:** Kör hela sviten: `cd Android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` och `TZ=America/New_York ./gradlew :core:test --rerun`.
- [ ] **Steg 2:** Installera i emulatorn och ta skärmbilder av inställningarna, datakällorna, Nyheter, kärlet med bubblor och snabbmenyn, i ljust och mörkt läge.
- [ ] **Steg 3:** PR med titeln `build: Inställningar, Nyheter och kärlet i Android-appen`, med PR-mallens rubriker.
