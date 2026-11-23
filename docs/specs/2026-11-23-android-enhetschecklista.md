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

## Kvar att pröva på en riktig telefon

- En påminnelse som kommer av sig själv, utan flyttad klocka, med telefonen låst och i viloläge (Doze).
- Utställt i notisen med appen dödad.
- Live Update på låsskärmen. Notisen har synligheten `PRIVATE`, så innehållet kan döljas på en låst skärm med skyddat innehåll.
- Bakgrundshämtningen efter några timmar, och notisen om ett nytt källmeddelande från bakgrunden.
- Byte av tidszon i systemets inställningar.
- Kontrast och TalkBack i hela appen.
