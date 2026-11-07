# Enhetschecklista för iOS-appen

**Datum:** 2026-11-07
**Syfte:** Det som simulatorn inte kan visa: notiser, Live Activity, widget och bakgrundsuppdatering på en riktig iPhone. Den här listan är enda stället att följa. Den samlar uppgift 14 steg 8 (ärende #16), uppgift 17 (ärende #16) och uppgift 15 i planen, och ska vara körd före TestFlight.

Bocka av i listan när punkten är körd, och skriv avvikelsen bredvid. Varje punkt säger vad som ska hända.

## Förberedelser (5 minuter)

1. Installera appen från Xcode på iPhonen. iOS 26 eller senare. Kör gärna en Release-bygge också, eftersom TestFlight-bygget är det.
2. Börja från en ren installation, så att inga gamla val eller tillstånd finns kvar. Undantaget är punkt 7, som kräver en äldre installation.
3. Ha minst två adresser med olika scheman, helst med en tömning i morgon eller övermorgon. De behövs i "En natt".
4. Slå på ljudet. Tyst läge och Fokus prövas separat.
5. Ha Xcode kopplat till telefonen för punkt 18. Inget annat kräver Xcode.

## Några minuter

Kan göras en och en, i vilken ordning som helst, när telefonen är i handen.

### Start och utseende

- [ ] **1. Introt.** Starta appen från början. En logotyp visas, utan hopp mot startskärmen, i både ljust och mörkt läge. Systemets toning hinner klart inom 0,3 sekunder. Sedan snurrar ringen ett varv, kalendern studsar med en lätt vibration, och logotypen krymper och tonas ut, allt på högst 1,2 sekunder. Ett tryck tar bort introt direkt.
- [ ] **2. Inget intro vid retur.** Gå till hemskärmen och tillbaka till appen: inget intro. Öppna appen när den redan startat i bakgrunden: inget intro. Slå på VoiceOver och starta om: inget intro.
- [ ] **3. Avstängt från början.** På en ren installation är notiser och Live Activity avstängda för alla adresser och i Inställningar. Ingen tillståndsfråga från iOS visas vid start. Hemkortet säger **Påminn mig kvällen före**.
- [ ] **4. Laddning till schema.** Lägg till en ny adress. Kärlet laddar, och övergången till schemat hoppar inte. En snabb hämtning får inte kärlet att blinka till.

### Notiser

- [ ] **5. Slå på notis.** Slå på **Notis kvällen före** på en adress. iOS frågar om tillstånd. Tillåt. Ikonen studsar och telefonen ger en lätt vibration. Raden under reglaget och hemkortet visar tid, till exempel **Påminnelse söndag kl. 18:00**.
- [ ] **6. Nekad behörighet.** Ta bort appen, installera på nytt och neka frågan, eller stäng av notiser för appen i iOS Inställningar. Slå på notisen. Ingen ikoneffekt och ingen vibration. Appen visar **Notiser är avstängda** med **Öppna Inställningar**, som öppnar rätt sida i iOS. Slå sedan på tillståndet i iOS och gå tillbaka till appen: meddelandet försvinner utan omstart.
- [ ] **7. Tidigare nekad notis.** Installera över en gammal installation som nekat notiser. Får du nekat direkt utan fråga, notera det. Det förklarar skillnaden mot en ren installation.
- [ ] **8. Ändrad påminnelsetid.** Ändra tiden under Inställningar > Påminnelsetid. Tiden går att välja mellan 15:00 och 23:00 i steg om 15 minuter. Notisen, hemkortet och adressvyn visar den nya tiden. Sätt tiden så att kvällens tid redan passerat när en tömning är i morgon: **Påminnelsen har passerat** visas, och ingen notis kommer i kväll.

### Live Activity

- [ ] **9. Slå på Live Activity.** Slå på **Live Activity** för huvudadressen. Ingen tillståndsfråga från iOS visas. Specen säger i dag att ingen fråga visas. Kommer frågan **Vill du fortsätta tillåta liveaktiviteter**, notera när den kommer, eftersom specen då ska ändras. Ikonen studsar och telefonen vibrerar när valet slås på, och inte när iOS nekar.
- [ ] **10. Avstängda i iOS.** Stäng av Live Activities för appen i iOS Inställningar. Appen visar **Live Activities är avstängda** med **Öppna Inställningar**. Valet i appen står kvar påslaget. Slå på dem i iOS igen: meddelandet försvinner.
- [ ] **11. Live Activity gäller bara huvudadressen.** Reglaget finns bara på huvudadressen. Byt huvudadress, och Live Activityn flyttas till den nya adressen.
- [ ] **12. Sex fraktioner på 375 punkter.** Förhandsvisningarna i `PickupLiveActivity.swift` och simulatorn **iPhone SE (3rd generation)** är 375 punkter breda. Visa en aktivitet med sex fraktioner, och kontrollera låsskärmen, kompakt, minimal och expanderad Dynamic Island, och avstängda val. Inget klipps, och alla fraktioner syns med färg, ikon och text. Telefonens egen bredd är större, så det gäller att breda fraktioner inte tränger ut texten.
- [ ] **13. Ändrat schema.** Ändra påminnelsetid, eller byt huvudadress, medan en schemalagd Live Activity väntar. Hemkortet visar den nya starten (**Live Activity måndag kl. 18:15**), och bara en aktivitet startar vid den nya tiden. Den gamla försvinner och startar inte.

### Hemkort och schema

- [ ] **14. Reservnotis på hemkortet.** Med både notis och Live Activity på för huvudadressen ska hemkortet visa **Reservpåminnelse kl. …** bara när en reservnotis verkligen ligger framför. Med bara notis på ska det stå **Påminnelse …**. Texten **Reservpåminnelse** får aldrig stå när det egentligen är en vanlig notis.
- [ ] **15. Flera adresser.** Lägg till tre adresser. Hemskärmen visar huvudadressen i kortet och övriga under **Fler adresser**. Byt namn på en, byt huvudadress, ta bort en med bekräftelse. Notisen går att slå på per adress, men inte Live Activity för andra än huvudadressen.
- [ ] **16. Flygplansläge.** Hämta schemat med nät, slå på flygplansläge och öppna appen. Hem och adress visar det sparade schemat, och adressvyn säger **Visar senast hämtade schema** med tid. Inget visas som att adressen saknas. Dra för att uppdatera: samma meddelande, utan felruta. Slå av flygplansläget och dra igen: schemat hämtas och meddelandet försvinner. Widgeten i flygplansläge visar samma sparade schema.
- [ ] **17. Widget.** Lägg till widgeten i storlekarna liten och mellan. De visar huvudadressens nästa tömning, och tillägg i galleriet visar exempeldata, aldrig din adress. Byt huvudadress i appen: widgeten följer. Utan någon adress visar den **Lägg till en adress i appen**.
- [ ] **18. Bakgrundsuppdatering, med Xcode.** Med Xcode kopplat och appen i bakgrunden, pausa körningen och kör i konsolen: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"se.hardyson.sophamtning.refresh"]`. Uppgiften körs, och schemat hämtas högst en gång i timmen per adress. Öppna appen: **Hämtat i dag hh:mm** är den tiden. Den riktiga körningen kontrolleras i "En natt".
- [ ] **19. Högst en gång i timmen.** Dra för att uppdatera två gånger i följd. Den andra dragningen hämtar inte på nytt, och adressvyn visar när schemat senast hämtades. Efter ett misslyckat försök (flygplansläge) går ett nytt manuellt försök tidigast efter en minut.

### Tillgänglighet

- [ ] **20. VoiceOver.** Slå på VoiceOver och gå igenom hem, adress, kommunfrågan, sökning, områdesval och inställningar. Chips läses som fraktionsnamn, kalenderbrickan som datum, reglagen med namn och läge (**Notis kvällen före, av**). Kärlet som laddar läses som **Hämtar schema**, inte som slumptexten. Hemkortet läses som en knapp med **Öppnar adressen**.
- [ ] **21. Största textstorlek.** Ställ in största Dynamic Type under Tillgänglighet. Ingen text klipps på hem, adress, inställningar och i arken, i både ljust och mörkt läge. Kontrollera också Live Activity och widgeten.
- [ ] **22. Reducera rörelse.** Slå på Reducera rörelse. Kärlet står still, och övriga animationer ersätts av toning. Ikonen pulserar i stället för att studsa.
- [ ] **23. Ikonerna på påminnelseraderna.** Titta på ikonerna vid **Notis kvällen före** och **Live Activity**. De finns inte i designen, och måste godkännas av Jesper före TestFlight.

## En natt

Kräver att någon schemalagd tömning ligger i morgon, och att telefonen får vara orörd. Planera två eller tre kvällar, eftersom Tyst läge och Fokus inte kan prövas samma kväll. Ha nätet påslaget om inget annat anges.

Förberedelse kvällen före, på en adress med tömning dagen efter: slå på notis och Live Activity för huvudadressen, ställ in tiden till en tid då telefonen är låst, och **öppna appen en sista gång** för att planeringen ska köras. Avsluta appen genom att svepa bort den. Lås telefonen.

### Kväll 1: Live Activity och notis med appen avslutad

- [ ] **24. Schemalagd start.** Vid vald tid startar Live Activityn med appen avslutad och telefonen låst. Aktiviteten syns på låsskärmen med rätt adress, fraktioner och datum (veckodag och datum, inte **i morgon**). Noteras: tänds skärmen av sig själv, hörs ljud, känns vibration? I försöket på iOS 27 tändes skärmen inte, bara ljud och vibration. Skärmen som inte tänds är den enda oron för att påminnelsen missas.
- [ ] **25. Inte två aviseringar.** Det kommer en avisering, inte två. Den vanliga notisen för just den tömningen kommer inte vid samma tid, eftersom den flyttats till reserven.
- [ ] **26. Dynamic Island.** Kompakt och minimal Dynamic Island visar rätt innehåll och inget klipps. Håll ned för det expanderade läget. Knappen **Utställt** syns.
- [ ] **27. Reservnotisen.** Gör inget, öppna inte appen, och tryck inte **Utställt**. Reservnotisen kommer 45 minuter efter starten, och senast 23:45 samma kväll. Starta Live Activityn sent (till exempel 23:15) och kontrollera att reserven kommer 23:45 och inte efter midnatt. Texten är **Reservpåminnelse**, och hemkortet säger det tills den kommit.
- [ ] **28. Försvinner efter högst 12 timmar.** Aktiviteten försvinner av sig själv senast 12 timmar efter starten. Kontrollera låsskärmen kring tidpunkten. Med start kl. 18:00 ska den vara borta före 06:00.

### Kväll 2: Utställt

- [ ] **29. Utställt.** Upprepa förberedelsen. När aktiviteten startat: tryck **Utställt**. Knappen byts mot en bock och **Utställt**, och aktiviteten försvinner efter 3 sekunder. Noteras: syns bocken 3 sekunder på låsskärmen och i Dynamic Island? Apples text om `.after` nämner bara låsskärmen.
- [ ] **30. Ingen reservnotis efter Utställt.** Ingen reservnotis kommer 45 minuter senare.
- [ ] **31. Inte igen vid öppning.** Öppna appen efteråt. Aktiviteten för samma tömning startas inte igen, och inte heller efter att appen avslutats och öppnats på nytt. Hemkortet visar nästa tömning, inte den utställda.

### Kväll 3: Tyst läge, Fokus och nekad behörighet

- [ ] **32. Tyst läge.** Slå på Tyst läge och upprepa punkt 24. Notera om aviseringen hörs eller känns, och om aktiviteten syns när du tänder skärmen. Det avgör om någon missar påminnelsen när den vanliga notisen uteblir.
- [ ] **33. Fokus.** Slå på Fokus (till exempel Stör ej, och sedan ett eget Fokus som inte släpper igenom appen). Upprepa. Notera om aktiviteten startar, om reserven kommer, och vad som syns på låsskärmen.
- [ ] **34. Notiser nekade, Live Activity på.** Stäng av notiser för appen i iOS, behåll Live Activity. Aktiviteten startar ändå, och ljudet hörs ändå, enligt försöket. Notera om en banner visas. Appen visar **Notiser är avstängda** utan att stänga av Live Activity.

### Kväll 4 (eller samma som 1): Notis med appen avslutad

- [ ] **35. Notis kvällen före.** Med bara notis på, och appen avslutad: notisen kommer vid vald tid kvällen före, med adress, fraktioner och datum. Beräknade datum står med **ca**, och en varning från källan följer med. Tryck på den: appen öppnas.
- [ ] **36. Flera adresser.** Slå på notis för tre adresser med olika datum. Varje adress får sin notis vid rätt kväll och inga dubbletter. Högst 60 notiser är schemalagda samtidigt, de närmaste först. Notisen för en adress som tagits bort kommer inte.

### Morgonen efter

- [ ] **37. Widget efter midnatt.** Lämna hemskärmen med widgeten över midnatt. Utan att öppna appen visar widgeten på morgonen rätt dag och rätt nästa tömning. En tömning som varit i går visas inte.
- [ ] **38. Bakgrundsuppdatering.** Efter natten, utan att ha öppnat appen sedan kvällen: öppna adressvyn och läs **Hämtat i dag hh:mm**. Står tiden under natten eller morgonen har iOS kört bakgrundsuppdateringen. iOS bestämmer när, så noteras bara om den kom, och när. Aktiv Lågenergiläge eller avstängd bakgrundsuppdatering i iOS ger ingen körning, och det är inget fel.
- [ ] **39. Kalenderbladet.** Öppna appen på morgonen efter en tömning. Kalenderbladet vänder sig när nästa tömning byter datum, men inte när kortet visas första gången.
- [ ] **40. Natten i appen.** Hemkortet visar inte längre **Live Activity visas nu** eller en gammal reservnotis. Texten **Reservpåminnelse** visas bara när en reservnotis ligger framför.

## Vid avvikelse

Skriv vad som hände, vid vilken tid, med vilken telefon och iOS-version, och om appen var avslutad. Ändrar utfallet något i `docs/specs/2026-11-06-ios-app.md` (till exempel att iOS frågar om liveaktiviteter, eller att skärmen inte tänds) ska specen ändras, och ändringen godkännas innan bygget fortsätter.
