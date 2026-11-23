# Sophämtning för Android

Status: godkänd av Jesper 2026-11-23.

## Varför

Sophämtning finns i dag bara för iPhone. Android-appen ska ge samma hjälp till dem som har en Android-telefon: se när kärlen töms, bli påmind och markera kärlen som utställda. Den byggs som en egen, modern native-app i `Android/` i samma repo. Den delar specar, fixturer, ortlista, typsnitt och design med iOS men ingen kod.

## Lyckat resultat

- Android-appen kan i stort sett det som iOS-appen 1.3.1 kan, utom hushåll, widgetar på låsskärmen och röststyrning.
- Samma regler gäller på båda plattformarna: Sopor API v1, högst en hämtning per adress och timme, "i dag" i `Europe/Stockholm`, och inga notiser utan användarens val.
- Den känns som en Android-app och inte som en kopia av iOS: systemets bakåtgest, Material-komponenter och Androids egna platser för widgetar, snabbinställningar och notiser.
- En release görs som på iOS: Jesper mergar en release-PR, godkänner, och bygget hamnar i intern testning i Google Play.

## Med i första versionen

Beteendet följer iOS-specarna, som är facit där inget annat står här: `2026-11-06-ios-app.md`, `2026-11-12-lasskarm-och-kalender.md`, `2026-11-13-installningar-paminnelser.md`, `2026-11-17-kallmeddelanden.md` och avsnittet Ställa ut i `2026-11-09-hushall.md`. Två påminnelser och morgonen beskrivs i `docs/plans/2026-11-09-paminnelse-morgon.md` och `docs/plans/2026-11-12-tva-paminnelser.md`. Där specarna inte säger något, eller säger emot varandra, är iOS-koden i 1.3.1 facit. Det som skiljer sig står nedan.

**Ställ ut utan hushåll:** reglerna för en adress som inte delas gäller. Knappen **Ställ ut kärlen** visas när en påminnelse är på för adressen (som `HouseholdLogic.showsPlaceOutButton` utan delning). Efter tryck blir den raden **Utställt** med **av dig · kl. {hh:mm}** och **Ångra**, och raderna på hemskärmen visar **Kärlen är utställda**. Inget om delning, väntande bockar eller deltagare finns med. *(Mitt beslut, från iOS-koden.)*

| iOS 1.3.1 | Android 1.0.0 |
|---|---|
| Finns min kommun, sök adress, välj område | Samma |
| Hem, huvudkort, Fler adresser, adressvy, hela schemat, Per kärl | Samma, i Compose |
| Ställ ut kärlen och Utställt, med Ångra | Samma, med Ångra i en snackbar |
| Kärlet med pratbubblorna | Samma, och "Ta bort animationer" i Android ersätter Reducera rörelse |
| Påminnelse kvällen före och samma morgon, tid, huvudadress | Samma, med alarm och lokala notiser (se Påminnelser) |
| Utställt i notisen | Samma, som knapp i notisen |
| Live Activity med Klart | En pågående notis med Klart, som Live Update i Android 16 och vanlig pågående notis före det |
| Widgetar på hemskärmen, liten och mellan, med Ställ ut | Samma, med Jetpack Glance |
| Widgetar på låsskärmen | Utgår. Android-telefoner har inga widgetar på låsskärmen |
| Kontrollcenter och Action-knappen | En ruta i snabbinställningarna, **Ställ ut kärlen** |
| Siri | Genvägar på appikonen (långt tryck): huvudadressen och **Lägg till adress**. Ingen röststyrning |
| Lägg till i Kalender | Prenumeration i Google Kalender (se Kalender) |
| Meddelanden från källan | Samma regler, kort och reglage |
| Version öppnar Nyheter | Samma, från Androids egen changelog |
| Datakällor, inofficiell-text, integritet | Samma |
| Hushåll | Utgår, och kommer senare |

## Inte med

- Hushåll och allt som rör CloudKit. `core` ska inte förutsätta att hushåll aldrig kommer, men ingen delning byggs.
- Widgetar på låsskärmen, röststyrning med Google Assistant eller Gemini, Wear OS och anpassad layout för surfplattor. Appen ska fungera på en surfplatta och i liggande läge, men utan egen layout.
- Andra språk än svenska.
- Play-sidan: texter, skärmbilder och formuläret om datasäkerhet. De får en egen spec, som `2026-11-06-app-store.md` för iOS.
- Backend, konton, push och analys.

## Får inte hända

- Appen frågar om notiser eller exakta alarm innan användaren har slagit på en påminnelse eller Live Update.
- En påminnelse försvinner efter en omstart av telefonen, en ändrad tidszon eller en appuppdatering.
- Android-ändringar höjer iOS-versionen eller startar ett TestFlight-bygge, och tvärtom.
- En Android-PR kan inte mergas för att den obligatoriska iOS-kontrollen aldrig körs.
- Dynamiska färger från bakgrundsbilden ändrar appens färger. Fraktionernas färger är fasta.

## Vägval

**Version och release** (Jesper valde 1):

1. **Två komponenter i Release Please**, med varsin version, changelog och tagg. Ändringar i den ena appen ger aldrig en release av den andra. Det kräver en engångsflytt av changelog, version och taggar för iOS.
2. **En gemensam version.** Releasen blir enklare, men en rättning i Android höjer också iOS och startar ett onödigt TestFlight-bygge. Android skulle börja på 1.4.
3. **Ett eget repo för Android.** Det blir mest isolerat, men specar, fixturer, regler och design måste då hållas i takt på två ställen.

**Teknik:** Kotlin med Jetpack Compose är Googles rekommenderade väg för en ny app. Alternativen, att dela logiken med Kotlin Multiplatform eller att använda Flutter eller React Native, skulle kräva att den testade Swift-kärnan skrivs om, eller att appen inte längre är native.

## Grundbeslut

| Område | Beslut |
|---|---|
| Språk | Kotlin, med coroutines och `Flow` |
| UI | Jetpack Compose med Material 3 och appens egna färger, typsnitt och former. Inga dynamiska färger |
| Lägsta version | Android 12 (API 31). Senaste stabila API som mål |
| Beroenden | Bara AndroidX, Jetpack och JetBrains bibliotek (`kotlinx.serialization`, `kotlinx.coroutines`, Ktor eller OkHttp för nätet). Inget DI-ramverk |
| Lagring | JSON-filer i appens egen katalog, skrivna atomiskt, med samma format som iOS |
| Bakgrund | WorkManager för hämtningen, `AlarmManager` för påminnelserna |
| Widgetar | Jetpack Glance |
| Webblänkar | Custom Tabs, som motsvarar `SFSafariViewController` |
| Bygge | Gradle med Kotlin DSL och en versionskatalog (`gradle/libs.versions.toml`) |
| Identitet | `applicationId` `se.hardyson.sophamtning`. User-Agent `Sophamtning-Android/<version>` |

Exakta versioner väljs i planen, efter aktuell dokumentation.

## Arkitektur

```text
Android/
  settings.gradle.kts
  gradle/libs.versions.toml
  core/      ren Kotlin (JVM): API-modeller, avkodning, schemalogik, påminnelseplanerare,
             kommunkoll, källmeddelanden, lagring. Inga Android-API:er
  app/       Compose-UI, design, notiser, alarm, WorkManager, widgetar, snabbinställningar
```

- `core` motsvarar `SophamtningKit` och har samma uppdelning: logik som inte känner till nätverk, lagring eller systemets API:er, och tunna lager för API-klient och lagring. Testerna körs på JVM utan emulator, som `swift test`.
- Designen (färger, typsnitt, fraktionernas färg och ikon, kort, chips) ligger i `app` under ett eget paket. Fredoka och Nunito hämtas från iOS-paketets resurser, så att de inte finns i två exemplar.
- Ortlistan (`orter.json`) och testfixturerna (`Fixtures/` och `UITestData/`) läses från iOS-mapparna med Gradle, och kopieras inte in i `Android/`. Ett test som går på iOS och samma test i `core` läser alltså samma fil.
- De delade filerna ligger kvar under `iOS/`, eftersom Swift-paketet bara kan ta med resurser inom sin egen mapp. En ändring i dem räknas därför till iOS i Release Please. `android.yml` körs ändå när de ändras, eftersom filtret också täcker de delade sökvägarna (ortlistan, `Fixtures/`, `UITestData/` och typsnitten). Ska en ändring i ortlistan nå Android-användarna görs en Android-release med en `fix:` i `Android/`. *(Mitt beslut.)*
- Widgeten, rutan i snabbinställningarna och alarmen körs i appens egen process. Därför behövs ingen motsvarighet till App Group.

## Påminnelser

Planeraren räknar som på iOS ut vilka notiser och vilken pågående notis som ska finnas. Android-lagret registrerar dem som alarm.

- **Tillstånd för notiser** (`POST_NOTIFICATIONS`) frågas när användaren slår på en påminnelse eller Live Update, och aldrig annars. Nekas det gäller samma ruta som på iOS, "Notiser är avstängda för appen", med en knapp till appens notisinställningar.
- **Exakta alarm:** när appen får använda exakta alarm (`canScheduleExactAlarms`) kommer påminnelsen på minuten. Annars används ett kort fönster (högst 10 minuter efter vald tid). Appen begär inte `USE_EXACT_ALARM`, eftersom Google Play bara tillåter det för väckarklockor och kalendrar. Under Inställningar → Notiser står raden **Exakta tider** med en knapp till systemets inställning, bara när en påminnelse är på och exakta alarm inte är tillåtna. *(Mitt förslag.)*
- **Omstart, tidszon och uppdatering:** Android tar bort alarm vid omstart. Appen registrerar om dem vid `BOOT_COMPLETED`, ändrad tid eller tidszon och efter en appuppdatering, utan nätanrop och från det sparade schemat.
- **Bakgrundshämtning:** WorkManager hämtar adresserna några gånger per dygn när nätet finns, med samma regel om en gång per timme, och planerar sedan om påminnelserna. Hämtningen i bakgrunden räknas som `.background` för källmeddelanden.
- **Live Update:** kvällen före eller samma morgon startar ett alarm den pågående notisen för huvudadressen, med kärlen och knappen **Klart**. I Android 16 och senare begärs den som en framhävd notis (Live Update). Tillåts den inte, eller på äldre Android, blir den en vanlig pågående notis. Klart, Utställt i notisen, widgeten och rutan i snabbinställningarna gör samma sak som `markPlacedOut` på iOS.
- Texterna under reglagen och på huvudkortet säger "Live Update" där iOS säger "Live Activity".

## Widgetar och snabbinställningar

- Glance-widgetar i storlekarna liten och mellan, med samma innehåll som iOS (`WidgetContent`) och knappen **Ställ ut kärlen** när det är dags. De uppdateras när schemat eller Utställt ändras och vid midnatt i Stockholm.
- Rutan **Ställ ut kärlen** i snabbinställningarna gäller huvudadressen. Den är aktiv när kärlen ska ställas ut, och visar "Utställt" eller är avstängd annars, med nästa tömning som undertext.
- Allt räknas från det sparade schemat, utan nätanrop.

## Kalender

- Adressvyn får avsnittet **Kalender** med raden **Lägg till i Google Kalender** och texten "Tömningarna läggs in som en egen kalender i Google Kalender, som uppdateras av sig själv. Kalendern påminner kl. 18 kvällen innan, utöver appens notiser."
- Raden öppnar Google Kalenders länk för att prenumerera med adressens `links.ics` (`https://calendar.google.com/calendar/render?cid=<webcal-adressen>`). Appen läser aldrig kalendern och behöver ingen behörighet.
- Avsnittet visas bara när svaret har en `links.ics`.
- Att länken faktiskt leder till en prenumeration provas på en riktig telefon med och utan Google Kalender-appen. Fungerar den inte där, tas frågan tillbaka till Jesper innan avsnittet byggs vidare.

## Design

- Pencil går inte att använda just nu. Facit för färger, typsnitt, kärlet och korten är därför iOS-appen som den ser ut i dag: färgerna och måtten i `SophamtningDesign`, kärlets animation i iOS-koden och skärmbilderna i `docs/appstore/`. Kärlet ritas om i Compose från iOS-koden. Pencil-designen uppdateras när den går att använda igen. Layouten följer Android: en övre appfält med bakåtpil, bakåtgest, menyer i stället för iOS snabbmenyer, och nederkantsark (`ModalBottomSheet`) eller helskärmsvyer där iOS har ark.
- Ljust och mörkt läge, TalkBack och systemets textstorlek ska fungera överallt. Fraktioner visas alltid med färg, ikon och text.
- Kanten-till-kanten-layout (edge-to-edge) med rätt marginaler mot statusfält och gestfält.

## Release och CI

### Två komponenter i Release Please

- `release-please-config.json` får två paket, `iOS` och `Android`, med `include-component-in-tag: true`. Taggarna blir `ios-vX.Y.Z` och `android-vX.Y.Z`, och varje app har sin version, sin changelog och sin GitHub Release.
- En commit räknas till den app vars filer den ändrar. En commit som bara ändrar `docs/`, `scripts/` eller roten räknas till ingen.
- **Flytten görs först, i en egen PR före Android-koden:** `CHANGELOG.md` och `version.txt` flyttas till `iOS/`, manifestet blir `{ "iOS": "1.3.1" }` (Android läggs till med sin första kod), och Release Please får `bootstrap-sha` på samma commit som `v1.3.1`, så att förra releasen hittas utan en ny tagg. Gamla taggar ligger kvar. `iOS/project.yml`, `release.yml`, `appstore-notes.yml`, `scripts/` och `CLAUDE.md` pekar om. iOS-versionen och Nyheter ska inte ändras av flytten, vilket kontrolleras med ett testbygge.
- Android börjar på 1.0.0, till exempel med `release-as: 1.0.0` i första release-PR:en. Androids version ligger i en fil som Release Please uppdaterar, som `iOS/Config/Version.xcconfig`. `versionCode` räknas fram i jobbet och ökar alltid.

### CI

- Den obligatoriska kontrollen `test` får inte bli hängande för en Android-PR. `ios.yml` körs därför fortfarande på alla PR:er, men ett litet jobb på Ubuntu avgör först om `iOS/` har ändrats. Är det inte så hoppas iOS-jobbet över, vilket räknas som godkänt. *(Mitt förslag. Alternativet är att byta de obligatoriska kontrollerna i regeluppsättningen.)*
- `android.yml` gör på samma sätt för `Android/` och kör på Ubuntu: `core`-testerna, appens enhetstester, lint och ett bygge. Jobbet blir en ny obligatorisk kontroll.
- UI-testerna för kärnflödena och tillgänglighetskontrollen körs på en emulator innan release-PR:en mergas, som `Granskning` på iOS.

### Google Play

- När Android-releasen skapas startar jobbet **Google Play** i samma körning. Det väntar på Jespers godkännande i miljön `googleplay`, bygger en signerad AAB och laddar upp den till **intern testning** med Play Developer API.
- Uppladdningsnyckeln och tjänstkontots nyckel ligger som secrets i miljön. Google sköter appens signering (Play App Signing).
- "Vad är nytt" (`sv-SE`) fylls i med versionens avsnitt ur changelogen, som ren text och högst 500 tecken. Blir texten längre kortas den, och Jesper kan skriva om den i Play Console.
- **Körning för hand:** Actions > Release > Run workflow får valet **app** (`ios` eller `android`), och en körning rör bara den valda appen. Med tagg görs uppladdningen om. Utan tagg blir det ett testbygge till intern testning, med nästa patchversion efter Androids version som `versionName`, och "Vad är nytt" blir "Testbygge från `<gren>` (`<commit>`)". `versionCode` räknas med samma formel som byggnumret på iOS (`run_number` × 100 + `run_attempt`) i samma workflow, så att den alltid ökar och aldrig krockar med en release. *(Mitt beslut.)*
- Jesper flyttar själv en version vidare till slutet test eller produktion i Play Console.
- **Engångssteg för Jesper:** skapa appen i Play Console, ladda upp det första bygget för hand (API:t kan inte skapa en app) och skapa tjänstkontot. Kontot är personligt. Är det skapat efter november 2023 krävs ett slutet test med minst 12 testare i 14 dagar före produktion, och planen räknar med det tills Play Console säger något annat. Appens paketnamn bestäms av det första bygget och kan aldrig ändras, så det första bygget måste ha `se.hardyson.sophamtning`.

## CLAUDE.md

- `Android/` beskrivs med `core/` och `app/`, och avsnittet Kommandon får Gradle-kommandona för test, bygge och UI-test.
- Reglerna skiljer på plattformarna där det behövs: lägsta version, User-Agent och identitet.
- Avsnittet Releaser beskriver de två komponenterna, taggarna och miljön `googleplay`.
- Regeln om notiser gäller båda appar. Undantaget för källmeddelanden säger "när systemet redan tillåter notiser".

## Test

- **`core`:** iOS-paketets tester skrivs om i Kotlin för det som finns med här: avkodning med fixturerna, schemalogik, Stockholmstid och dagsbyte i en annan tidszon, påminnelseplaneraren, kommunkollen, källmeddelanden, Nyheter-tolkningen och lagringen. Nya kontroller av vad som visas och vilken text skrivs som enhetstester.
- **Android-lagret:** enhetstester för att alarmen registreras om efter omstart och tidszonbyte, och för fönstret när exakta alarm inte är tillåtna.
- **UI:** några få kärnflöden med Compose-tester mot fixturerna, som `UITestAPI` på iOS, och en tillgänglighetskontroll med största textstorleken.
- **Enhet:** en checklista för en riktig telefon, som `2026-11-06-enhetschecklista.md`: påminnelse efter omstart, Live Update i Android 16, widgeten, rutan i snabbinställningarna, Google Kalender och en notis om ett källmeddelande från bakgrunden.

## Kvar till byggaren

- Exakta biblioteksversioner, navigationsbiblioteket och hur skärmarna delas i ViewModels.
- Hur ofta WorkManager körs, inom regeln om en gång per timme.
- Hur Androids version och changelog läses in i bygget, och skriptet för "Vad är nytt".
- Ordningen i planen, med flytten i Release Please först.
