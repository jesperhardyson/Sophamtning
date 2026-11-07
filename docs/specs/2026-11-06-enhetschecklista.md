# Enhetschecklista för iOS-appen

**Datum:** 2026-11-07
**Syfte:** Det som simulatorn inte kan visa: notiser, Live Activity, widget och bakgrundsuppdatering på en riktig iPhone. Den här listan är enda stället att följa, och är skriven i fas med avsnittet Animationer i `docs/specs/2026-11-06-ios-app.md`. Den samlar uppgift 14 steg 8 (ärende #16), uppgift 17 (ärende #16) och uppgift 15 i planen, och ska vara körd före TestFlight.

Bocka av i listan när punkten är körd, och skriv avvikelsen bredvid. Varje punkt säger vad som ska hända.

## Förberedelser (5 minuter)

Förberedelserna numreras F1 till F5, så att de inte förväxlas med punkterna nedan.

- **F1.** Installera appen från Xcode på iPhonen. iOS 26 eller senare. Kör gärna ett Release-bygge också, eftersom TestFlight-bygget är det.
- **F2.** Börja från en ren installation, så att inga gamla val eller tillstånd finns kvar. Undantaget är punkt 12, som kräver en äldre installation.
- **F3.** Ha minst två adresser med olika scheman, helst med en tömning i morgon eller övermorgon. De behövs i "Kvällar".
- **F4.** Slå på ljudet. Tyst läge och Fokus prövas separat.
- **F5.** Ha Xcode kopplat till telefonen för punkt 23. Inget annat kräver Xcode.

## Några minuter

Kan göras en och en, i vilken ordning som helst, när telefonen är i handen.

### Start och animationer

Animationerna är byggda och inspelade i simulatorn, men simulatorn har ingen haptik, går i cirka 30 bilder per sekund och kan inte visa hur rörelsen känns. Därför prövas allt nedan på telefonen. Kör punkt 1 till 8 på ett Release-bygge, eftersom det är det som skickas.

- [ ] **1. Introt.** Starta appen från början (svep bort den först). En logotyp visas direkt, utan hopp mot startskärmen, i både ljust och mörkt läge. Systemets toning hinner klart inom 0,3 sekunder. Sedan snurrar pilen ett varv runt kalendern, kalendern studsar med en lätt vibration, och logotypen krymper och glider undan för hemskärmen. Allt tar högst 1,2 sekunder. Rörelsen ska kännas tydlig och aldrig långsam.
- [ ] **2. Ett tryck hoppar över introt.** Starta om och tryck på skärmen under introt: det försvinner direkt och hemskärmen visas, med korten som glider in. Tryck under introts sista fas (efter cirka 0,8 sekunder): trycket går igenom till hemskärmen.
- [ ] **3. Inget intro vid retur.** Gå till hemskärmen och tillbaka till appen: inget intro, inga kort som glider in och ingen vändning av kalenderbladet. Öppna appen när den redan startat i bakgrunden: samma sak. Slå på VoiceOver och starta om: inget intro.
- [ ] **4. Hemskärmen kommer in.** Vid varje start från början, efter introt, glider rubrik, kort och friskrivning upp ett efter ett (24 punkter och toning, 60 ms mellan korten). Verktygsknapparna står stilla. Kontrollera med en adress, med flera adresser och i tomt läge (en ren installation). Kortet ska aldrig synas på fel plats under rörelsen, och ingen data väntar på introt.
- [ ] **5. Kalenderbladet vid start.** Vid varje start från början, när huvudkortet landat, bläddras kalenderbladet från dagens datum till tömningsdagen som en blockkalender: ett blad per dag viks upp kring överkanten, nästa blad ligger redan under, och bladen överlappar varandra. Inget blinkar tomt mellan bladen. Brickan visar andra datum bara under bläddringen, och VoiceOver läser bara upp tömningsdagen. Bläddringen sker inte om tömningen är i dag, eller om schema saknas, och inte vid retur från bakgrunden. Den sker också när nästa tömning byter datum efter en hämtning. Prova med tömningen:
  - **i morgon:** ett blad, cirka 0,25 sekunder.
  - **om 4 dagar:** 4 blad, cirka 0,5 sekunder. Det börjar snabbt och bromsar in mot tömningsdagen. Det känns som att dra tummen över en blockkalender.
  - **om mer än 8 dagar**, gärna över ett månadsskifte: 8 jämnt fördelade blad, sista bladet är tömningsdagen, och månadsraden byter månad med bladet. Allt är klart inom cirka 0,6 sekunder.
  - **vibrationer:** en lätt vibration per blad och en tydligare när sista bladet landar. Hemskärmens start känns inte längre än bläddringen.
  - **med Reducera rörelse:** en enda toning, inga blad och ingen vibration.
  - Inget hackar i 120 Hz, och varje blad hinner synas.
- [ ] **6. Tryck.** Knappar och rader fjädrar lite när de trycks ned (skala 0,96), och med Reducera rörelse tonar de i stället. Rörelsen fördröjer aldrig trycket. Kontrollera särskilt rader i listor som går att rulla: iOS kan där vänta lite med nedtrycket, och det ska inte kännas som en fördröjning.
  - **Snabba tryck:** tryck snabbt och kort på huvudkortet, en sökträff och en primärknapp. Fjädringen syns även vid ett mycket kort tryck, och varje tryck går igenom. Tryck flera gånger i snabb följd på samma knapp: inget hänger sig och inget öppnas två gånger.
  - **De tre vibrationerna** kommer när åtgärden utförs, inte vid nedtryck: **Spara området** (när området sparats, också när arket stängs samtidigt), **Hitta område** (när områden hittats, inte vid fel eller noll träffar) och **Sök din adress** (när sökningen öppnas). En sökträff som sparas direkt vibrerar också, när sparandet lyckats.
  - **Ingen vibration** när ett finger vilar på någon av knapparna och sedan rullar listan eller arket, när fingret dras bort från knappen innan det släpps, eller när sparandet misslyckas. Ett misslyckat sparande är svårt att framkalla, så notera om det fallet inte prövats.
- [ ] **7. Listor.** Sökresultat, områden och schemarader tonar in ett efter ett (de 8 första, 40 ms emellan), och inte när listan redan visats. Schemaraderna väntar tills listan syns. Skriv en adress i sökningen och ändra söktexten medan träffarna visas: träffarna startar om. Noteras: blinkar listans ruta tom till en kort stund när träffarna byts? Det är känt, och Jesper avgör om det är för mycket.
- [ ] **8. Känslan i rörelsen.** Titta på 120 Hz-flödet i introt, hemskärmens inträde och vändningen. Inget hackar, och inget känns segt. Vibrationerna i punkt 1, 6 och 11 kommer vid rätt ögonblick och inte oftare än de ska.
- [ ] **9. Avstängt från början.** På en ren installation är notiser och Live Activity avstängda för alla adresser och i Inställningar. Ingen tillståndsfråga från iOS visas vid start. Hemkortet säger **Påminn mig kvällen före**.
- [ ] **10. Laddning till schema.** Lägg till en ny adress. Kärlet laddar, och övergången till schemat hoppar inte. En snabb hämtning får inte kärlet att blinka till. Siffrorna i **om 3 dagar** rullar när de ändras.

### Notiser

- [ ] **11. Slå på notis.** Slå på **Notis kvällen före** på en adress. iOS frågar om tillstånd. Tillåt. Ikonen studsar och telefonen ger en lätt vibration. Raden under reglaget och hemkortet visar tid, till exempel **Påminnelse söndag kl. 18:00**.
- [ ] **12. Tidigare nekad notis.** Installera över en gammal installation som nekat notiser. Får du nekat direkt utan fråga, notera det. Det förklarar skillnaden mot en ren installation.
- [ ] **13. Nekad behörighet.** Ta bort appen, installera på nytt och neka frågan, eller stäng av notiser för appen i iOS Inställningar. Slå på notisen. Ingen ikoneffekt och ingen vibration. Appen visar **Notiser är avstängda** med **Öppna Inställningar**, som öppnar rätt sida i iOS. Slå sedan på tillståndet i iOS och gå tillbaka till appen: meddelandet försvinner utan omstart.
- [ ] **14. Ändrad påminnelsetid.** Ändra tiden under Inställningar > Påminnelsetid. Tiden går att välja mellan 15:00 och 23:00 i steg om 15 minuter. Notisen, hemkortet och adressvyn visar den nya tiden. Sätt tiden så att kvällens tid redan passerat när en tömning är i morgon: **Påminnelsen har passerat** visas, och ingen notis kommer i kväll.

### Live Activity

**Så startar du en aktivitet utan att vänta på kvällen.** Slå på **Live Activity** för huvudadressen, och ha en tömning i morgon. Ställ in påminnelsetiden på en tid som redan passerat i kväll (tidigast går tiden att sätta till 15:00, så det fungerar först efter 15:15). Öppna appen: planeraren körs och aktiviteten startas direkt. Ligger tiden framåt schemaläggs aktiviteten i stället, och startar då av sig själv vid tiden (se "Kvällar"). Aktiviteten kan bara starta när tömningen är i morgon, och den som har tryckt **Utställt** startar inte igen för samma tömning.

- [ ] **15. Slå på Live Activity.** Slå på **Live Activity** för huvudadressen. Ingen tillståndsfråga från iOS visas. Specen säger i dag att ingen fråga visas. Kommer frågan **Vill du fortsätta tillåta liveaktiviteter**, notera när den kommer, eftersom specen då ska ändras. Ikonen studsar och telefonen vibrerar när valet slås på, och inte när iOS nekar.
- [ ] **16. Avstängda i iOS.** Stäng av Live Activities för appen i iOS Inställningar. Appen visar **Live Activities är avstängda** med **Öppna Inställningar**. Valet i appen står kvar påslaget. Slå på dem i iOS igen: meddelandet försvinner.
- [ ] **17. Live Activity gäller bara huvudadressen.** Reglaget finns bara på huvudadressen. Byt huvudadress, och Live Activityn flyttas till den nya adressen.
- [ ] **18. Sex fraktioner på 375 punkter (låsskärm).** iPhone SE har ingen Dynamic Island, så här prövas bara låsskärmens aktivitet och förhandsvisningen. Öppna `iOS/SophamtningWidgets/PickupLiveActivity.swift` i Xcode och titta på förhandsvisningarna **Sex fraktioner, 375 pt**, **Utställt, 375 pt** och **Sex fraktioner, 402 pt** i canvas. Starta sedan en aktivitet på simulatorn **iPhone SE (3rd generation)** enligt beskrivningen ovan (ett vanligt bygge med en riktig adress, inte UI-testernas stubb, som inte startar aktiviteter), och titta på den på låsskärmen. Inget klipps, och alla fraktioner syns med färg, ikon och text. Startar inte aktiviteten i simulatorn räcker förhandsvisningarna, och det noteras. Telefonens egen bredd är större, så det som prövas här är att breda fraktioner inte tränger ut texten.
- [ ] **19. Ändrat schema.** Ändra påminnelsetid, eller byt huvudadress, medan en schemalagd Live Activity väntar. Hemkortet visar den nya starten (**Live Activity måndag kl. 18:15**), och bara en aktivitet startar vid den nya tiden. Den gamla försvinner och startar inte.

### Hemkort och schema

- [ ] **20. Reservpåminnelse på hemkortet.** Med både notis och Live Activity på för huvudadressen ska hemkortet visa **Reservpåminnelse kl. …** bara när en reservnotis verkligen ligger framför. Med bara notis på ska det stå **Påminnelse …**. Texten **Reservpåminnelse** hör till hemkortet och får aldrig stå när det egentligen är en vanlig notis. Själva notisen har rubriken **Har du ställt ut kärlen?**.
- [ ] **21. Flera adresser.** Lägg till tre adresser. Hemskärmen visar huvudadressen i kortet och övriga under **Fler adresser**. Byt namn på en, byt huvudadress, ta bort en med bekräftelse. Notisen går att slå på per adress, men inte Live Activity för andra än huvudadressen.
- [ ] **22. Flygplansläge.** Hämta schemat med nät, slå på flygplansläge och öppna appen. Hem och adress visar det sparade schemat, och adressvyn säger **Visar senast hämtade schema** med tid. Inget visas som att adressen saknas. Dra för att uppdatera: samma meddelande, utan felruta. Slå av flygplansläget och dra igen: schemat hämtas och meddelandet försvinner. Widgeten i flygplansläge visar samma sparade schema.
- [ ] **23. Bakgrundsuppdatering, med Xcode.** Med Xcode kopplat och appen i bakgrunden, pausa körningen och kör i konsolen: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"se.hardyson.sophamtning.refresh"]`. Uppgiften körs, och schemat hämtas högst en gång i timmen per adress. Öppna appen: **Hämtat i dag hh:mm** är den tiden. Den riktiga körningen kontrolleras i "Kvällar".
- [ ] **24. Högst en gång i timmen.** Dra för att uppdatera två gånger i följd. Den andra dragningen hämtar inte på nytt, och adressvyn visar när schemat senast hämtades. Efter ett misslyckat försök (flygplansläge) går ett nytt manuellt försök tidigast efter en minut.
- [ ] **25. Widget.** Lägg till widgeten i storlekarna liten och mellan. De visar huvudadressens nästa tömning, och tillägg i galleriet visar exempeldata, aldrig din adress. Byt huvudadress i appen: widgeten följer. Utan någon adress visar den **Lägg till en adress i appen**.

- [ ] **55. Adressvyn i ny ordning.** Öppna en adress med flera fraktioner. Utan att scrolla syns nästa tömning med kalenderbricka, dagar kvar, datum och kärlen som chips, och direkt under den **Kommande** med de tre närmaste datumen: liten datumbricka, chips med korta namn och dagar kvar (**om 4 d**) till höger. Den första raden kan vara samma dag som nästa tömning. Avvikelse och varning står under sin rad, utom varningen för nästa tömning, som bara står i rutan under kortet. **Hela schemat** finns bara när det finns fler än tre datum och visar alla datum i samma format. Under **Kärlen** ligger ett kort per kärl i sidled, och nästa kort syns till hälften. Svep i sidled: korten scrollar, och en lodrät rörelse som börjar på ett kort scrollar vyn. Sist kommer **Påminnelser**, och därefter källan och tid för senaste hämtning. Raderna och korten kommer in första gången, utan att blinka, och inte vid nästa öppning. Med VoiceOver läses nästa tömning som datum, dagar kvar och kärl, varje rad som datum, dagar kvar och kärl med hela namn, och varje kort för sig, även de som ligger utanför skärmen. Med största text: inga ord bryts mitt i, inte heller långa kärlnamn som **Pappersförpackningar**, korten växer, och **Hela schemat** står under rubriken.
- [ ] **56. Plats och notis på alla kort.** Spara minst två adresser, en gata och ett område, och slå på notis för en adress under **Fler adresser**. Huvudkortet, raderna och adressvyns rubrik visar gatan eller området, orten och kommunen utan "kommun" ("Storgatan 12, Krylbo · Avesta", "Kaplansgården, Jularbo m.fl. · Avesta"). Kommunen står inte två gånger när den heter som orten ("Stationsgatan 12, Uppsala"). Raden bryts och kapas inte med "…". Raden med notis på visar en liten ifylld klocka och samma text som huvudkortet ("Påminnelse tisdag kl. 18:45"), aldrig Live Activity. En rad med notis av visar ingen klocka. Neka notiser i iOS: raden visar samma text som huvudkortet. VoiceOver läser platsen och påminnelsen på raden. Med största text står ikonerna under texten och inga ord bryts mitt i.
- [ ] **57. Områden utan kommatecken.** Sök **Bergslagsgatan, Avesta**, **Bergslagsgatan Avesta**, **Bergslagsgatan 1 Avesta** och bara **Avesta**: alla visar **Välj område i Avesta kommun**. Med träffar står knappen ovanför dem, och områdesrader för samma kommun står inte en gång till i listan. Sök **Säter**: träffarna från andra kommuner visas, med **Välj område i Säters kommun** ovanför. Träffarna kommer lika fort som förut och väntar inte på knappen. Skriv snabbt och ändra texten: sökningen hackar inte, och en knapp för en gammal söktext visas inte. I flygplansläge: inget säger att kommunen saknar områdesval.

### Tillgänglighet

- [ ] **26. VoiceOver.** Slå på VoiceOver och gå igenom hem, adress, kommunfrågan, sökning, områdesval och inställningar. Chips läses som fraktionsnamn, kalenderbrickan som datum, reglagen med namn och läge (**Notis kvällen före, av**). Kärlet som laddar läses som **Hämtar schema**, inte som slumptexten. Hemkortet läses som en knapp med **Öppnar adressen**. Schemaraderna är med VoiceOver synliga direkt, utan att listan först rullats fram.
- [ ] **27. Största textstorlek.** Ställ in största Dynamic Type under Tillgänglighet. Ingen text klipps på hem, adress, inställningar och i arken, i både ljust och mörkt läge, och inte heller när hemskärmen kommer in och kalenderbladet vänds. Kontrollera också Live Activity och widgeten.
- [ ] **28. Reducera rörelse.** Slå på Reducera rörelse. Kärlet står still med stängt lock och en fast text. Introt, hemskärmens inträde, listorna och trycken ersätts av toning, och introts vibration uteblir. Ikonen pulserar i stället för att studsa.
- [ ] **29. Ikonerna på påminnelseraderna.** Titta på ikonerna vid **Notis kvällen före** och **Live Activity**. De finns inte i designen, och måste godkännas av Jesper före TestFlight.

### Svep och snabbmeny

Punkterna har nummer efter listans övriga, så att hänvisningarna ovan och nedan inte ändras. Ha minst tre adresser.

- [ ] **47. Svep som i Mail.** Svep åt vänster på huvudkortet och på en rad under **Fler adresser**. Bakom huvudkortet kommer en rund röd knapp med papperskorg fram, mitt för kortet och med **Ta bort** under, och den tonas och skalas in med svepet. Bakom en rad kommer en röd knapp lika hög som raden. Raden följer fingret. Släpp efter en bit: raden står öppen. Tryck på knappen: **Ta bort adressen?** visas. **Avbryt** får raden att glida tillbaka. Ett tryck på en öppen rad stänger den, och öppnar inte adressen. Ett snabbt kort svep öppnar raden men tar aldrig bort.
- [ ] **48. Fullt svep.** Svep hela vägen åt vänster. En lätt vibration kommer när gränsen för fullt svep passeras, och bara en gång per passage. Släpp: bekräftelsen visas direkt. **Ta bort** tar bort adressen. Tas huvudadressen bort blir den äldsta kvarvarande ny huvudadress, och widgeten följer. Den sista adressen ger tomt läge.
- [ ] **49. Svepet stör inget annat.** Börja en lodrät scrollning på ett kort, också lite snett: hemskärmen scrollar, och kortet rör sig inte i sidled. Dra för att uppdatera från kortet: det uppdaterar. Ett vanligt tryck öppnar adressen utan fördröjning, och fjädringen syns. Öppna en rad och svep sedan en annan: den första stängs. Öppna en rad och scrolla: den stängs. Öppna en rad och tryck utanför den, på ett annat kort, på **Lägg till** eller nedanför innehållet: raden stängs, och inget annat händer. Öppna en rad, lås telefonen och lås upp: raden är stängd. Svep åt höger på en stängd rad: inget händer.
- [ ] **50. Svep med Reducera rörelse.** Med Reducera rörelse glider raden till sitt läge utan att fjädra, och den runda knappen tonas in utan att skalas.
- [ ] **51. Snabbmenyn.** Håll ned på huvudkortet. Systemets snabbmeny öppnas med systemets haptik, och förhandsvisningen har kortets rundade hörn, utan fyrkantig ram. Valen är i ordning **Byt namn**, **Notis kvällen före**, **Live Activity**, med undertexten "Starten aviseras med ljud.", och **Ta bort** (rött). På en rad under **Fler adresser** finns **Gör till huvudadress** efter **Byt namn**, men inte **Live Activity**. **Notis kvällen före** och **Live Activity** har ingen bock på en ren installation. Håll ned på en rad som står öppen efter ett svep: inget konstigt händer.
- [ ] **52. Val i snabbmenyn.** **Byt namn** öppnar samma dialog som i adressvyn. **Gör till huvudadress** flyttar adressen till kortet. **Notis kvällen före** frågar om tillstånd första gången, precis som i adressvyn, och har bock nästa gång menyn öppnas. **Ta bort** visar bekräftelsen.
- [ ] **53. Nekad behörighet från snabbmenyn.** Neka notiser i iOS och slå på **Notis kvällen före** i snabbmenyn. När menyn stängts visas **Notiser är avstängda** med **Öppna Inställningar**, som öppnar rätt sida i iOS. Med Live Activities avstängda i iOS visar hemskärmen **Live Activities är avstängda** när valet slås på i menyn.
- [ ] **54. VoiceOver.** Med VoiceOver på huvudkortet och en rad: åtgärden **Ta bort** finns i rotorn och visar bekräftelsen utan svep. Rotorn har också samma val som snabbmenyn: **Byt namn**, **Gör till huvudadress** (bara på en rad), **Slå på** eller **Stäng av notis kvällen före**, **Slå på** eller **Stäng av Live Activity** (bara huvudkortet) och **Ta bort**. Notera om iOS dessutom lägger till en egen åtgärd för snabbmenyn.

## Kvällar

Kräver att en schemalagd tömning ligger dagen efter varje kväll, och att telefonen får vara orörd över natten. Det blir **fem kvällar**, eftersom en aktivitet bara kan startas en gång per tömning och varje prov kräver en egen start: kväll 1 (Live Activity och reserv), kväll 2 (Utställt), kväll 3 (Tyst läge), kväll 4 (Fokus) och kväll 5 (nekade notiser). Tyst läge och Fokus kan inte prövas samma kväll. Notisen med appen avslutad (punkt 41) prövas på en annan adress än huvudadressen under kväll 1, så den kräver ingen kväll för sig. Punkt 42 gäller flera kvällar och följs upp efter hand. Ha nätet påslaget om inget annat anges.

Förberedelse varje kväll, på huvudadressen med tömning dagen efter: slå på notis och Live Activity, ställ in en tid då telefonen är låst, och **öppna appen en sista gång** för att planeringen ska köras. Avsluta appen genom att svepa bort den. Lås telefonen.

### Kväll 1: Live Activity och reserv med appen avslutad

- [ ] **30. Schemalagd start.** Vid vald tid startar Live Activityn med appen avslutad och telefonen låst. Aktiviteten syns på låsskärmen med rätt adress, fraktioner och datum (veckodag och datum, inte **i morgon**). Noteras: tänds skärmen av sig själv, hörs ljud, känns vibration? I försöket på iOS 27 tändes skärmen inte, bara ljud och vibration. Skärmen som inte tänds är den enda oron för att påminnelsen missas.
- [ ] **31. Inte två aviseringar.** Det kommer en avisering, inte två. Den vanliga notisen för just den tömningen kommer inte vid samma tid, eftersom den flyttats till reserven.
- [ ] **32. Dynamic Island, på Jespers iPhone 17 Pro.** Starta aktiviteten som i punkt 30. Titta på kompakt läge när du lämnar låsskärmen: inget klipps. Håll ned på ön för det expanderade läget: knappen **Utställt** syns. Minimalt läge visas bara när ett annat program, till exempel en timer, har en aktivitet samtidigt: starta en timer och titta. Låsskärmens aktivitet på telefonens egen bredd tittar du på i samma ögonblick.
- [ ] **33. Reservnotisen.** Gör inget, öppna inte appen, och tryck inte **Utställt**. Reservnotisen med rubriken **Har du ställt ut kärlen?** kommer 45 minuter efter starten. Tiden går att sätta till 23:00 som senast, så den senaste reserven kommer 23:45, och taket går därför inte att pröva med någon tid som tidsväljaren erbjuder. Pröva i stället 18:00 (reserv 18:45) och 23:00 (reserv 23:45, inte efter midnatt). Hemkortet säger **Reservpåminnelse kl. …** tills den kommit.
- [ ] **34. Försvinner efter högst 12 timmar.** Aktiviteten försvinner av sig själv senast 12 timmar efter starten. Med start kl. 18:00 ska den vara borta senast 06:00, och med start 23:00 senast 11:00. Kontrollera låsskärmen kring tidpunkten. Är den kvar efter 12 timmar är det ett fel.

### Kväll 2: Utställt

- [ ] **35. Utställt.** Upprepa förberedelsen. När aktiviteten startat: tryck **Utställt**. Knappen byts mot en bock och **Utställt**, och aktiviteten försvinner efter 3 sekunder. Noteras: syns bocken 3 sekunder på låsskärmen och i Dynamic Island? Apples text om `.after` nämner bara låsskärmen.
- [ ] **36. Ingen reservnotis efter Utställt.** Ingen reservnotis kommer 45 minuter senare.
- [ ] **37. Inte igen vid öppning.** Öppna appen efteråt. Aktiviteten för samma tömning startas inte igen, och inte heller efter att appen avslutats och öppnats på nytt.

### Kväll 3: Tyst läge

- [ ] **38. Tyst läge.** Slå på Tyst läge och upprepa punkt 30. Notera om aviseringen hörs eller känns, och om aktiviteten syns när du tänder skärmen. Det avgör om någon missar påminnelsen när den vanliga notisen uteblir.

### Kväll 4: Fokus

- [ ] **39. Fokus.** Slå på Fokus (till exempel Stör ej, och sedan ett eget Fokus som inte släpper igenom appen). Upprepa punkt 30. Notera om aktiviteten startar, om reserven kommer, och vad som syns på låsskärmen.

### Kväll 5: Notiser nekade

- [ ] **40. Notiser nekade, Live Activity på.** Stäng av notiser för appen i iOS, behåll Live Activity. Aktiviteten startar ändå, och ljudet hörs ändå, enligt försöket. Notera om en banner visas. Appen visar **Notiser är avstängda** utan att stänga av Live Activity.

### Notis med appen avslutad (under kväll 1, på en annan adress)

- [ ] **41. Notis kvällen före.** Slå på bara notis (inte Live Activity) på en annan adress än huvudadressen, med tömning dagen efter. Notisen kommer vid vald tid kvällen före, med adress, fraktioner och datum, och appen avslutad. Beräknade datum står med **ca**, och en varning från källan följer med. Har ingen adress med tömning dagen efter "ca" eller en varning: notera det, och kontrollera **ca** och varningen i adressvyn i stället. Tryck på notisen: appen öppnas.
### Notiser för flera adresser (över flera kvällar)

- [ ] **42. Flera adresser.** Slå på notis för tre adresser med olika datum. Varje adress får sin notis vid rätt kväll och inga dubbletter. Högst 60 notiser är schemalagda samtidigt, de närmaste först. Notisen för en adress som tagits bort kommer inte.

### Morgonen efter

- [ ] **43. Widget efter midnatt.** Lämna hemskärmen med widgeten över midnatt. Utan att öppna appen visar widgeten på morgonen rätt dag och rätt nästa tömning. En tömning som varit i går visas inte.
- [ ] **44. Bakgrundsuppdatering.** Efter natten, utan att ha öppnat appen sedan kvällen: öppna adressvyn och läs **Hämtat i dag hh:mm**. Står tiden under natten eller morgonen har iOS kört bakgrundsuppdateringen. iOS bestämmer när, så noteras bara om den kom, och när. Aktivt Lågenergiläge eller avstängd bakgrundsuppdatering i iOS ger ingen körning, och det är inget fel.
- [ ] **45. Kalenderbladet på morgonen.** Starta appen från början på morgonen efter en tömning: kalenderbladet vänds från dagens datum till nästa tömningsdag (se punkt 5). Hämtas ett nytt schema medan appen är öppen och nästa tömning byter datum, vänds bladet även då.
- [ ] **46. Morgonen i appen.** Hemkortet visar inte längre **Live Activity visas nu** eller en gammal reservpåminnelse. Texten **Reservpåminnelse** visas bara när en reservnotis ligger framför.

## När listan är körd

Bocka av steg 8 i uppgift 14 i `docs/plans/2026-11-06-ios-app.md` (**Kontrollera på riktig telefon**) när testet är gjort. Ändrar utfallet något i `docs/specs/2026-11-06-ios-app.md` (till exempel att iOS frågar om liveaktiviteter, eller att skärmen inte tänds) ska specen ändras, och ändringen godkännas av Jesper innan bygget fortsätter.

## Vid avvikelse

Skriv vad som hände, vid vilken tid, med vilken telefon och iOS-version, och om appen var avslutad.
