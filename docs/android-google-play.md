# Google Play: Jespers steg

Det här görs för hand, en gång, innan jobbet **Google Play** i `.github/workflows/release.yml` kan ladda upp Android-appen. Efter det sköts varje release i GitHub Actions, som på iOS. Spec: `docs/specs/2026-11-23-android-app.md` (Google Play) och `docs/specs/2026-11-08-release.md` (Ändrat 2026-11-23: Google Play).

Ordningen spelar roll: appen måste finnas i Play Console och ha ett första bygge som är släppt i intern testning innan API:t kan ladda upp något. Play Console visas här med engelska menynamn. På svenska ligger de på samma ställen.

| Steg | Engång? |
|---|---|
| 1. Skapa appen i Play Console | Ja |
| 2. Skapa uppladdningsnyckeln | Ja (nyckeln gäller i många år, och kan bytas via Play Console om den försvinner) |
| 3. Bygg och ladda upp det första bygget, och slå på Play App Signing | Ja |
| 4. Skapa tjänstkontot och ge det behörighet | Ja |
| 5. Skapa miljön `googleplay` med godkännare och secrets | Ja (secrets byts om nyckeln eller tjänstkontot byts) |
| 6. Slutet test med 12 testare i 14 dagar | Ja, innan den första releasen till produktion |
| 7. Datasäkerhet, åldersgräns och integritetspolicy | Ja, och uppdateras när appen ändras |

## 1. Skapa appen (engång)

1. Öppna [Play Console](https://play.google.com/console) och välj **Home** > **Create app**.
2. Fyll i:
   - **App name:** Sophämtning
   - **Default language:** Swedish – sv-SE
   - **App or game:** App
   - **Free or paid:** Free (det går inte att ändra till betald senare)
3. Kryssa i deklarationerna (Developer Program Policies och US export laws) och välj **Create app**.

Paketnamnet bestäms inte här, utan av det första bygget i steg 3, och kan aldrig ändras efteråt. Det ska vara `se.hardyson.sophamtning`.

## 2. Skapa uppladdningsnyckeln (engång)

Uppladdningsnyckeln signerar varje AAB som laddas upp. Google signerar sedan appen med sin egen nyckel (Play App Signing), så den här nyckeln går att byta via Play Console om den försvinner. Den ska ändå sparas säkert, och aldrig i repot. `*.jks` och `*.keystore` ignoreras av git.

Byt `<alias>` mot ett eget namn, till exempel `upload`:

```bash
mkdir -p ~/Nycklar
keytool -genkeypair -v \
  -keystore ~/Nycklar/sophamtning-upload.jks \
  -storetype PKCS12 \
  -alias <alias> \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Sophamtning, C=SE"
```

`keytool` frågar efter ett lösenord. Med `PKCS12` har nyckeln samma lösenord som nyckelfilen, så samma lösenord används för både `SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD` och `SOPHAMTNING_UPLOAD_KEY_PASSWORD`.

Spara nyckelfilen, aliaset och lösenordet i lösenordshanteraren.

## 3. Det första bygget, för hand (engång)

API:t kan inte ladda upp till en app som aldrig har haft en version, så det första bygget laddas upp i Play Console. Det byggs lokalt med uppladdningsnyckeln:

```bash
cd Android
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export SOPHAMTNING_UPLOAD_KEYSTORE=~/Nycklar/sophamtning-upload.jks
export SOPHAMTNING_UPLOAD_KEY_ALIAS=<alias>
read -rs SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD && export SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD
export SOPHAMTNING_UPLOAD_KEY_PASSWORD="$SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD"
./gradlew --no-configuration-cache :app:bundleRelease -PversionCode=1 -PversionName=0.0.1
```

- `read -rs` läser lösenordet utan att det syns eller hamnar i skalets historik.
- `--no-configuration-cache` gör att lösenorden inte sparas i Gradles cache i `Android/.gradle`.
- `versionCode` 1 är lägre än alla som jobbet räknar fram (körningens nummer × 100), så nästa uppladdning från GitHub går alltid igenom.
- Saknas en variabel stoppar bygget med ett fel som säger vilken. Ett osignerat bygge går aldrig att få fram av misstag.

Filen hamnar i `Android/app/build/outputs/bundle/release/app-release.aab`.

I Play Console:

1. Välj appen och sedan **Test and release** > **Testing** > **Internal testing**.
2. Fliken **Testers**: välj **Create email list**, ge listan ett namn (till exempel "Jesper") och lägg till din egen Google-adress. Spara, och kryssa i listan.
3. Välj **Create new release**.
4. Under **App integrity** (Play App Signing): välj **Choose signing key** > **Use Google-generated key**, om det inte redan är valt. Det slår på Play App Signing.
5. Ladda upp `app-release.aab` under **App bundles**. Kontrollera att paketnamnet som visas är `se.hardyson.sophamtning`.
6. **Release name** fylls i med 0.0.1. Skriv något kort under **Release notes**, till exempel "Första bygget".
7. Välj **Next** och sedan **Save and publish** (eller **Start rollout to Internal testing**). Versionen måste släppas, inte bara sparas som utkast: annars är appen fortfarande ett utkast, och API:t vägrar sätta status `completed` ("Only releases with status draft may be created on draft app").
8. Ber Play Console om uppgifter under **App content** innan versionen kan släppas, gör steg 7 först.
9. Kopiera länken under **How testers join your test** och öppna den på telefonen för att installera.

## 4. Tjänstkontot (engång)

Tjänstkontot är den identitet som jobbet laddar upp med. Det behöver bara få släppa i testspår för den här appen.

I [Google Cloud Console](https://console.cloud.google.com):

1. Skapa ett projekt: projektväljaren högst upp > **New project**, till exempel `sophamtning-play`. Välj det.
2. Slå på API:t: **APIs & Services** > **Library**, sök på **Google Play Android Developer API** och välj **Enable**.
3. Skapa kontot: **IAM & Admin** > **Service accounts** > **Create service account**. Namn till exempel `play-upload`. Hoppa över rollerna (**Continue** och **Done**). Projektet behöver inga roller, behörigheten ges i Play Console.
4. Skapa nyckeln: välj kontot > fliken **Keys** > **Add key** > **Create new key** > **JSON** > **Create**. En JSON-fil laddas ned. Spara den i lösenordshanteraren.
5. Kopiera kontots e-postadress (`play-upload@<projekt>.iam.gserviceaccount.com`).

I [Play Console](https://play.google.com/console):

1. **Users and permissions** (i vänstermenyn på kontonivå, inte i appen) > **Invite new users**.
2. **Email address:** tjänstkontots adress.
3. Fliken **Account permissions:** kryssa inte i något.
4. Fliken **App permissions:** **Add app** > Sophämtning > **Apply**. Kryssa i:
   - **Release apps to testing tracks**
   - **View app information and download bulk reports (read-only)**

   Inget om produktion, ekonomi eller användare. Jesper flyttar själv versioner till produktion.
5. **Invite user** och bekräfta. Ett tjänstkonto behöver inte godkänna inbjudan.

Det kan ta upp till ett dygn innan behörigheten gäller. Fram till dess kan jobbet ge `HTTP 403: The caller does not have permission`. Att länka Play Console till Google Cloud-projektet under API access behövs inte längre.

## 5. Miljön `googleplay` i GitHub (engång)

Miljön håller secrets och kräver Jespers godkännande innan jobbet kör, som `testflight`.

1. På GitHub: repot > **Settings** > **Environments** > **New environment**, namn `googleplay` > **Configure environment**.
2. **Deployment protection rules:** kryssa i **Required reviewers** och lägg till `jesperhardyson`. Lämna **Prevent self-review** av, eftersom Jesper både startar och godkänner. **Save protection rules**.
3. **Deployment branches and tags:** **Selected branches and tags** > **Add deployment branch or tag rule**: `main`. Lägg till `feature/*` och `fix/*` om testbyggen från PR-grenar ska gå, som i `testflight`.

Secrets läggs in från en terminal i repot med `gh`. Båda filerna är base64-kodade, som `ASC_KEY_P8`. Kommandon utan `--body` frågar efter värdet, som då inte syns och inte hamnar i historiken:

```bash
base64 -i ~/Nycklar/sophamtning-upload.jks | gh secret set SOPHAMTNING_UPLOAD_KEYSTORE --env googleplay
gh secret set SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD --env googleplay
gh secret set SOPHAMTNING_UPLOAD_KEY_ALIAS --env googleplay --body '<alias>'
gh secret set SOPHAMTNING_UPLOAD_KEY_PASSWORD --env googleplay
base64 -i ~/Downloads/<tjänstkontots-fil>.json | gh secret set PLAY_SERVICE_ACCOUNT_JSON --env googleplay
gh secret list --env googleplay
```

`SOPHAMTNING_UPLOAD_KEY_PASSWORD` är samma lösenord som `SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD` (se steg 2). Ta bort JSON-filen från Hämtade filer när den finns i lösenordshanteraren.

| Secret | Innehåll |
|---|---|
| `SOPHAMTNING_UPLOAD_KEYSTORE` | Uppladdningsnyckelns `.jks`-fil, base64-kodad |
| `SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD` | Nyckelfilens lösenord |
| `SOPHAMTNING_UPLOAD_KEY_ALIAS` | Nyckelns alias |
| `SOPHAMTNING_UPLOAD_KEY_PASSWORD` | Nyckelns lösenord, samma som filens med `PKCS12` |
| `PLAY_SERVICE_ACCOUNT_JSON` | Tjänstkontots JSON-nyckel, base64-kodad |

Saknas någon stoppar jobbet med ett fel som räknar upp de som saknas.

**Prova:** Actions > Release > **Run workflow**, välj grenen `main`, **app** `android` och lämna taggen tom. Godkänn `googleplay`. Förväntat: ett testbygge med `versionName` 0.0.1 i intern testning, med "Testbygge från main (…)" som "Vad är nytt".

## 6. Slutet test med 12 testare i 14 dagar (engång, före produktion)

Ett personligt utvecklarkonto som skapades efter november 2023 måste ha ett slutet test med minst 12 testare som har varit med i 14 dagar i följd innan appen kan släppas i produktion. Play Console visar på **Dashboard** om kravet gäller kontot.

1. **Test and release** > **Testing** > **Closed testing** > **Create track**, eller använd spåret **Closed testing - Alpha** som finns.
2. Fliken **Testers:** skapa en e-postlista med minst 12 Google-adresser (eller en Google-grupp) och kryssa i den. Spara.
3. Flytta en version dit: i **Internal testing**, välj **Promote release** > **Closed testing** på versionen. Granska och släpp. Det slutna testet granskas av Google, vilket kan ta några dagar.
4. Skicka länken under **How testers join your test** till testarna. Varje testare ska tacka ja och installera appen.
5. Efter 14 dagar med minst 12 testare: **Dashboard** > **Apply for production access** och svara på frågorna om testet.

Nya versioner till det slutna testet flyttas på samma sätt från intern testning. Jobbet i GitHub laddar bara upp till intern testning.

## 7. Datasäkerhet, åldersgräns och integritetspolicy (engång, och vid ändringar)

Allt finns under **Policy and programs** > **App content** (i appen, längst ned i vänstermenyn). Svaren följer App Privacy för iOS i `docs/specs/2026-11-06-app-store.md`, som bygger på integritetspolicyn. Stämmer något inte med policyn ändras svaren, inte policyn.

- **Privacy policy:** `https://sopor.hardyson.se/integritet`
- **App access:** All functionality is available without special access. Appen har inga konton.
- **Ads:** No, my app does not contain ads.
- **Content rating:** fyll i frågeformuläret (IARC). E-post: din adress. Kategori: **All Other App Types** (eller **Utility, Productivity, Communication, or Other** om den visas). Svara nej på alla frågor om våld, sex, språk, droger, spel om pengar och användarinteraktion. Appen har ingen chatt och delar inte plats. Förväntat: 3+ (PEGI 3).
- **Target audience and content:** **18 and over**. Appen är inte gjord för barn, och ett yngre åldersspann gör att Familjepolicyn och fler krav gäller. Svara nej på att appen kan locka barn.
- **News apps:** No.
- **Government apps:** No. Appen är inofficiell och inte gjord av eller för en myndighet.
- **Financial features**, **Health apps**, **Data safety for health**: inga.
- **Data safety:** samma utgångspunkt som på iOS. Söktexten och den valda adressen skickas till Sopors API, och serverns loggar sparas i en timme och svaren i en cache i högst åtta dygn. Därför:
  - **Does your app collect or share any of the required user data types?** Yes.
  - **Is all of the user data collected by your app encrypted in transit?** Yes (bara HTTPS).
  - **Do you provide a way for users to request that their data is deleted?** No. Appen har inga konton, och loggarna rensas av sig själva.
  - Datatyper som samlas in: **Personal info** > **Address** och **App activity** > **In-app search history**. För båda: **Collected** ja, **Shared** nej, **Processed ephemerally** nej (loggarna sparas en timme), **Required**, ändamål **App functionality**.
  - Inga andra typer: inte plats, inte identifierare, inte kraschloggar eller diagnostik. Appen har ingen analys och ingen kraschrapportering.

Planen sa "inga data samlas in", men det vore ett påstående som policyn inte stöder, och svaren ska vara desamma som för iOS. Vill Jesper svara annorlunda ändras både iOS-svaren och de här.

## Efter engångsstegen

- **Release:** mergar Jesper release-PR:en för `android` startar jobbet **Google Play** i samma körning. Det väntar på godkännande i `googleplay`, bygger en signerad AAB och laddar upp den till intern testning med versionens avsnitt ur changelogen som "Vad är nytt" (`sv-SE`, ren text, högst 500 tecken, kortad vid en hel rad). Texten kan skrivas om i Play Console.
- **Ladda upp igen:** Actions > Release > Run workflow, **app** `android` och taggen, till exempel `android-v1.0.0`.
- **Testbygge:** samma, med tomt taggfält och en gren vald. Det får nästa patchversion efter `Android/version.txt`, och ingen fil i repot ändras.
- **Produktion:** Jesper flyttar själv en version från intern testning till slutet test eller produktion i Play Console, med **Promote release**.
- **Kraschrapporter:** varje körning sparar AAB:n och `mapping.txt` som artefakt i 30 dagar. Ladda upp `mapping.txt` under **App bundle explorer** > versionen > **Downloads** > **ReTrace mapping file** om en krasch i Play Console behöver läsas med klassnamn.
