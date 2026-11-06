# Test av schemalagd Live Activity

**Datum:** 2026-11-06
**Enhet:** iPhone 17 Pro med iOS 27.0.1 (24A446)
**Kod:** en engångsapp med `Activity.request(attributes:content:pushType:style:alertConfiguration:start:)`, `pushType: nil` och `style: .standard`. Appen är inte committad.

Testet körs enligt uppgift 1 i `docs/plans/2026-11-06-ios-app.md`. Starttiden låg tre minuter fram i tiden. Varje fall kördes en gång.

## Resultat

| # | Fråga | Svar |
|---|---|---|
| 1 | Startar en schemalagd aktivitet när appen är avslutad och telefonen låst? | **Ja.** Aviseringen hördes och kändes. Skärmen tändes däremot inte av sig själv, utan aktiviteten syntes när skärmen tändes vid beröring |
| 2 | Går det att ta bort en aktivitet i läget `pending`? | **Ja.** `end(nil, dismissalPolicy: .immediate)` gav före 1, efter 0, och aktiviteten dök inte upp efter fyra minuter |
| 3 | Hur beter sig aviseringen när notiser är nekade? | **Aktiviteten startar, och ljudet hörs ändå.** Vi har inte testat om en banner visas |
| 4 | Hur många schemalagda aktiviteter accepteras? | **Minst 5.** Fem av fem lyckades utan fel. I simulatorn med iOS 26 gav det sjätte försöket, och i praktiken det femte i det försöket, felet `targetMaximumExceeded`, med fem samtidigt |
| 5 | Visas innehållet korrekt, och fungerar knappen, när appen är avslutad? | **Ja.** Låsskärm, kompakt och större Dynamic Island visades. Knappen med `LiveActivityIntent` avslutade aktiviteten utan att appen öppnades |

## Konsekvenser

Designen i `docs/specs/2026-11-06-ios-app.md` håller, och specen ändras inte.

- **Ingen server behövs.** Schemalagd start, borttagning och knappen fungerar på telefonen.
- **Ändrat schema:** en väntande aktivitet tas bort och läggs in på nytt, som specen beskriver.
- **Opt-in:** Live Activity och notiser är oberoende av varandra, eftersom aktiviteten startar även med nekade notiser. Texten vid valet ska säga att starten aviseras med ljud.
- **Samspel med notis:** beslutet att hoppa över den vanliga notisen för samma tömning står kvar, eftersom aktiviteten aviserar med ljud och vibration.

## Det som inte är testat

- **Skärmen som inte tändes.** Det observerades en gång. Vi vet inte om det alltid är så, eller hur det skiljer sig från en vanlig notis. Det kontrolleras i enhetschecklistan i uppgift 15, och beslutet om notisen omprövas om användare riskerar att missa påminnelsen.
- **iOS 26 på riktig telefon.** Appens lägsta version är iOS 26, men testet kördes på iOS 27.0.1. API:t finns enligt Apple från iOS 26.0.
- **En natt.** Tid och gränsen på 12 timmar är inte testade, och inte heller en längre tid mellan schemaläggning och start. Det ingår också i uppgift 15.
- **Tidigare nekad notis.** En äldre installation fick direkt svaret nekat utan dialog. En ny installation med nytt bundle-id fick dialogen. Orsaken bekräftades inte, men pekar på ett tidigare val knutet till det gamla id:t.
