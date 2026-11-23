# Android 5: Påminnelser, Live Update och bakgrund

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** Android-appen påminner som iOS-appen gör. Den skickar notiser kvällen före och samma morgon, visar en Live Update med **Klart**, och hämtar scheman i bakgrunden. Alarmen läggs in igen efter omstart, ändrad tid eller tidszon och efter en appuppdatering. Notisen om källmeddelanden skickas från bakgrunden. Påminnelsernas UI, som har varit dolt sedan plan 4a, visas.

**Arkitektur:**
- `ReminderScheduling` från plan 4a ersätts av två gränssnitt i `core`, som speglar iOS: `NotificationScheduling` och `LiveActivityScheduling`. Då kan `performApplyReminders` i `AppModel.swift` och `LiveActivityDiff.swift` skrivas om med sina tester.
- Android-lagret i `app` implementerar gränssnitten:
  - **notiser** med `AlarmManager` och `NotificationManager`,
  - **Live Update** med ett alarm som visar en framhävd pågående notis,
  - **bakgrund** med WorkManager,
  - **omregistrering** med en `BroadcastReceiver`.
- Systemet kan inte svara på vilka alarm som väntar. Därför sparar appen själv det som är schemalagt, i `scheduled-reminders.json`.

**Teknik:**
- `AlarmManager` (`setExactAndAllowWhileIdle`, `setWindow`), `NotificationCompat` med `setRequestPromotedOngoing` och `setShortCriticalText`, och `POST_NOTIFICATIONS` och `POST_PROMOTED_NOTIFICATIONS`.
- WorkManager (`androidx.work:work-runtime`, senaste stabila).
- Robolectric (`ShadowAlarmManager`, `ShadowNotificationManager`), och emulatorn med Android 17 (API 37).

**Spec:** `docs/specs/2026-11-23-android-app.md`, avsnitten Påminnelser och Får inte hända. Facit är `AppModel.swift` (påminnelserna), `NotificationScheduling.swift`, `LiveActivityScheduling.swift`, `LiveActivityDiff.swift`, `BackgroundRefreshRun.swift`, och iOS-vyerna `ReminderToggleRow.swift` och `SettingsView.swift` (Notiser).

## Gemensamma krav

- Samma krav som i plan 4a och 4b.
- **Inget utan användarens val.** Appen frågar om notiser (`POST_NOTIFICATIONS`) bara när användaren slår på en påminnelse eller Live Update, och den frågar aldrig för källmeddelanden. Den begär aldrig exakta alarm själv. Den visar bara raden Exakta tider, som öppnar systemets inställning.
- **Exakta tider:** med `canScheduleExactAlarms()` används `setExactAndAllowWhileIdle`. Utan det används `setWindow` med ett fönster på högst 10 minuter från vald tid. Appen begär inte `USE_EXACT_ALARM`.
- **Kanaler:** **Påminnelser** (hög vikt), **Live Update** (standard) och **Meddelanden från källan** (standard). Namnen och beskrivningarna står i `strings.xml`.
- **Notis-id:** de strängar som `PlannedNotification.identifier` och `SourceMessages.notificationId` ger, omräknade till ett heltal med en stabil hash. Samma sträng ger alltid samma heltal, och strängen sparas som taggen (`notify(tag, id, …)`), så att den går att hitta igen.
- **Ord:** "Live Update" och "för appen", som i plan 3b.

## Granskningsfokus

1. **Telefonen startas om natten före en tömning.** Förväntat: kvällens och morgonens påminnelser och Live Update läggs in igen från det sparade schemat, utan nät.
2. **Användaren byter tidszon eller ändrar klockan.** Förväntat: påminnelserna gäller fortfarande kl. 18:00 svensk tid. Alarmen räknas om efter `TIME_SET` och `TIMEZONE_CHANGED`.
3. **Exakta alarm är inte tillåtna** (Android 14 och senare som standard). Förväntat: påminnelsen kommer inom 10 minuter efter vald tid, och raden Exakta tider syns.
4. **Klart i Live Update eller Utställt i notisen, med appen dödad.** Förväntat: bocken sparas, Live Update visar bocken i 3 sekunder och försvinner, och båda notiserna för tömningen tas bort.
5. **Notiser nekas, eller stängs av i systemet efteråt.** Förväntat: samma lägen som iOS. Rutan "Notiser är avstängda för appen" visas med en knapp till appens notisinställningar, och ingen notis skickas.

---

### Uppgift 1: Gränssnitten och appens påminnelser i kärnan

**Filer:**
- Skriv om: `Reminders/NotificationScheduling.swift`, `LiveActivityScheduling.swift` och `LiveActivityDiff.swift`, och påminnelsedelarna i `App/AppModel.swift` (`applyReminders`, `settleReminders`, `performApplyReminders`, `setNotifications`, inställningarnas setters, `remindersOn`, `handledPickup`, `reserveNotificationDate`, `missedReminderApplies` och `missedReminderText`), och `App/BackgroundRefreshRun.swift`
- Ändra: `core/app/AppModel.kt`, och `ReminderScheduling.kt`, som tas bort
- Till: `core/reminders/` och `core/app/`
- Test: `LiveActivityDiffTests` (utom texttesterna, som redan finns), `AppModelRemindersTests`, `AppModelLiveActivityTests` och `BackgroundRefreshRunTests`, med fejkade gränssnitt som på iOS

**Gränssnitt:**
- Ger: `NotificationScheduling` (`authorization`, `requestAuthorization`, `pending`, `schedule`, `cancel`, `deliverNow`), `LiveActivityScheduling` (`areEnabled`, `current`, `start`, `update`, `remove`, `end`), `SystemActivity` med samma lägen som iOS, och `AppModel(api, store, notifications, liveActivities, clock, scope)`.
- `AppState.remindersAvailable` blir sann när gränssnitten inte är de tomma, så att UI:t visas.

- [ ] **Steg 1: Skriv om testerna** och se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör** `cd Android && ./gradlew :core:test` och `TZ=America/New_York ./gradlew :core:test --rerun`. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: påminnelserna i Android-kärnan`

### Uppgift 2: Notiser med alarm

**Filer:**
- Skapa: `app/.../reminders/AndroidNotifications.kt` (implementerar `NotificationScheduling`), `ReminderAlarmReceiver.kt`, `NotificationChannels.kt` och `ScheduledReminders.kt` (filen `scheduled-reminders.json` i `LocalStore`-katalogen)
- Ändra: `AndroidManifest.xml` (`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` och mottagaren) och `AppDependencies.kt`
- Test: `app/src/test/.../reminders/AndroidNotificationsTest.kt`

- [ ] **Steg 1: Skriv testerna** (Robolectric):
  - `schemalaggerExaktNarDetArTillatet`
  - `schemalaggerFonsterNarExaktaTiderInteArTillatna` (högst 10 minuter)
  - `alarmetVisarNotisenMedUtstalltKnapp`
  - `utstalltIKnappenSparasUtanAttAppenOppnas`
  - `pendingGerDetSomArSchemalagtOchInteHarGattAv`
  - `cancelTarBortAlarmOchNotis`
  - `deliverNowVisasDirekt` (källmeddelanden)
  - `ingenNotisNarNotiserArAvstangda`

  Se dem fallera.
- [ ] **Steg 2: Implementera.** Begäran om tillstånd går genom aktiviteten (`ActivityResultContracts.RequestPermission`), som `AppDependencies` exponerar som en `suspend`-funktion.
- [ ] **Steg 3: Kör** `./gradlew :app:testDebugUnitTest :app:lintDebug`. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: påminnelser med alarm och notiser på Android`

### Uppgift 3: Live Update

**Filer:**
- Skapa: `app/.../reminders/AndroidLiveUpdates.kt` (implementerar `LiveActivityScheduling`) och `LiveUpdateReceiver.kt` (start, Klart och bortsvepning)
- Ändra: `AndroidManifest.xml` (`POST_PROMOTED_NOTIFICATIONS`)
- Test: `app/src/test/.../reminders/AndroidLiveUpdatesTest.kt`

Så fungerar det:
- Ett alarm vid starttiden visar en pågående notis byggd av `PickupActivityContent`:
  - titeln `ALERT_TITLE`, texten `alertBody` och chippet `compactDate` (`setShortCriticalText`),
  - knappen **Klart**,
  - `setRequestPromotedOngoing(true)` och `setTimeoutAfter` på 12 timmar.
- `current()` ger de schemalagda som `pending` och de som visas (`activeNotifications`) som `active`. En notis som svepts bort (`deleteIntent`) blir `dismissed`.
- **Klart** kör `PlacedOutAction`, visar bocken (`markedPlacedOut`) och tar bort notisen efter `PlacedOutAction.checkmarkDuration`.
- Före API 36.1, eller när framhävning inte är tillåten, blir det samma notis utan framhävning.

- [ ] **Steg 1: Skriv testerna**:
  - `startalarmetVisarFramhavdPagaendeNotis` (kontrollerar flaggorna och `EXTRA_REQUEST_PROMOTED_ONGOING`)
  - `klartSparasVisarBockenOchTarBortNotisen`
  - `bortsveptBlirDismissedOchStartasInteIgen`
  - `currentSkiljerSchemalagdaFranVisade`
  - `aldreAndroidGerVanligPagaendeNotis`

  Se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: Live Update på Android`

### Uppgift 4: Omregistrering och bakgrundshämtning

**Filer:**
- Skapa: `app/.../reminders/RescheduleReceiver.kt` (`BOOT_COMPLETED`, `TIME_SET`, `TIMEZONE_CHANGED`, `MY_PACKAGE_REPLACED` och `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`) och `app/.../background/RefreshWorker.kt`
- Ändra: `AndroidManifest.xml` (`RECEIVE_BOOT_COMPLETED` och mottagaren), `SophamtningApplication.kt` (lägger in arbetet), versionskatalogen (WorkManager)
- Test: `app/src/test/.../reminders/RescheduleTest.kt` och `background/RefreshWorkerTest.kt`

- [ ] **Steg 1: Skriv testerna**:
  - `omstartLaggerInAlarmenIgenUtanNat` (`FakeSoporApi` som kastar vid anrop)
  - `tidszonsbyteRaknarOmTillStockholm`
  - `arbetetHamtarOchPlanerarOm`
  - `arbetetSkickarNotisForNyttKallmeddelande`, som ger `RefreshContext.Background`
  - `arbetetKraverNat` (villkoret `NetworkType.CONNECTED`)
  - `arbetetKorsVarTredjeTimme` (det periodiska arbetet är unikt och har en period på 3 timmar)

  Se dem fallera.
- [ ] **Steg 2: Implementera.** Mottagaren använder `goAsync()` och gör klart inom tidsgränsen. Arbetet följer `BackgroundRefreshRun`, så att regeln om en hämtning per timme gäller.
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: omregistrering och bakgrundshämtning på Android`

### Uppgift 5: Påminnelsernas UI

**Filer:**
- Skriv om från iOS-vyerna: `ReminderToggleRow.swift` och avsnittet Notiser i `SettingsView.swift`, med tidsväljarna och Live Update (Visas från och Tid)
- Ändra: skärmarna där påminnelserna har varit dolda (hemskärmen, adressvyn, inställningarna och snabbmenyn), och `app/.../ui/settings/`, som får tidsväljarna och raden **Exakta tider**
- Test: `app/src/test/.../ui/RemindersUiTest.kt` och utökningar av `AccessibilityTest`

- [ ] **Steg 1: Skriv testerna**:
  - `paminnMigFragarOmNotiserOchSlarPa`
  - `nekadVisarRutanMedOppnaInstallningar`, där knappen öppnar `Settings.ACTION_APP_NOTIFICATION_SETTINGS`
  - `exaktaTiderVisasBaraNarDeBehovs`, där knappen öppnar `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`
  - `tidsvaljarenGerKvartarInomIntervallet`
  - `liveUpdateKanSlasPaOchVisasFran`
  - `kallmeddelandenFragarAldrigOmTillstand`

  Se dem fallera.
- [ ] **Steg 2: Implementera.** Tidsväljarna är listor med kvartarna i `ReminderTiming.times`, som på iOS, och ingen urtavla.
- [ ] **Steg 3: Kör.** Förväntat: gröna, också `AccessibilityTest`.
- [ ] **Steg 4: Commit** `build: påminnelsernas inställningar på Android`

### Uppgift 6: Prova på Android 17 och PR

- [ ] **Steg 1:** Kör hela sviten: `cd Android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` och `TZ=America/New_York ./gradlew :core:test --rerun`.
- [ ] **Steg 2:** I emulatorn med API 37:
  - slå på en påminnelse och flytta emulatorns klocka till 17:59 kvällen före en tömning, så att notisen kommer,
  - slå på Live Update och kontrollera chippet i statusfältet och Klart,
  - starta om emulatorn (`adb reboot`) och kontrollera att alarmen finns kvar (`adb shell dumpsys alarm`),
  - kör bakgrundsarbetet (`adb shell cmd jobscheduler run -f se.hardyson.sophamtning <jobb-id>`).

  Skriv resultatet i en ny checklista, `docs/specs/2026-11-23-android-enhetschecklista.md`, som motsvarar `2026-11-06-enhetschecklista.md`.
- [ ] **Steg 3:** PR med titeln `build: Påminnelser och Live Update i Android-appen`. Det är `build:` och inte `feat:`, eftersom Android inte släpps förrän plan 7 (`CLAUDE.md`, avsnittet Releaser).
