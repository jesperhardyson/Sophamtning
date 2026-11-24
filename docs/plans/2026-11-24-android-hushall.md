# Android: Hushåll

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** Android-appen får hushåll med samma funktioner som iPhone, i samma hushåll, via brevlådan på Cloudflare och med push via FCM.

**Arkitektur:**
- `core` får hushållets modeller, logik, texter, kryptering och synk, och hushållsdelen av `AppModel`. Inget där känner till Android eller Firebase, och allt testas på JVM mot en falsk server.
- `app` får bara det som kräver Android: filerna för nyckel och enhet, Firebase, länkar, notiskanalen, kontrollen före en påminnelse och skärmarna.
- Arbetet görs i två PR:er: kärnan (uppgift 1–6, gren `feature/android-hushall-karna`) och appen (uppgift 7–11, gren `feature/android-hushall-app`).

**Teknik:** Kotlin, coroutines, `kotlinx.serialization`, Ktor 3.6 (HTTP och WebSocket), `javax.crypto`, Compose med Material 3, WorkManager, `firebase-messaging` 26.0.2 (Firebase BoM 35.2.0), Robolectric.

**Spec:** `docs/specs/2026-11-23-hushall-mellan-plattformar.md` (avsnittet Android-appen) och `docs/specs/2026-11-09-hushall.md`. Båda ska läsas. Där de inte säger något är iOS-koden facit.

**Förutsättningar:**
- Uppgift 0–4 i `docs/plans/2026-11-23-hushall-mellan-plattformar.md` är klara: servern är driftsatt och `hushall-vectors.json` finns.
- iOS-versionen med brevlådan är släppt innan Android-versionen med hushåll släpps. Bygget kan göras innan.
- Jesper har skapat Firebase-projektet (uppgift 0 där) innan uppgift 8 provas på en telefon.

## Gemensamma krav

- Lägsta version är Android 12 (API 31). `firebase-messaging` är det enda nya biblioteket, och bara i `app`.
- All text, alla kommentarer och alla commit-meddelanden är på svenska. Inga AI-attributionsrader. Tills Android 1.0.0 är släppt är commits `build:`, därefter `feat:`, enligt `CLAUDE.md`. Exemplen nedan skriver `build:`.
- Bas-URL är `https://hushall.sopor.hardyson.se/v1`. User-Agent är `Sophamtning-Android/<version>`.
- Krypteringen, länken, gränserna och felkoderna är exakt de i Gemensamma krav i planen för servern och iOS.
- Bara felkoderna `removed` och `ended` tar bort hushållet. Allt annat är `HouseholdStatus.Failed` med kopian kvar.
- "I dag", hämtdatum och `expiresAt` räknas i `Europe/Stockholm` (`StockholmClock`).
- `SavedAddress.url` och adress-id skrivs, krypteras och används oförändrade.
- Inget registreras hos Firebase utan hushåll. Frågan om notiser ställs bara när **Notiser från hushållet** slås på.
- Nycklar, inbjudningslänkar och namn skrivs aldrig i loggen eller i `savedInstanceState`.
- Allt som rör `AppModel` körs på huvudtråden. Nätet och krypteringen körs utanför den.
- Varje uppgift kör `cd Android && ./gradlew :core:test`, och när `app` ändras också `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`. Datumtester körs dessutom med `TZ=America/New_York ./gradlew :core:test --rerun`.

## Granskningsfokus

1. **En adress som Android delar ska gå att läsa på iPhone.** `storeJson` utelämnar fält med standardvärde, och iOS kräver `notificationsOn`. Testet `adressFranAndroidHarAllaFalt` i uppgift 3.
2. **Alarmet startar processen kallt.** `SophamtningApplication.onCreate` kör `rescheduleAll`, som i dag visar passerade påminnelser direkt, före mottagaren. Då hoppas kontrollen av hushållet över. Testet `kallstartKontrollerarHushalletForst` i uppgift 9.
3. **Telefonen vilar (Doze) och har inget nät när påminnelsen ska visas.** Den visas ändå, inom 4 sekunder. Även om `applyReminders` hinner ta bort posten ur filen. Testerna `utanNatVisasPaminnelsen` och `omplaneringTarInteBortPaminnelsen` i uppgift 9.
4. **`household-credentials.json` går inte att läsa.** Hushållet blir `Failed` med kopian kvar, aldrig "inget hushåll", och filen skrivs inte över. Testet `olasbaraNycklarGerFailed` i uppgift 4.
5. **Telefonen saknar Google Play-tjänster, eller bygget saknar Firebase-värdena.** Appen startar, hushållet fungerar när appen är öppen, och inget fel visas. Testet `utanFirebaseFungerarHushallet` i uppgift 8.

## Filer

Sökvägar som börjar med `core/` och `app/` ligger under `Android/<modul>/src/main/kotlin/se/hardyson/sophamtning/` (för `core` i paketet `core`). Testerna ligger på motsvarande plats under `src/test`.

| Fil | Ansvar |
|---|---|
| `core/household/HouseholdModels.kt` | Roll, deltagare, adress, bock, läge, val |
| `core/household/HouseholdLogic.kt` | Rena regler, som `HouseholdLogic.swift` |
| `core/household/HouseholdTexts.kt` | Texterna |
| `core/household/HouseholdSync.kt` | `HouseholdSync`, `HouseholdMembership`, `DisabledHousehold` |
| `core/household/InMemoryHouseholdSync.kt` | Hushållet i minnet, för tester och skärmtester |
| `core/household/HouseholdReminderCheck.kt` | Om en påminnelse ska visas |
| `core/household/relay/HouseholdCrypto.kt` | Nycklar, HKDF, postnamn, kryptering |
| `core/household/relay/HouseholdInviteLink.kt` | Länken till och från text |
| `core/household/relay/RelayWire.kt` | JSON-typerna och felkoderna |
| `core/household/relay/RelayTransport.kt` | Gränssnittet för HTTP och signaler |
| `core/household/relay/KtorRelayTransport.kt` | HTTP och WebSocket med Ktor |
| `core/household/relay/RelayStorage.kt` | Nycklarna, enheten, kopian och kön som filer |
| `core/household/relay/RelayHouseholdSync.kt` | Synken mot brevlådan |
| `core/placedout/PlacedOutLine.kt` | Raden för Utställt, nu också med hushåll |
| `core/app/AppModelHousehold.kt` | Hushållsdelen av `AppModel` |
| `app/household/HouseholdPush.kt` | Registrering och avregistrering hos FCM |
| `app/household/HouseholdMessagingService.kt` | Tar emot push |
| `app/household/HouseholdFetchWorker.kt` | Hämtar när nätet är tillbaka |
| `app/ui/household/*` | Skärmen Hushåll och dess ViewModel |
| `app/reminders/ReminderAlarmReceiver.kt`, `AndroidNotifications.kt` | Kontrollen före påminnelsen |
| `app/build.gradle.kts`, `AndroidManifest.xml`, `res/xml/data_extraction_rules.xml` | Firebase, länkar, säkerhetskopian |

---

# PR 1: Kärnan

## Uppgift 1: Modeller, lagring, logik och texter

**Files:**
- Create: `core/household/HouseholdModels.kt`, `HouseholdLogic.kt`, `HouseholdTexts.kt`, `HouseholdSync.kt`, `InMemoryHouseholdSync.kt`
- Modify: `core/storage/LocalStore.kt`
- Test: `household/HouseholdModelsTest.kt`, `HouseholdLogicTest.kt`, `HouseholdTextsTest.kt`, `InMemoryHouseholdSyncTest.kt`

**Interfaces:**
- Produces:
  - `enum class HouseholdRole { None, Owner, Member }`
  - `data class HouseholdParticipant(val id: String, val name: String, val isOwner: Boolean, val legacyIds: List<String> = emptyList())`
  - `data class HouseholdAddress(val address: SavedAddress, val addedBy: String)`
  - `data class HouseholdMark(val placedOut: PlacedOut, val by: String, val at: Instant, val isPending: Boolean)`
  - `enum class HouseholdStatus { Synced, Removed, Failed }`
  - `data class HouseholdState(val role, val myId: String?, val participants, val addresses, val marks, val status, val myName: String? = null)` med `HouseholdState.Empty` och `val isMember: Boolean` (roll finns och inte `Removed`).
  - `data class HouseholdPreferences(...)` med samma fält och standardvärden som iOS.
  - `LocalStore`: `householdState(): StoreRead<HouseholdState>`, `setHouseholdState(_)`, `householdPreferences()`, `setHouseholdPreferences(_)`. Filerna är `household.json` och `household-preferences.json`.
  - `HouseholdLogic`: `showsPlaceOutButton`, `currentMark`, `newParticipants`, `departedParticipants`, `isKnown(participant, known)`, `expired`, `othersActive` och `merge`, med iOS regler.
  - `HouseholdTexts`: iOS texter ordagrant, med de nya från uppgift 7 i planen för iOS. Texterna om iCloud och Väntar på svar tas inte med.
  - Gränssnitten:

```kotlin
interface HouseholdSync {
    /** Senast kända läget, och sedan varje ändring. */
    val states: Flow<HouseholdState>
    suspend fun share(address: SavedAddress)
    suspend fun unshare(key: AddressKey)
    suspend fun mark(placedOut: PlacedOut)
    suspend fun unmark(placedOut: PlacedOut)
    suspend fun leave()
    suspend fun removeExpired(today: DayDate)
    suspend fun setMyName(name: String)
    suspend fun fetchChanges()
}

interface HouseholdMembership {
    suspend fun create(myName: String)
    suspend fun invite(): HouseholdInviteLink
    suspend fun revokeInvites()
    suspend fun join(link: HouseholdInviteLink, myName: String?)
    suspend fun remove(participantId: String)
    suspend fun end()
    fun isCurrent(link: HouseholdInviteLink): Boolean
    suspend fun registerDevice(fid: String, urgent: Boolean)
    suspend fun unregisterDevice()
}
```

  `HouseholdInviteLink` skapas i uppgift 3. Här räcker klassens deklaration, `data class HouseholdInviteLink(val householdId: String, val inviteToken: String, val householdKey: ByteArray)` med `equals` på innehållet.

- [ ] **Steg 1:** Skriv om testerna i `HouseholdLogicTests.swift` (25), `HouseholdModelsTests.swift` och `InMemoryHouseholdSyncTests.swift` till Kotlin, med samma namn. Fallen om iCloud och inbjudna utgår. Lägg till:
  - `flyttadDeltagareArKand`: `isKnown` är sant när något i `legacyIds` finns i `known`, och den räknas varken som ny eller, för sitt gamla id, som lämnad.
  - `hushalletFranAldreFilFarStandardvarden`, `okantLageIFilenGerFailed`.
  - `texternaArSammaSomIOS`: de strängar som `HouseholdTexts.swift` har och som tas med är exakt lika, uppräknade i testet, inklusive `intro` med "Hushållet krypteras på era telefoner, och bara ni kan läsa det."
- [ ] **Steg 2:** Kör `./gradlew :core:test --tests '*household*'`. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera. `PlacedOutLogic.showsPlaceOutButton` och `currentMark` ersätts av `HouseholdLogic` och tas bort i uppgift 2.
- [ ] **Steg 4:** Kör `./gradlew :core:test`. Förväntat: grönt.
- [ ] **Steg 5:** Committa `build: Hushållets modeller, regler och texter i Android-kärnan`

## Uppgift 2: Det som visas och planeras med hushåll

**Files:**
- Modify: `core/placedout/PlacedOutLine.kt`, `core/home/HomeContent.kt`, `core/home/AddressDetail.kt`, `core/widget/WidgetContent.kt`, `core/widget/PlaceOutTileContent.kt`, `core/reminders/ReminderPlanner.kt`
- Test: motsvarande testfiler

**Interfaces:**
- Consumes: uppgift 1.
- Produces:
  - `PlacedOutLine` får `isShared`, `sharedText: String?`, `isPending` och `statusText: String?`, med standardvärden så att dagens anrop fungerar. `PlacedOutLine.make(..., household: HouseholdState = HouseholdState.Empty)` följer `HouseholdLine.make`. Undertexten med klockslag för en adress som inte delas står kvar.
  - `HomeContent.make` och `AddressDetail.make` får `household` och `silencedPickups: Set<PlacedOut> = emptySet()`.
  - `WidgetData.placedOutBy(now: Instant): String?`: "av Kim", "av dig" eller "av någon". `WidgetData.read` läser `household.json`, och en fil som inte går att läsa ger ingen bock.
  - `ReminderPlanner.activityContent(..., household: HouseholdState = HouseholdState.Empty)`.

- [ ] **Steg 1:** Skriv om hushållsfallen till Kotlin från `HomeContentTests.swift` (från rad 700), `WidgetContentTests.swift` (från rad 320), `PlacedOutContentTests.swift`, `AddressDetailTests.swift` och `LiveActivityDiffTests.swift`. Lägg till `rutanArAvstangdNarNagonAnnanHarStalltUt` och `utanHushallArRadenSomForut`.
- [ ] **Steg 2:** Kör testerna. Förväntat: de nya misslyckas, de gamla är gröna.
- [ ] **Steg 3:** Implementera.
- [ ] **Steg 4:** Kör `./gradlew :core:test` och `TZ=America/New_York ./gradlew :core:test --rerun`. Förväntat: grönt.
- [ ] **Steg 5:** Committa `build: Utställt från hushållet i Android-kärnans innehåll`

## Uppgift 3: Krypteringen, länken och formatet

**Files:**
- Create: `core/household/relay/HouseholdCrypto.kt`, `HouseholdInviteLink.kt`, `RelayWire.kt`
- Test: `household/relay/HouseholdCryptoTest.kt`, `HouseholdInviteLinkTest.kt`, `RelayWireTest.kt`

**Interfaces:**
- Consumes: `hushall-vectors.json` via de delade fixturerna.
- Produces:
  - `enum class RelayRecordKind { Address, Mark }`, som `address` och `mark` i JSON.
  - `class HouseholdCrypto(householdId: String, householdKey: ByteArray)` med `recordName(logical)`, `seal(plaintext: ByteArray, name, kind): String`, `open(data: String, name, kind): ByteArray`, `sealName(plaintext, participantId)`, `openName(data, participantId)`, `companion newKey()`, och en `internal` `seal(..., nonce)`.
  - `HouseholdInviteLink.parse(text: String): HouseholdInviteLink?` och `val text: String`.
  - `RelayWire`: `ChangesResponse`, `ParticipantWire`, `RecordWire`, `ErrorResponse`, klartexterna `AddressPlaintext(address, legacy)`, `MarkPlaintext(source, id, date, legacy)`, `NamePlaintext(name, legacyIds)`, `Legacy(by, at: Instant)`, och `val relayJson: Json` med `encodeDefaults = true`, `explicitNulls = false` och `ignoreUnknownKeys = true`.
  - `enum class RelayErrorCode(val raw: String)`: `removed`, `ended`, `invite_invalid`, `full`, `conflict`, `not_found`.

- [ ] **Steg 1: Skriv tester som misslyckas:**
  - `vektorernaStammer`: varje fall ger exakt `name` och `data`, och `open` ger `plaintext`.
  - `felAADGerFel`: fel `name`, `kind`, hushåll eller nyckel kastar.
  - `hkdfFoljerRfc5869`: testfall 3 i RFC 5869 (utan salt och info) stämmer.
  - `adressFranAndroidHarAllaFalt`: en `SavedAddress` med `notificationsOn = false` och utan `detail` skrivs med exakt nycklarna `key`, `url`, `street`, `locality`, `kommun`, `selection`, `displayName`, `isPrimary`, `notificationsOn`, `addedAt`.
  - `adresserFranVektorernaGarAttLasa`: båda adressfallen, också det med `\/` och ett okänt fält, ger `SavedAddress` med oförändrad `url`.
  - `lankTillOchFran`, `lankMedFelVersionVardEllerDelarGerNull` (`#2.…`, `http:`, fel värd, fel antal delar, en nyckel som inte är 32 byte, utfyllnad med `=`).
- [ ] **Steg 2:** Kör. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera med `Cipher("AES/GCM/NoPadding")`, `GCMParameterSpec(128, nonce)`, `Mac("HmacSHA256")`, `java.util.Base64.getUrlEncoder().withoutPadding()` och `SecureRandom`.
- [ ] **Steg 4:** Kör `./gradlew :core:test`. Förväntat: grönt.
- [ ] **Steg 5:** Committa `build: Kryptering och inbjudningslänk för hushåll i Android-kärnan`

## Uppgift 4: Synken mot brevlådan

**Files:**
- Create: `core/household/relay/RelayTransport.kt`, `RelayStorage.kt`, `RelayHouseholdSync.kt`, `KtorRelayTransport.kt`
- Test: `household/relay/FakeRelayServer.kt`, `RelayHouseholdSyncTest.kt`, `KtorRelayTransportTest.kt`

**Interfaces:**
- Consumes: uppgift 1 och 3.
- Produces:
  - `interface RelayTransport { suspend fun send(request: RelayRequest): RelayResponse; fun signals(householdId: String, authorization: String): Flow<Int> }`, med `RelayRequest(method, path, headers, body: String?)` och `RelayResponse(status: Int, body: String)`. Nätfel kastas som `IOException`.
  - `class KtorRelayTransport(engine: HttpClientEngine, version: String) : RelayTransport`. Tidsgräns 10 sekunder. `signals` kopplar upp igen efter 1, 2, 4 och sedan högst 30 sekunder.
  - `data class HouseholdCredentials(householdId, householdKey, participantId, participantSecret)` och `class RelayStorage(store: LocalStore)`, med filerna `household-credentials.json`, `household-device.json` (`deviceId`, skapat när det saknas), `household-relay.json` (kopian med `seq`) och `household-relay-pending.json` (kön).
  - `class RelayHouseholdSync(transport, storage: RelayStorage, clock: () -> Instant, scope: CoroutineScope) : HouseholdSync, HouseholdMembership` med `startSignals()` och `stopSignals()`.
  - `class HouseholdException(val code: RelayErrorCode?) : Exception`.

- [ ] **Steg 1:** Skriv `FakeRelayServer` med samma regler som den i iOS-paketet: behörighet, `If-None-Match`, `seq`, felkoder, gränser, och lägen för `500` och nätfel.
- [ ] **Steg 2: Skriv tester som misslyckas.** Samma namn och fall som `RelayHouseholdSyncTests` i uppgift 5 i planen för iOS, och dessutom:
  - `olasbaraNycklarGerFailed`: en skadad `household-credentials.json` ger `Failed` med den sparade kopian, och filens byte är oförändrade.
  - `markSparasIKonForeNatet`: kön är skriven innan något anrop görs, så att bocken överlever att processen dödas.
  - `legacyVisarRattNamnOchTid`: en flyttad bock visar `legacy.at` och namnet på den vars `legacyIds` har `legacy.by`, annars id:t oförändrat.
  - `olasbarPostTarInteBortAdressen`.
  - `tvaHamtningarSamtidigtBlirEn`: en push och en signal samtidigt ger ett anrop i taget, och `seq` går aldrig bakåt.
  - `lamnaRaderarNycklarOchKopia`: också när servern inte svarar tas de inte bort, utan `leave()` kastar.
  - I `KtorRelayTransportTest` (MockEngine): `userAgentOchBehorighetSkickas`, `svarMed500ArInteUndantag`, `natfelBlirIOException`.
- [ ] **Steg 3:** Kör. Förväntat: misslyckas.
- [ ] **Steg 4:** Implementera. En `Mutex` runt hämtning och skickning. Läget skickas bara när det har ändrats, och innan en hämtning med `full: true` har lyckats skickas bara lägen med fel. `unregisterDevice` är bästa försök.
- [ ] **Steg 5:** Kör `./gradlew :core:test`. Förväntat: grönt.
- [ ] **Steg 6:** Committa `build: Hushållets synk mot brevlådan i Android-kärnan`

## Uppgift 5: Hushållet i `AppModel`

**Files:**
- Create: `core/app/AppModelHousehold.kt`
- Modify: `core/app/AppModel.kt`, `core/app/BackgroundRefreshRun.kt`
- Test: `app/AppModelHouseholdTest.kt`, `BackgroundRefreshRunTest.kt`

**Interfaces:**
- Consumes: uppgift 1, 2 och 4.
- Produces:
  - `AppModel` får `household: HouseholdSync = DisabledHousehold` och `membership: HouseholdMembership? = null` i konstruktorn.
  - `AppState` får `household`, `householdPreferences`, `householdNotice: String?`, `householdScreenRequested: Boolean`, `pendingInvite: HouseholdInviteLink?` (bara i minnet), `isShared(key)`, `inHousehold`, `canManageMembers`, `householdMembersText`, `householdName` och `householdNameMissing`. `homeContent` och `addressDetail` skickar dem vidare.
  - Funktioner, med iOS regler: `startHousehold()`, `fetchHouseholdChanges()`, `setShared(on, key): Boolean`, `setHouseholdName(name): Boolean`, `leaveHousehold()`, `endHousehold(): Boolean`, `removeParticipant(id): Boolean`, `inviteLink(): HouseholdInviteLink?`, `revokeInvites(): Boolean`, `receiveInvite(link)`, `answerInvite(leaveCurrent: Boolean)`, `clearHouseholdNotice()`, `clearMembersNotice()`, `householdScreenShown()`, `setSilenceWhenOthersPlaceOut(on)`, `setNotifyWhenOthersPlaceOut(on): PermissionResult`, `householdSilenced(today): Set<PlacedOut>`, `wantsUrgentPush(): Boolean` (notiserna på och tillåtna).
  - `markPlacedOut` och `undoPlacedOut` skickar eller tar bort bocken också i hushållet när adressen delas. Alla fyra vägar (appen, notisen, widgeten, rutan) och Klart i Live Update använder dem redan.
  - `BackgroundRefreshRun` hämtar hushållets ändringar före planeringen. Ett fel där stoppar inte schemana.

- [ ] **Steg 1:** Skriv om de 40 testerna i `AppModelHouseholdTests.swift` till Kotlin, med samma namn. `utloggadBehallerAdresser` blir `felBehallerAdresser`, och `forslagetFranAppleKontotFyllerFaltet` utgår. Lägg till testerna ur uppgift 7 i planen för iOS, och:
  - `lankTillSammaHushallFragarInte`
  - `inbjudanNarJagArMedFragarForst`: `pendingInvite` sätts, och inget görs förrän `answerInvite`.
  - `nejTillAttLamnaGorInget`
  - `urgentFoljerValOchTillstand`
  - `omplaneringenAnvanderHushalletsBockar`: andras bock tar bort påminnelsen och avslutar Live Update med "av Kim · kl. 19:42".
- [ ] **Steg 2:** Kör. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera. `performApplyReminders` lägger `householdSilenced(today)` till `placedOut` i planeringen och ger `LiveActivityDiff.actions` `householdMarked`, `householdMarkDetails` och `householdSilenced`. `handledPickups` och visningen följer `AppModel.swift:695–715`.
- [ ] **Steg 4:** Kör `./gradlew :core:test` i båda tidszonerna. Förväntat: grönt.
- [ ] **Steg 5:** Committa `build: Hushållet i Android-appens modell`

## Uppgift 6: Om en påminnelse ska visas

**Files:**
- Create: `core/household/HouseholdReminderCheck.kt`
- Test: `household/HouseholdReminderCheckTest.kt`

**Interfaces:**
- Consumes: uppgift 5.
- Produces: `object HouseholdReminderCheck`
  - `fun isNeeded(state: AppState, key: AddressKey): Boolean`: med i ett hushåll, adressen delas, och Tysta min påminnelse är på.
  - `suspend fun shouldShow(model: AppModel, entry: PlacedOut, limit: Duration = 4.seconds): Boolean`: hämtar ändringarna inom `limit` och svarar sant om inte `householdSilenced` då har tömningen. Vid fel eller tidsgräns används det senast kända.

- [ ] **Steg 1: Skriv tester som misslyckas:** `nagonHarStalltUtDoljer`, `ingenHarStalltUtVisar`, `natfelVisar`, `tidsgransenVisar` (virtuell tid), `kandBockUtanNatDoljer`, `avstangtValBehoverIngenKontroll`, `egenAdressBehoverIngenKontroll`, `angradBockVisar`.
- [ ] **Steg 2–4:** Kör, implementera, kör `./gradlew :core:test`. Förväntat: grönt.
- [ ] **Steg 5:** Committa `build: Kontroll av hushållet före en påminnelse`. Gör PR:en för kärnan.

---

# PR 2: Appen

## Uppgift 7: Koppla in synken, länkarna och säkerhetskopian

**Files:**
- Modify: `app/SophamtningApplication.kt`, `AppDependencies.kt`, `MainActivity.kt`, `navigation/AppLink.kt`, `reminders/NotificationChannels.kt`, `reminders/AndroidNotifications.kt`, `AndroidManifest.xml`, `res/values/strings.xml`, `res/xml/data_extraction_rules.xml`
- Test: `MainActivityTest.kt`, `household/InviteLinkTest.kt`, `reminders/BackupRulesTest.kt`, `AndroidNotificationsTest.kt`

**Interfaces:**
- Consumes: uppgift 4 och 5.
- Produces:
  - `SophamtningApplication` skapar `RelayHouseholdSync`, ger den till `AppModel` och anropar `startHousehold()`. `MainActivity.onStart`/`onStop` kör `startSignals()`/`stopSignals()`, och `onStart` också `fetchHouseholdChanges()`.
  - `AppLink.Invite(link)` ur en `ACTION_VIEW` med `https://sopor.hardyson.se/hushall`. En ogiltig länk öppnar hemskärmen.
  - Kanalen `NotificationChannels.HOUSEHOLD = "hushall"`, namnet "Hushåll", standardvikt. `deliverNow` väljer den när identifieraren börjar med `hushall.`.

- [ ] **Steg 1: Skriv tester som misslyckas:** `lankenGerInbjudan`, `ogiltigLankOppnarHem`, `lankenSparasInteIInstansen` (återskapad aktivitet följer inte länken igen), `hushallsnotisAnvanderEgenKanal`, `kallmeddelandeAnvanderSinKanal`, `synkenArBaraUppkoppladNarAppenSyns`, och i `BackupRulesTest` att undantagen nu också har `file:Sophamtning/household-device.json`.
- [ ] **Steg 2:** Kör `./gradlew :app:testDebugUnitTest`. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera. Manifestets filter: `android:autoVerify="true"`, `VIEW`, `DEFAULT`, `BROWSABLE`, `https`, `sopor.hardyson.se`, `android:path="/hushall"`. OkHttp-motorn får `pingInterval` 30 sekunder, eftersom Ktors egen inställning inte gäller OkHttp.
- [ ] **Steg 4:** Kör tester, lint och bygge. Förväntat: grönt.
- [ ] **Steg 5:** Committa `build: Android-appen använder brevlådan för hushåll`

## Uppgift 8: Push med FCM

**Files:**
- Create: `app/household/HouseholdPush.kt`, `HouseholdMessagingService.kt`, `HouseholdFetchWorker.kt`
- Modify: `gradle/libs.versions.toml`, `app/build.gradle.kts`, `AndroidManifest.xml`, `res/xml/data_extraction_rules.xml`, `.github/workflows/release.yml`, `app/proguard-rules.pro` (bara om R8 kräver det)
- Test: `household/HouseholdPushTest.kt`, `HouseholdMessagingServiceTest.kt`, `ReleaseConfigTest.kt`

**Interfaces:**
- Consumes: `HouseholdMembership.registerDevice`/`unregisterDevice`, `AppModel.wantsUrgentPush()`.
- Produces:
  - `interface PushRegistration { suspend fun register(); suspend fun unregister() }`, med `FirebasePushRegistration` (`FirebaseMessaging.register()`, `unregister()` och sedan `FirebaseInstallations.delete()`) och `DisabledPushRegistration` när `FirebaseApp.getApps(context)` är tom.
  - `class HouseholdPush(model, membership, registration, scope)` med `observe()`: `register()` när `inHousehold` blir sant och vid varje start som medlem, `unregister()` när det blir falskt, och `registerDevice(fid, urgent)` igen när `wantsUrgentPush()` ändras.
  - `HouseholdMessagingService`: `onRegistered(installationId)` ger `registerDevice`, och `onMessageReceived` med nyckeln `h` hämtar i högst 8 sekunder. `onDeletedMessages` hämtar också. `onNewToken` används inte.
  - `HouseholdFetchWorker`: unikt engångsarbete `hushall-hamta` (`ExistingWorkPolicy.KEEP`), kräver nät.

- [ ] **Steg 1:** Lägg till `firebase-bom` 35.2.0 och `firebase-messaging` i versionskatalogen och i `app`. Inget Google-plugin. `buildFeatures.resValues = true`. De fyra resurserna (`google_app_id`, `gcm_defaultSenderId`, `google_api_key`, `project_id`) skapas med `resValue` ur Gradle-egenskaperna eller miljövariablerna `SOPHAMTNING_FIREBASE_APP_ID`, `_SENDER_ID`, `_API_KEY` och `_PROJECT_ID`. Saknas någon skapas ingen av dem. `CheckReleaseSigning` får samma kontroll för dem, utom med `-Psigning=debug`.
- [ ] **Steg 2:** Manifestet: `firebase_messaging_auto_init_enabled` = `false`, `firebase_messaging_installation_id_enabled` = `true`, `firebase_analytics_collection_deactivated` = `true`, och tjänsten med `com.google.firebase.MESSAGING_EVENT`, `exported="false"`.
- [ ] **Steg 3: Skriv tester som misslyckas** (med falsk `PushRegistration`):
  - `utanHushallRegistrerasInget`, `medlemRegistreras`, `lamnatHushallAvregistreras`, `failedAvregistrerarInte`
  - `urgentSkickasNarValetAndras`
  - `pushForMittHushallHamtar`, `pushForAnnatHushallGorInget`, `pushUtanHushallGorInget`
  - `misslyckadHamtningLaggerInArbetet`
  - `utanFirebaseFungerarHushallet`: utan resurserna startar appen, `DisabledPushRegistration` används och inget fel visas.
  - `misslyckadRegistreringVisarInget`: `register()` kastar (inga Google Play-tjänster).
  - I `ReleaseConfigTest`: `manifestetStangerAvAutomatiskRegistrering`, `ingetGooglePlugin`.
- [ ] **Steg 4:** Kör. Förväntat: misslyckas.
- [ ] **Steg 5:** Implementera. Tjänstens trådar hoppar till huvudtråden för modellen. `Task` väntas in med en egen `suspendCancellableCoroutine`, så att inget mer bibliotek behövs.
- [ ] **Steg 6:** Starta appen i en emulator med Google Play och riktiga värden, gå med i ett hushåll och lista filerna i `files/`, `no_backup/` och `shared_prefs/` (`adb shell run-as`). De som Firebase skapade och som säkerhetskopieras (minst `com.google.android.gms.appid.xml` och `com.google.firebase.messaging.xml`) läggs som undantag i `data_extraction_rules.xml` och i `BackupRulesTest`.
- [ ] **Steg 7:** `release.yml`: de fyra variablerna från miljön `googleplay` skickas till Android-bygget.
- [ ] **Steg 8:** Kör tester, lint, `assembleDebug` och `assembleRelease -Psigning=debug --no-configuration-cache`. Förväntat: grönt.
- [ ] **Steg 9:** Committa `build: Push för hushåll med FCM i Android-appen`

## Uppgift 9: Tystad påminnelse när alarmet går

**Files:**
- Modify: `app/reminders/ReminderAlarmReceiver.kt`, `AndroidNotifications.kt`
- Test: `reminders/HouseholdReminderTest.kt`, `AndroidNotificationsTest.kt`, `RescheduleTest.kt`

**Interfaces:**
- Consumes: `HouseholdReminderCheck` (uppgift 6).
- Produces:
  - `AndroidNotifications.due(store, identifier): ScheduledNotification?` läser posten utan att ta bort den, och `finishDue(context, store, entry, show: Boolean)` visar eller inte och tar sedan bort posten. `showDue` blir de två i följd när ingen kontroll behövs.
  - `ReminderAlarmReceiver.ACTION_SHOW`: behövs ingen kontroll visas notisen direkt, som i dag. Annars `goAsync()` och `ReceiverWork.launch`, där posten läses först, sedan kontrolleras hushållet, och sist `finishDue`.
  - En mängd i minnet med identifierare som kontrolleras just nu. Ett andra alarm för samma identifierare gör inget.
  - `rescheduleAll(context, store, now, needsCheck: (AddressKey) -> Boolean)`: en passerad påminnelse inom `MISSED_LIMIT` som behöver kontroll får ett nytt alarm direkt (`Alarms.set` med `now`) och ligger kvar i filen. Andra visas direkt, som i dag. `needsCheck` läser `household.json` och `household-preferences.json` från lagringen, eftersom modellen inte finns än i `onCreate`.

- [ ] **Steg 1: Skriv tester som misslyckas:**
  - `nagonHarStalltUtVisarInget`
  - `utanNatVisasPaminnelsen`
  - `omplaneringTarInteBortPaminnelsen`: hämtningen gör att `applyReminders` tar bort posten ur filen, ingen har ställt ut, och notisen visas ändå.
  - `kallstartKontrollerarHushalletForst`: `rescheduleAll` i `onCreate` visar inget för en delad adress, och mottagaren visar eller tystar.
  - `tvaAlarmGerEnNotis`
  - `egenAdressVisasDirekt`: utan `goAsync`, som i dag.
  - `missadEfterOmstartKontrolleras`
  - `undantagIKontrollenVisarPaminnelsen`
- [ ] **Steg 2–4:** Kör, implementera, kör tester, lint och bygge. Förväntat: grönt.
- [ ] **Steg 5:** Committa `build: Påminnelsen tystas när någon i hushållet har ställt ut`

## Uppgift 10: Skärmarna

**Files:**
- Create: `app/ui/household/HouseholdScreen.kt`, `HouseholdViewModel.kt`, `HouseholdDialogs.kt`
- Modify: `navigation/Keys.kt` (`data object Household : NavKey`), `AppNavigation.kt`, `ui/screens/AppScreens.kt`, `ui/settings/SettingsScreen.kt`, `ui/home/HomeScreen.kt`, `HomeCards.kt`, `PlacedOutRow.kt`, `ui/address/AddressScreen.kt`, `widget/NextPickupWidget.kt`, `widget/WidgetUpdates.kt`
- Test: `ui/HouseholdScreenTest.kt`, `HomeScreenTest.kt`, `AddressScreenTest.kt`, `AccessibilityTest.kt`, `LargeTextTest.kt`, `widget/NextPickupWidgetTest.kt`

**Interfaces:**
- Consumes: `AppState` och `AppModel` (uppgift 5), `InMemoryHouseholdSync`.

- [ ] **Steg 1: Skriv skärmtester som misslyckas**, med `InMemoryHouseholdSync`:
  - `utanNamnGarDetInteAttBjudaIn`, `bjudInOppnarDelningen` (ett `ACTION_SEND` med texten och länken)
  - `deltagarnaVisas`, `agarenTarBortDeltagare` (⋮, **Ta bort ur hushållet**, bekräfta), `medlemSerIngenMeny`
  - `gorInbjudningarOgiltiga`, `lamnaOchAvslutaBekraftas`
  - `inbjudanFragarOmAttLamna`
  - `delaMedHushalletIAdressvyn`
  - `andrasUtstalltMedAngra`, `vantandeBockVisarKlocka`
  - `radenOmNyDeltagareStangs`
  - `felVisarForsokIgen` med de delade adresserna kvar
  - Skärmen i `AccessibilityTest` och `LargeTextTest`, och "av Kim" i widgettestet.
- [ ] **Steg 2:** Kör. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera med komponenterna i `ui/components` och temat. Facit är `HouseholdSheet.swift`, `HouseholdPlaceOutRow.swift` och specens avsnitt Utseende. `WidgetUpdates.observe` ritar om också när bockar, roll eller läge ändras.
- [ ] **Steg 4:** Kör tester, lint och bygge. Förväntat: grönt.
- [ ] **Steg 5:** Skärmbilder av Hushåll (tomt, ägare, medlem, fel), hemskärmen och adressvyn, i ljust läge, mörkt läge och med största text. Jesper godkänner dem innan uppgift 11.
- [ ] **Steg 6:** Committa `build: Skärmarna för hushåll i Android-appen`

## Uppgift 11: Dokument, enhetstest och PR

**Files:**
- Modify: `CLAUDE.md`, `docs/android-google-play.md`, `docs/specs/2026-11-23-android-enhetschecklista.md`

- [ ] **Steg 1:**
  - `CLAUDE.md`: `firebase-messaging` är undantaget i reglerna, User-Agent mot brevlådan, regeln att inget registreras hos Firebase utan hushåll, och de fyra variablerna i miljön `googleplay`.
  - `docs/android-google-play.md`: engångsstegen för Firebase-projektet, API-nyckelns begränsning, fingeravtrycket för `assetlinks.json` och formuläret om datasäkerhet.
- [ ] **Steg 2:** Enhetschecklistan får fallen från specens Test: iPhone och Android i samma hushåll åt båda hållen, ett hushåll som flyttats från iCloud, Doze, flygplansläge, en återställd telefon, en telefon utan Google Play-tjänster, App Links (`adb shell pm get-app-links se.hardyson.sophamtning` visar `verified`, med ett bygge från intern testning) och att appen inte har något FID utan hushåll.
- [ ] **Steg 3:** Röktest av release-bygget efter R8 i emulatorn, med en separat kopia av appen: gå med i ett hushåll, ställ ut, ta emot push.
- [ ] **Steg 4:** Doze på en riktig telefon: `adb shell dumpsys deviceidle force-idle`, ställ ut på den andra telefonen, och anteckna i checklistan om pushen kom med notiserna på respektive av, och om kontrollen före påminnelsen hade nät. Stämmer det inte med specen: stoppa och fråga Jesper.
- [ ] **Steg 5:** Kör `./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`. Stäng emulatorn efteråt.
- [ ] **Steg 6:** Committa `docs: Hushåll på Android i checklistor och regler`, och gör PR:en för appen. Före releasen: Jesper har fyllt i datasäkerheten, integritetspolicyn är publicerad, och iOS-versionen med brevlådan är släppt.
