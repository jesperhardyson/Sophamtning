# Android: checklista för en riktig telefon

Fall som enhetstesterna inte kan pröva, eftersom de kräver systemets alarm, notiser och omstart. Motsvarar `2026-11-06-enhetschecklista.md` för iOS. Fyll i datum, enhet och resultat varje gång listan körs.

## 2026-11-23, emulator Pixel 9 Pro, Android 17 (API 37), Google Play

Adressen är ett område i Avesta (trakt 2), med nästa tömning tisdag 1 december. Påminn mig kvällen före kl. 18:00 och Live Update kl. 18:00 är på, och notiser är tillåtna.

| Fall | Resultat |
|---|---|
| Alarmen läggs in när påminnelsen slås på (`dumpsys alarm`) | Ja. Live Update 30 nov 18:00, och reservnotisen 18:45, eftersom notisen och Live Update har samma tid. |
| Exakta alarm inte tillåtna | Fönster på 10 minuter (`window=+10m`). |
| Exakta alarm tillåts (`appops`) | Alarmen läggs in igen som exakta (`window=0`) utan att appen öppnas. |
| Klockan flyttas till 17:59:30 kvällen före | Live Update visas 18:00:00 med flaggan `PROMOTED_ONGOING`, chippet "🗑 Tis" i statusfältet, och titel, text och **Klart** i notislistan. |
| **Klart** i Live Update | Bocken "Kärlen är utställda" visas och försvinner efter 3 s. Utställt sparas med tid, och reservnotisen tas bort. |
| Omstart (`adb reboot`) | Alarmen för nästa tömning (14 dec) finns kvar efter omstarten, utan att appen öppnas. |
| Bakgrundsarbetet | Schemalagt med villkoret nät och en period på 3 timmar. Gick inte att tvinga fram efter flyttad klocka, eftersom WorkManager räknar om schemat vid omstart och tidsbyte. Logiken prövas i `RefreshWorkerTest`. |

## 2026-11-23, plan 6, samma emulator

Provat med en separat kopia av appen (`se.hardyson.sophamtning.prov`), så att data i den riktiga appen inte rördes.

| Fall | Resultat |
|---|---|
| Liten widget (2×2) vid 100, 130 och 200 % text | Namnet, "I morgon", datumet och kärlen ryms, och inget klipps. |
| Mellanstor widget (4×2) med Ställ ut kvällen före | Två kärl och knappen vid 100 %. Vid 130 och 200 % visas det första kärlet, knappen och "+1 till", och vid 200 % får veckodagen och namnet "…". |
| Tryck på widgeten utanför knappen | Adressvyn öppnas. |
| Förhandsvisning i widgetgalleriet | Visas. |
| Genvägen Lägg till adress | Öppnar sökningen, också när appen redan är igång. |
| Rutan i snabbinställningarna | Kan läggas till. Den är avstängd när tömningen är mer än en dag bort. |
| Kalenderbladet | Bläddrar när appen startar. |

Inte provat här: den mellanstora widgeten i sin lägsta storlek (240 × 100 dp), eftersom en widget på 4×2 i den här emulatorn är cirka 220 dp hög. Den storleken prövas i `WidgetLayoutTest`. Inte heller rutan efter tryck, eller widgeten när klockan går över midnatt.

## 2026-11-23, plan 7, release-bygget efter R8, samma emulator

Release-bygget (`assembleRelease -Psigning=debug`, med R8 och borttagna resurser) installerades som en separat kopia (`se.hardyson.sophamtning.prov`, via ett init-skript som inte committas), så att data i den riktiga appen inte rördes. Kopian avinstallerades efteråt. R8 krävde inga `-dontwarn`-regler.

| Fall | Resultat |
|---|---|
| Sök adress ("Storgatan", "Kungsgatan") | Träffar, områden och felraden "Alla källor svarade inte" visas. Avkodningen fungerar. |
| Spara en adress, med Påminn mig | Sparas och visas på hemskärmen med påminnelsen. Frågan om notiser kommer först efter Påminn mig. |
| Adressvyn | Nästa tömning, Kommande, Per kärl, Påminnelser, Kalender och ansvarig visas. |
| Ställ ut kärlen, Utställt och Ångra | Utställt med "av dig · kl. 15:58", Ångra tar bort det, och hemskärmen visar "Kärlen är utställda". |
| Appen dödas i bakgrunden (`am kill`) och öppnas igen | Adressvyn återställs. Navigationens nycklar avkodas efter R8. |
| Inställningarna | Notiser, Live Update, Huvudadress, Datakällor (53), Version och Nyheter öppnas. |
| Widgeten, liten och mellan | Visas med huvudadressen. Knappen Ställ ut kärlen i den mellanstora widgeten ger "Utställda" (Glance skapar `PlaceOutAction` efter R8). |

Inte provat här: rutan i snabbinställningarna, Live Update och påminnelser som kommer, eftersom de inte påverkas av R8 på annat sätt än det som provats ovan.

## Kvar att pröva på en riktig telefon

- En påminnelse som kommer av sig själv, utan flyttad klocka, med telefonen låst och i viloläge (Doze).
- Utställt i notisen med appen dödad.
- Live Update på låsskärmen. Notisen har synligheten `PRIVATE`, så innehållet kan döljas på en låst skärm med skyddat innehåll.
- Bakgrundshämtningen efter några timmar, och notisen om ett nytt källmeddelande från bakgrunden.
- Byte av tidszon i systemets inställningar.
- Kontrast och TalkBack i hela appen.
- Widgeten och rutan efter tvångsstopp och över midnatt, och rutan efter ett tryck.
