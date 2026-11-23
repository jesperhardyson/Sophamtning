# Google Play: Jespers steg

Det här görs för hand, en gång, innan jobbet **Google Play** i `.github/workflows/release.yml` kan ladda upp Android-appen. Efter det sköts varje release i GitHub Actions, som på iOS. Spec: `docs/specs/2026-11-23-android-app.md` (Google Play) och `docs/specs/2026-11-08-release.md` (Ändrat 2026-11-23: Google Play).

Ordningen spelar roll: appen måste ha ett första bygge som är släppt i internt test innan API:t kan ladda upp något. Play Console beskrivs med svenska menynamn. Där den svenska texten inte är bekräftad står den engelska inom parentes.

| Steg | Engång? | Läge |
|---|---|---|
| 1. Skapa appen i Play Console | Ja | Klart |
| 2. Skapa uppladdningsnyckeln | Ja (nyckeln gäller i många år, och kan bytas via Play Console om den försvinner) | |
| 3. Bygg och ladda upp det första bygget, och slå på appsignering via Play | Ja | |
| 4. Skapa tjänstkontot och ge det behörighet | Ja | |
| 5. Skapa miljön `googleplay` med godkännare och secrets | Ja (secrets byts om nyckeln eller tjänstkontot byts) | |
| 6. Prova ett testbygge från GitHub | Ja, efter att PR:en med jobbet är mergad | |
| 7. Slutet test med 12 testare i 14 dagar | Ja, innan den första releasen till produktion | |
| Appinnehåll, butiksinformation och kategori | Ja, och uppdateras när appen ändras | Klart, se checklistan längst ned |

## 1. Skapa appen (klart)

Appen Sophämtning finns i Play Console, med svenska som standardspråk och gratis. Paketnamnet bestäms inte där, utan av det första bygget i steg 3, och kan aldrig ändras efteråt. Det ska vara `se.hardyson.sophamtning`.

## 2. Skapa uppladdningsnyckeln (engång)

Uppladdningsnyckeln signerar varje AAB som laddas upp. Google signerar sedan appen med sin egen nyckel (appsignering via Play), så den här nyckeln går att byta via Play Console om den försvinner. Den ska ändå sparas säkert, och aldrig i repot. `*.jks` och `*.keystore` ignoreras av git.

Använd `keytool` från JDK 21, samma som bygget. Byt `<alias>` mot ett eget namn, till exempel `upload`:

```zsh
export JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || echo /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home)
mkdir -p ~/Nycklar
"$JAVA_HOME/bin/keytool" -genkeypair -v \
  -keystore ~/Nycklar/sophamtning-upload.jks \
  -storetype PKCS12 \
  -alias <alias> \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Sophamtning, C=SE"
```

`keytool` frågar efter ett lösenord. Med `PKCS12` har nyckeln samma lösenord som nyckelfilen, så samma lösenord används för både `SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD` och `SOPHAMTNING_UPLOAD_KEY_PASSWORD`.

Spara nyckelfilen, aliaset och lösenordet i lösenordshanteraren.

## 3. Det första bygget, för hand (engång)

API:t kan inte ladda upp till en app som aldrig har haft en version, så det första bygget laddas upp i Play Console. Det byggs lokalt med uppladdningsnyckeln, i zsh från repots rot:

```zsh
cd Android
export JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || echo /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home)
export SOPHAMTNING_UPLOAD_KEYSTORE=~/Nycklar/sophamtning-upload.jks
export SOPHAMTNING_UPLOAD_KEY_ALIAS=<alias>
read -rs 'SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD?Lösenord för uppladdningsnyckeln: '; echo
export SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD
export SOPHAMTNING_UPLOAD_KEY_PASSWORD="$SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD"
./gradlew --no-configuration-cache :app:bundleRelease -PversionCode=1 -PversionName=0.0.1
unset SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD SOPHAMTNING_UPLOAD_KEY_PASSWORD
```

- `read -rs 'VAR?text: '` är zsh: texten visas som fråga, och lösenordet syns inte och hamnar inte i skalets historik.
- `--no-configuration-cache` behövs: utan den sparas lösenorden i Gradles konfigurationscache i `Android/.gradle`.
- `versionCode` 1 är lägre än alla som jobbet räknar fram (körningens nummer × 100), så nästa uppladdning från GitHub går alltid igenom.
- Saknas en variabel stoppar bygget med ett fel som säger vilken. Ett osignerat bygge går aldrig att få fram av misstag.

Filen hamnar i `Android/app/build/outputs/bundle/release/app-release.aab`.

I Play Console, i appen Sophämtning:

1. **Testa och lansera** > **Test** > **Internt test**.
2. Fliken **Testare**: **Skapa e-postlista**, ge listan ett namn (till exempel "Jesper") och lägg till din egen Google-adress. **Spara ändringar**, och kryssa i listan.
3. **Skapa ny version**.
4. Under **Appintegritet**: kontrollera att appsignering via Play är på, med en nyckel som Google skapar (Choose signing key > Use Google-generated key). Det är förvalt för nya appar.
5. **Ladda upp** `app-release.aab`. Kontrollera att paketnamnet som visas är `se.hardyson.sophamtning`.
6. **Versionsnamn** fylls i med 0.0.1. Skriv något kort under **Nyheter i den här versionen**, till exempel "Första bygget". **Nästa**.
7. Innan versionen kan publiceras måste allt under **Appinnehåll** vara ifyllt (se avsnittet Appinnehåll och butiksinformation nedan). Det är redan gjort. Visar **Förhandsgranska och bekräfta** ändå fel om Appinnehåll, rätta dem där och kom tillbaka.
8. **Spara**, och sedan **Starta lanseringen** (eller **Publicera** i **Publiceringsöversikt**, om Play Console visar ändringarna där). Versionen måste släppas, inte bara sparas som utkast: annars är appen fortfarande ett utkast, och API:t vägrar sätta status `completed` ("Only releases with status draft may be created on draft app").
9. Kopiera länken för testare på fliken **Testare** (How testers join your test) och öppna den på telefonen för att installera.

## 4. Tjänstkontot (engång)

Tjänstkontot är den identitet som jobbet laddar upp med. Det behöver bara få släppa i testkanaler för den här appen.

I [Google Cloud Console](https://console.cloud.google.com) (menynamnen på engelska):

1. Skapa ett projekt: projektväljaren högst upp > **New project**, till exempel `sophamtning-play`. Välj det.
2. Slå på API:t: **APIs & Services** > **Library**, sök på **Google Play Android Developer API** och välj **Enable**.
3. Skapa kontot: **IAM & Admin** > **Service accounts** > **Create service account**. Namn till exempel `play-upload`. Hoppa över rollerna (**Continue** och **Done**). Projektet behöver inga roller, behörigheten ges i Play Console.
4. Skapa nyckeln: välj kontot > fliken **Keys** > **Add key** > **Create new key** > **JSON** > **Create**. En JSON-fil laddas ned. Spara den i lösenordshanteraren.
5. Kopiera kontots e-postadress (`play-upload@<projekt>.iam.gserviceaccount.com`).

I [Play Console](https://play.google.com/console), på kontonivå (inte i appen):

1. **Användare och behörigheter** > **Bjud in nya användare**.
2. **E-postadress:** tjänstkontots adress.
3. **Kontobehörigheter:** kryssa inte i något.
4. **Appbehörigheter:** lägg till appen Sophämtning (Add app) och kryssa i:
   - **Publicera appar i testkanaler**: det är behörigheten som låter jobbet släppa en version i internt test.
   - **Visa appinformation (skrivskyddat)**

   Inget om produktionskanalen, ekonomi eller användare. Jesper flyttar själv versioner till produktion.
5. **Bjud in användare** och bekräfta. Ett tjänstkonto behöver inte godkänna inbjudan.

Det kan ta upp till ett dygn innan behörigheten gäller. Fram till dess kan jobbet ge `HTTP 403: The caller does not have permission`. Att länka Play Console till Google Cloud-projektet under API-åtkomst behövs inte längre.

## 5. Miljön `googleplay` i GitHub (engång)

Miljön håller secrets och kräver Jespers godkännande innan jobbet kör, som `testflight`.

1. På GitHub: repot > **Settings** > **Environments** > **New environment**, namn `googleplay` > **Configure environment**.
2. **Deployment protection rules:** kryssa i **Required reviewers** och lägg till `jesperhardyson`. Lämna **Prevent self-review** av, eftersom Jesper både startar och godkänner. **Save protection rules**.
3. **Deployment branches and tags:** **Selected branches and tags** > **Add deployment branch or tag rule**: `main`. Bara `main`: testbyggen görs från `main` efter att en PR är mergad.

Secrets läggs in från en terminal i repot med `gh`. Båda filerna är base64-kodade, som `ASC_KEY_P8`. Kommandon utan `--body` frågar efter värdet, som då inte syns och inte hamnar i historiken:

```zsh
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

## 6. Prova ett testbygge (engång, efter att PR:en är mergad)

Jobbet finns på `main` först när PR:en med Google Play-releaserna är mergad, och miljön tillåter bara `main`.

1. Actions > Release > **Run workflow**. Välj grenen `main`, **app** `android` och lämna taggen tom.
2. Godkänn `googleplay` när jobbet väntar.
3. Förväntat: ett testbygge med `versionName` 0.0.1 i internt test, med "Testbygge från main (…)" som "Nyheter i den här versionen".

Ger jobbet `HTTP 403`, vänta ett dygn på tjänstkontots behörighet (steg 4) och kör igen. Säger felet att ändringar måste skickas för granskning, öppna **Publiceringsöversikt**, skicka ändringarna och kör igen.

## 7. Slutet test med 12 testare i 14 dagar (engång, före produktion)

Ett personligt utvecklarkonto som skapades efter november 2023 måste ha ett slutet test med minst 12 testare som har varit med i 14 dagar i följd innan appen kan släppas i produktion. Play Console visar på appens **Översikt** om kravet gäller kontot.

1. **Testa och lansera** > **Test** > **Slutet test**. Skapa en kanal, eller använd den som finns (Closed testing - Alpha).
2. Fliken **Testare:** **Skapa e-postlista** med minst 12 Google-adresser (eller en Google-grupp) och kryssa i den. **Spara ändringar**.
3. Flytta en version dit: i **Internt test**, flytta upp versionen till slutet test (Promote release > Closed testing). **Förhandsgranska och bekräfta** och **Starta lanseringen**. Det slutna testet granskas av Google, vilket kan ta några dagar.
4. Skicka länken för testare (How testers join your test) till testarna. Varje testare ska tacka ja och installera appen.
5. Efter 14 dagar med minst 12 testare: ansök om produktionsåtkomst från appens **Översikt** (Apply for production access) och svara på frågorna om testet.

Nya versioner till det slutna testet flyttas på samma sätt från internt test. Jobbet i GitHub laddar bara upp till internt test.

## Appinnehåll och butiksinformation (klart)

Allt är ifyllt. Listan är till för att bocka av när appen ändras, inte för att göras om. Det finns under **Policy och program** > **Appinnehåll** (Policy and programs > App content), längst ned i appens vänstermeny. Svaren följer App Privacy för iOS i `docs/specs/2026-11-06-app-store.md`, som bygger på integritetspolicyn. Stämmer något inte med policyn ändras svaren, inte policyn.

- [x] **Integritetspolicy:** `https://sopor.hardyson.se/integritet`
- [x] **Appåtkomst:** alla funktioner är tillgängliga utan särskild åtkomst. Appen har inga konton.
- [x] **Annonser:** appen innehåller inga annonser.
- [x] **Innehållsklassificering:** frågeformuläret är besvarat.
- [x] **Målgrupp och innehåll:** 13 år och äldre.
- [x] **Annonserings-id:** nej, appen använder inte annonserings-id. Om en ny version någonsin får ett bibliotek som lägger till behörigheten `com.google.android.gms.permission.AD_ID` måste svaret ändras.
- [x] **Myndighetsappar:** nej. Appen är inofficiell och inte gjord av eller för en myndighet.
- [x] **Ekonomiska funktioner** och **Hälsa:** inga.
- [x] **Datasäkerhet:** samma utgångspunkt som på iOS. Söktexten och den valda adressen skickas till Sopors API, och serverns loggar sparas i en timme och svaren i en cache i högst åtta dygn.
  - Data samlas in: ja. Krypteras vid överföring: ja (bara HTTPS).
  - **Adress** (Personliga uppgifter) och **Sökhistorik i appen** (Appaktivitet): insamlad, inte delad, inte tillfälligt behandlad, obligatorisk, för appens funktioner.
  - Raderas automatiskt inom 90 dagar. Appen har inga konton, så det finns inget att begära radering av.
  - Inga andra typer: inte plats, inte identifierare, inte kraschloggar eller diagnostik. Appen har ingen analys och ingen kraschrapportering.
- [x] **Status som näringsidkare** (trader status) är angiven.
- [x] **Butiksinformation:** texter, skärmbilder och funktionsgrafik. Kategori **Hus och hem**.

Ändras appen så att något av svaren inte stämmer, till exempel en ny datatyp eller ett nytt bibliotek, uppdateras listan och Play Console innan versionen släpps.

## Efter engångsstegen

- **Release:** mergar Jesper release-PR:en för `android` startar jobbet **Google Play** i samma körning. Det väntar på godkännande i `googleplay`, bygger en signerad AAB och laddar upp den till internt test med versionens avsnitt ur changelogen som "Nyheter i den här versionen" (`sv-SE`, ren text, högst 500 tecken, kortad vid en hel rad). Texten kan skrivas om i Play Console.
- **Ladda upp igen:** Actions > Release > Run workflow, grenen `main`, **app** `android` och taggen, till exempel `android-v1.0.0`.
- **Testbygge:** samma, med tomt taggfält. Det får nästa patchversion efter `Android/version.txt`, och ingen fil i repot ändras.
- **Tillfälliga fel:** ett HTTP-fel 5xx eller ett nätfel prövas en gång till av skriptet. Fallerar det igen stoppar jobbet utan att något ändras i Play Console, och körningen kan göras om.
- **Produktion:** Jesper flyttar själv en version från internt test till slutet test eller produktion i Play Console.
- **Kraschrapporter:** varje körning sparar AAB:n och `mapping.txt` som artefakt i 30 dagar. Ladda upp `mapping.txt` på versionen i App bundle explorer (fliken Downloads, ReTrace mapping file) om en krasch i Play Console behöver läsas med klassnamn.
