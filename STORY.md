# STORY.md

Memoria di progetto per le sessioni AI. Leggi questo file prima di esplorare il codice: serve a non rifare ricerche e a non ripetere errori.

**Regole**
- Dopo ogni modifica rilevante aggiungi una voce in fondo a "Registro" e aggiorna "Stato attuale" e "Lavoro aperto".
- Rilevante: comportamento, architettura, build, decisioni, bug con causa non ovvia. Non serve per refusi o ritocchi.
- Scrivi solo fatti verificati. Separa cosa hai provato da cosa no. Se una causa è un'ipotesi, dillo.
- Tieni il file corto: niente che si ricavi leggendo il codice o `git log`. Conta il perché.
- Il codice batte questo file. Se non coincidono, verifica e correggi il file.

## Il progetto
DullNotch è un fork di Boring Notch: app macOS in SwiftUI (minimo macOS 14) che trasforma il notch in un pannello di widget. L'identificativo dell'app è ancora `theboringteam.boringnotch`.

## Stato attuale (11 novembre 2026)
**Avanzamento nel notch chiuso** (release 1.5.0): una fonte per volta, in ordine di priorità: timer di Orologio, download, ricarica solo se avanza, quota AI. Tre stili (`wings`, `wire`, `hybrid`), pagina Impostazioni → Progress. Tutto in `components/Notch/NotchProgress.swift`; l'aggancio al notch è in `ContentView` (`progressItem`, `progressWings`, `ProgressLiveActivity`). Dettagli nel Registro, 2026-11-11.

Lumen, Meteo, barra laterale delle Impostazioni e scheda Convert sono nel commit della **release 1.4.0**. Lumen è inclusa e attiva di default, ma per scelta dell'utente non è ancora citata nel README né nelle note di rilascio.

**Lumen**, la mascotte: una falena-lanterna pixel-art (28 × 20) che si muove sopra, sotto e dietro i widget. Attiva di default (`lumenEnabled`), con interruttore nelle impostazioni dei widget.

| File | Contenuto |
|---|---|
| `components/Notch/LumenBrain.swift` | FSM pura, senza UI né timer: mosse, probabilità, attese, condizioni del sonno |
| `components/Notch/LumenView.swift` | Sprite, percorsi, `LumenDirector`, `LumenClock`, disegno |
| `components/Notch/NotchHomeView.swift`, sezione `Lumen` | Aggancio alla riga dei widget e input della FSM |

Stati della FSM: `hidden`, `asleep`, `waking`, `hovering`, `fallingAsleep`, `performing(mossa)`.

**Quando dorme**
- Notch non aperto da 10 minuti e niente musica: la trovi addormentata.
- Notch aperto, puntatore fermo da 30 s e niente musica.
- Risparmio energetico: dorme e nulla la sveglia.

**Aggiungere un widget:** basta una riga in `NotchWidget.lumenKind` (`NotchHomeView.swift`); lo switch è esaustivo, quindi il compilatore la richiede. Posizioni e dimensioni arrivano dal layout. Se il widget ha uno sfondo pieno, aggiungilo anche a `isGlass`.

## Decisioni e perché
- **Timer, non `TimelineView`.** Con `TimelineView` l'app consumava circa il 10% di un core anche senza disegnare nulla. Non riportarlo in Lumen. Limitare l'area di disegno ha dato poco: la causa non era il disegno.
- **`clearOfCamera`/`quietSpot`.** L'header passa sopra la riga dei widget: tocca al notch fisico e alle icone di stato coprire la testa di Lumen. I punti a ±108 pt dal centro sono liberi.
- **"Sotto" è in parte dietro il vetro.** Sotto le card restano circa 12 pt e lo sprite è alto 20. Si è scelto di non alzare il notch.
- **La FSM è separata dal disegno** e ha `selfCheck` eseguiti in Debug. Fuori dall'app si possono compilare `LumenBrain.swift` e `LumenView.swift` con `swiftc -DDEBUG` e un `main.swift` che li chiama.

## Trappole
- **Mai animare l'intero notch su un valore che cambia ogni secondo.** `.animation(.smooth, value: progress.current)` sul layout principale costava il 34% di un core a notch chiuso con un timer in corso; legata alla sola fonte (`current?.source`) scende a 0,7%.
- **Cartelle dell'utente nella sandbox:** `FileManager.urls(for: .downloadsDirectory)` restituisce la cartella del contenitore, non quella vera, anche con l'entitlement. Il percorso reale si ricava da `getpwuid`.
- **Misura le prestazioni solo in Release.** In Debug l'app segnava circa il 27% con Lumen spenta e 0,6% in Release: la build Debug mi aveva fatto concludere il contrario del vero.
- **Build Release locale:** serve `ENABLE_HARDENED_RUNTIME=NO` con firma ad hoc, altrimenti `MediaRemoteAdapter.framework` non si carica e l'app si chiude all'avvio. Il flag è solo da riga di comando, il progetto non è cambiato.
- **Non usare `CODE_SIGNING_ALLOWED=NO` per lanciare l'app.** Senza entitlements perde il sandbox, quindi non legge le impostazioni dell'utente.
- **Impostazioni:** stanno nel contenitore sandbox di `theboringteam.boringnotch` e ogni build con quell'identificativo le condivide. macOS impedisce di leggere il file dall'esterno. Per le prove senza toccarle usa argomenti di avvio, per esempio `--args -lumenEnabled '<false/>' -homeWidgets '<array><string>quote</string></array>'`.
- **Istanze multiple:** `open -n` ne apre sempre una nuova e l'app non risponde a `kill`/SIGTERM. Usa `kill -9` e controlla con `pgrep -lf "MacOS/DullNotch"`. Se due istanze restano aperte si sovrappongono e falsano test e log.
- **Il notch si chiude quando il puntatore esce:** nelle prove automatiche tienilo dentro. Su uno schermo da 1512 pt il notch aperto largo 720 pt va da x≈396 a x≈1116.
- **Nuovi file Swift:** `boringNotch/components/Notch` non è una cartella sincronizzata, quindi vanno aggiunti a mano a `project.pbxproj` in quattro punti.
- **Permesso posizione e firma ad hoc:** il permesso è registrato sul `cdhash` della build. Build diverse non hanno lo stesso hash, quindi prima di dare la colpa al codice controlla la voce in `/var/db/locationd/clients.plist`.
- **Misure automatiche a notch aperto:** `hideFromScreenRecording` può nascondere il notch dagli screenshot, quindi una cattura non prova che sia chiuso. Spostare il cursore con `CGEvent` e la scorciatoia ⌘⇧I (`toggleNotchOpen`) non lo aprono in modo affidabile: scarta ogni prova con l'app sotto l'1% circa. Per un confronto serio serve aprirlo da codice in una copia di prova, senza cursore.
- **Più sessioni insieme:** altre sessioni possono modificare questi stessi file. Rileggili prima di modificarli e controlla chi è in esecuzione.
- **Prove sulla finestra Impostazioni:** una build nuova non ha l'icona nella barra dei menu su macOS 27, quindi va aperta da codice in una copia dei sorgenti. Usa `orderFrontRegardless()`, non `showWindow()`: con il focus la pagina è cambiata da sola tra l'apertura e la cattura (causa non verificata) e una misura è finita su Media. Guarda sempre la cattura, non solo il numero.

## Lavoro aperto
- Avanzamento, non provato: download reale da Safari, Chrome e Firefox (provato solo con un `Progress` pubblicato da uno script); ricarica che avanza (la batteria era ferma all'80%); musica attiva con l'interruttore di precedenza acceso e spento; timer in pausa e fine del timer; pagina Progress nelle Impostazioni mai aperta; area sensibile al mouse nello stile Ibrida.
- Scheda Convert e schede visibili (Registro, 2026-11-08): mai aperte nell'app, da far provare all'utente.
- Far confermare all'utente la correzione della barra laterale su Widgets (Registro, 2026-11-06): l'istanza in esecuzione è una build precedente.
- Lumen nel README: rimandata dall'utente (2026-11-08).
- Firma stabile per la posizione: sul Mac non c'è nessuna identità di firma (`security find-identity` ne trova 0). Serve l'Apple ID in Xcode e una scelta dell'utente su dove tenere il Team. Da provare con `MediaRemoteAdapter.framework` e hardened runtime, vedi Trappole.
- Decidere se Lumen resta attiva di default anche per gli altri utenti.
- Non ancora visti nell'app reale: "Contro la luce", "Balla", "Legge", "Bussa", risveglio con la musica, risparmio energetico, cambio di widget a mano, Specchio, Calendario, Batteria Bluetooth.
- Consumo delle nuove mosse non misurato: vedi Registro, misura non riuscita.
- **Cielo animato del Meteo: è il consumo più alto a notch aperto.** Con il Meteo (cielo nuvoloso) app circa 30% e WindowServer circa 30%; senza Meteo e senza Lumen 0,1% e 7%. Vedi Registro, 2026-11-11 "Lumen: cadenza variabile". Da ottimizzare.
- Lumen sveglia costa ancora circa 6 punti di core nell'app. Idee non provate: ridipingere l'alone sui widget solo quando Lumen si sposta; un solo calcolo per fotogramma tra i due strati; sprite come layer Core Animation.

## Misure di riferimento
Build Release, percentuali di un core, Mac in carica, poche letture.

| Stato | DullNotch | Totale con WindowServer |
|---|---|---|
| Chiuso | 0,0% | circa 6% (1,8% in altre misure: dipende da cos'altro si muove sullo schermo) |
| Aperto, Lumen spenta | 0,6% | 9,9% |
| Aperto, Lumen addormentata | 1,8% | 10,9% |
| Aperto, Lumen sveglia | 9,9% | 23,6% |

Misura dell'11 novembre, senza Meteo (widget Musica e Quote), puntatore mosso da script, 10 letture, una sola prova per riga:

| Stato | DullNotch | WindowServer |
|---|---|---|
| Aperto, Lumen spenta | 0,1% | 7,1% |
| Aperto, Lumen sveglia, 1.4.1 (24 Hz fissi) | 8,7% | 7,8% |
| Aperto, Lumen sveglia, cadenza variabile | 6,3% | 7,0% |
| Aperto con Meteo, Lumen sveglia (entrambe le build) | circa 30% | circa 30% |

Confronta solo righe della stessa misura. I watt non sono mai stati misurati: `powermetrics` richiede `sudo`.

## Registro
Più recente in fondo.

### 2026-11-04 — Lumen
- Scelta della creatura con prototipi HTML, poi FSM e sonno, poi integrazione nell'app.
- Il prototipo interattivo è un artifact: https://claude.ai/artifact/EyMFHxd4ErdakW9VV7T3AK. Può non coincidere più con il codice.
- Provata sul Mac dell'utente: sonno, risveglio, otto movimenti, "Segue il cursore" e tre disposizioni di widget all'avvio.
- Bug corretti: Lumen finiva nell'angolo perché il primo layout non ha ancora le posizioni dei widget; l'ingranaggio le copriva la testa mentre dormiva.

### 2026-11-04 — Prestazioni e layout
- Sostituito `TimelineView` con `LumenClock`: con Lumen addormentata l'app scende da 11,9% a 1,8%, da sveglia da 16,9% a 9,9%.
- Un cambio di layout ora interrompe la mossa corrente (`LumenDirector.adapt`).
- `LumenStage` non ricostruisce più i widget quando Lumen si accende o si spegne.

### 2026-11-05 — Popup della posizione in loop
- Sintomo: il popup ricompariva qualunque cosa si rispondesse. Avveniva con la build Release firmata ad hoc.
- Causa nel codice: ogni apertura del notch con il Meteo visibile richiedeva il permesso se lo stato era `.notDetermined`.
- Mentre il permesso è indeciso, il Meteo usa la posizione da IP e non resta sulla rotellina.
- Prima correzione: richiesta una sola volta, ricordata nelle impostazioni. Sostituita dalla voce seguente.

### 2026-11-05 — Cursore e posizione (00:55–00:56)
Richiesta dell'utente: Lumen non deve seguire il cursore, e il popup in loop e l'uso dell'IP dopo il consenso vanno corretti.

**Cursore**
- Rimossa la mossa `.follow` da `LumenBrain.swift` e `LumenView.swift`, e `onContinuousHover` da `NotchHomeView.swift`. L'utente non l'aveva chiesta.
- Il puntatore serve ancora solo per sonno e risveglio (`pointerStillFor`).

**Posizione** (`WeatherWidget.swift`)
- La richiesta ora avviene una volta **per avvio** (`askedForLocation`). Il flag salvato `weatherLocationAsked` è stato eliminato: dopo un cambio di firma lo stato torna indeciso e il flag bloccava la richiesta, lasciando il Meteo su IP.
- Un risultato da IP arrivato tardi viene scartato se il permesso è attivo e c'è già una posizione del dispositivo.

**Firma, fatti letti da `/var/db/locationd/clients.plist`** (leggibile senza `sudo`)
- `locationd` tiene una sola voce per l'identificativo dell'app, legata a `Requirement = cdhash` e al percorso della build.
- Alle 00:50 la voce era quella della Release in DerivedData, `Authorized = False`. `/Applications/DullNotch.app` e la Debug in DerivedData avevano hash diversi.
- Dopo l'avvio della nuova Debug, la voce è stata sostituita: hash `9ca51cbe…`, `Authorized = True`, posizione ricevuta alle 00:59.
- Non provato: che un rebuild successivo faccia tornare il popup, e che una firma stabile elimini il problema. Il legame con la firma è la causa più probabile, non dimostrata.

**Verifiche**
- Build Debug riuscita. `selfCheck` di Lumen superati con `swiftc -DDEBUG` fuori dall'app.
- Provato dall'utente sulla Debug con firma ad hoc: Lumen non segue più il cursore e la posizione funziona come previsto. La firma stabile resta da fare.
- La build Release in DerivedData è delle 00:48, quindi precede queste modifiche.

### 2026-11-05 — Movimento più naturale
Richiesta dell'utente: Lumen può sparire e riapparire, restare ferma, e deve essere meno prevedibile, **senza toccare le mosse e le animazioni esistenti**.
- Nuove mosse: `.wander` (soste casuali lungo la riga), `.rest` (si posa su un widget, 5–30 s circa), `.absent` (sparisce 2,5–11 s e riappare altrove).
- Le mosse esistenti hanno percorsi e tempi invariati e usano ancora oscillazione, battito d'ali e occhi di prima. Le variazioni organiche valgono solo per pause e nuove mosse (`isUnscripted`).
- Cambia ciò che sta tra le mosse: attese irregolari (70% 1–6 s, 30% 8–24 s), voli di raccordo con curva e velocità casuali (`wander` in `fly`), ricomparsa in un punto casuale invece che sul primo widget.
- Le mosse esistenti escono meno spesso, perché ora si dividono le probabilità con quelle nuove.
- Simulazione di 1 ora con musica attiva, fuori dall'app: tutte le mosse attese compaiono, 20 assenze da 2,6 a 11 s, attesa media 7,7 s, massimo 23,9 s. `sunBump` è fuori perché la simulazione non ha il sole.
- `selfCheck` superati e build Debug riuscita. Resa visiva non ancora valutata nell'app. Per regolare la frequenza si cambia `weight` in `LumenMove`.

### 2026-11-05 — Misura del consumo non riuscita
Confronto tentato tra la Release nuova e quella delle 00:48, con cursore e tasti simulati, a batteria. **Non dà un risultato:** non è servito a dire se il movimento naturale consuma di più.
- Solo la prima prova ha un consumo da notch aperto: app 2,35%, totale con WindowServer 9,29%. Somiglia alla riga "Lumen addormentata" della tabella, quindi probabilmente Lumen non era sveglia.
- Le altre quattro (0,26–0,33%, totale 2,35–2,70%) sembrano a notch chiuso, build vecchia inclusa. Nessuna cifra della vecchia build è confrontabile.
- Lettura del codice, non misura: il timer resta a 24 Hz e il disegno resta limitato alla zona di Lumen. Durante `.absent` il timer continua a girare senza disegnare.

### 2026-11-06 — Barra laterale schiacciata su Widgets
Sintomo: entrando in Widgets la barra laterale delle Impostazioni si sposta contro il bordo sinistro della finestra. Il commento nel `tray` indica una correzione precedente, che non bastava.
- Causa: il riquadro di dettaglio ha 500 pt (finestra 700, barra 200) e la pagina ne chiedeva 514, con l'anteprima del notch larga 780 × 0,6 + 46 di margini. Il divisore passava da 200 a 186.
- Correzioni: `scale` 0,58 in `WidgetsSettings` e `minWidth: 0` sul dettaglio in `SettingsView`. Solo con la scala il divisore restava a 194: un secondo elemento chiedeva circa 506 pt e non è stato identificato.
- Misurato su copie di prova con Widgets, 3 widget e 4/4 di spazio: 186 con la scala 0,6, 194 con 0,58, 200 con 0,58 e `minWidth: 0`, senza contenuti tagliati.
- Non provato: il passaggio a Widgets con un clic (la copia si apre già lì), le altre disposizioni di widget, l'effetto di `minWidth: 0` sulle altre pagine. Non provato dall'utente.
- I puntini bianchi attorno alla finestra nello screenshot dell'utente sono lo sfondo della scrivania, non l'app.
- Su richiesta dell'utente la Release con questa correzione è stata installata in `/Applications`. Prova: firma valida e app viva dopo 7 s. La schermata Widgets non è stata riprovata su questa build.

### 2026-11-08 — Scheda Convert e schede visibili
- Nuova scheda **Convert** (`components/Notch/ConverterView.swift`, aggiunto a pbxproj con ID `C0FFEE…020D/020E`). Converte in locale: immagini con ImageIO (+ PDF via PDFKit), testi con `NSAttributedString` (+ PDF via `NSPrintOperation`). Il file finale si salva con `NSSavePanel`: la sandbox non permette di scrivere accanto all'originale senza consenso. Durante la finestra Salva il notch resta aperto (`SharingStateManager.beginInteraction`).
- `FileConverter` (motore) non dipende dall'app: per provarlo fuori, estrai il file fino a `// MARK: - Model` e compila con `swiftc -DDEBUG -Onone` più un `main.swift` che chiama `FileConverter.selfCheck()` dentro `MainActor.assumeIsolated`. Così è passato: PNG→JPEG/PDF, RTF→TXT/DOCX, TXT→PDF. Il DOCX riletto ha un `\n` finale.
- Schede visibili: chiave `notchTabs` (`[NotchViews]`, default Home, Mixer, MacRemote, Convert: **Shelf nascosto di default**, scelta dell'utente). Home è sempre visibile. Sezione "Notch tabs" in Impostazioni → General, con "i" che usa il tooltip nativo `.help`.
- Con lo Shelf nascosto il trascinamento non apre lo Shelf e non vi aggiunge file (`coordinator.showShelfForDrag()`, `dragDetector` e `openShelfByDefault` controllano `notchTabs`). Se la scheda attiva è Convert, un trascinamento non la cambia. Il rilascio in Convert imposta `vm.dropEvent`, altrimenti il notch si chiude dopo 500 ms.
- Build Debug riuscita. Non provato nell'app: un'altra istanza di prova (non mia) era aperta, quindi non ho lanciato la build. Interfaccia, trascinamento, finestra Salva e tooltip non sono stati visti.

### 2026-11-08 — Trascinamento verso Convert
- Nuova chiave `dragOpensConverter` (default `true`), interruttore in General → "Notch tabs", disattivato se Convert è nascosto. Con l'interruttore attivo, un file trascinato sul notch apre Convert al posto dello Shelf (`coordinator.showViewForDrag()`, ex `showShelfForDrag`), e un rilascio sul notch chiuso va a `ConverterModel.load(providers)` invece che allo Shelf.
- Tutta la vista Convert accetta il rilascio, non solo il riquadro tratteggiato. Se il tipo non è ancora scelto, o c'è già un file caricato, il tipo lo decide il file. Nel riquadro, se hai scelto il tipo a mano, un file dell'altro tipo dà errore.
- Build Debug riuscita, app riavviata (un'istanza). Non provato il trascinamento reale.

### 2026-11-08 — PDF come file di partenza
- L'utente ha trascinato un PDF e ha ricevuto "non leggibile": il PDF era escluso di proposito. Ora è accettato sia con Immagine sia con Testo. Da PDF si va in TXT, RTF, HTML, DOCX, ODT, DOC (testo da `selectionForEntireDocument.attributedString`) e in PNG, JPEG, HEIC, TIFF, GIF, BMP (pagine a 144 dpi con `PDFPage.thumbnail`; TIFF e GIF tutte le pagine, gli altri la prima).
- `PDFDocument` non ha `attributedString`, solo `PDFSelection`/`PDFPage`. Un PDF scansionato non ha testo: messaggio dedicato.
- selfCheck esteso (PDF→TXT, PDF→PNG) e superato fuori dall'app; build Debug riuscita, app riavviata. Non provato con il PDF dell'utente.

### 2026-11-08 — Notch che si chiudeva dopo il rilascio in Convert
- Causa (da lettura del codice): `anyDropZoneTargeting` combina `dropZoneTargeting`, `dragDetectorTargeting` e `generalDropTargeting`. La vista Convert usava un `@State` proprio per il rilascio, quindi sopra Convert tutti e tre erano falsi: dopo 500 ms il task in `ContentView.onChange(of: anyDropZoneTargeting)` chiudeva il notch. Lo Shelf lega il suo `onDrop` a `vm.dragDetectorTargeting`; ora Convert fa lo stesso.
- Comportamento atteso: dopo il rilascio il notch resta aperto finché il cursore non esce. Build Debug riuscita, app riavviata, non provato dall'utente.

### 2026-11-08 — README e GIF di Convert
- `docs/convert.gif` (1100 px, 10 fps, 198 fotogrammi, 3,8 MB) ricavata dalla registrazione dell'utente. ffmpeg e gifski non sono installati: la GIF è fatta con uno script Swift (AVAssetImageGenerator + ImageIO) nello scratchpad, non nel repo.
- README: righe "Convert" e "Notch tabs" in What's new / Novità, sezione "Convert" / "Converti" con la GIF prima di Performance / Prestazioni.

### 2026-11-08 — Test a matrice delle conversioni
- Script nello scratchpad (non nel repo): `Engine.swift` estratto da `ConverterView.swift` fino a `// MARK: - Model` più un `main.swift` che genera sorgenti in ogni formato, converte verso ogni destinazione proposta e rilegge il risultato (tipo, larghezza, fotogrammi GIF/TIFF, testo con `àèìòù €`, grassetto conservato, PDF con testo).
- Sorgenti: PNG, JPEG, HEIC, TIFF e GIF a 3 fotogrammi, BMP, AVIF; TXT, RTF, RTFD, HTML, DOCX, DOC, ODT, webarchive, MD, PDF. Casi limite: zip e PNG corrotto non riconosciuti, PDF accettato da entrambi i tipi, PDF scansionato dà il messaggio giusto. Esito finale 223/223.
- ImageIO **non scrive WebP** (legge sì): provata la lettura con un `.webp` reale trovato sul disco, verso tutti i 7 formati, ok.
- Bug trovati e corretti: (1) da Markdown si perdeva il grassetto, perché `AttributedString(markdown:)` usa `inlinePresentationIntent` e i writer AppKit lo ignorano; ora `styled()` lo traduce in font. (2) `convertImage` apriva ogni immagine con `PDFDocument` prima di controllarne il tipo, e CoreGraphics scriveva un errore nel log; invertito l'ordine.
- Non coperto: la parte UI (finestra Salva, spostamento del file temporaneo, trascinamento), file molto grandi, PDF con molte pagine verso GIF/TIFF.

### 2026-11-08 — Release 1.4.0
- `MARKETING_VERSION` 1.3.0 → 1.4.0 (serve all'avviso aggiornamenti, che confronta il tag con la versione). Release compilata con `-derivedDataPath` nello scratchpad e `ENABLE_HARDENED_RUNTIME=NO`, zip con `ditto -c -k --sequesterRsrc --keepParent`. Prova: versione 1.4.0 nell'Info.plist, MacRemote incluso, `codesign` valido, app viva dopo 7 s.

### 2026-11-08 — La "i" delle Notch tabs non mostrava nulla
- Segnalato dall'utente sulla 1.4.0: `.help()` sull'icona dentro l'etichetta di un `Toggle` in un `Form` non mostra il tooltip. Causa probabile, non verificata: la riga del Form gestisce lei il passaggio del mouse.
- Sostituito con `HoverInfo` (`SettingsView.swift`): popover aperto con `onHover`, sotto l'icona così non la copre. Build Debug riuscita; confermato funzionante dall'utente. Uscito nella **release 1.4.1** (stessa procedura della 1.4.0, app viva dopo 7 s).
- `/Applications/DullNotch.app` sostituita con la Release 1.4.1 (prima c'era una 1.3.0): firma valida, app viva dopo 7 s, una sola istanza.

### 2026-11-11 — Avanzamento nel notch chiuso
Richiesta dell'utente: il notch chiuso mostra da solo ciò che è in corso, con priorità timer, download, ricarica (solo se avanza), quota AI (solo se nient'altro è attivo e il servizio è collegato e aggiornato). Tre stili selezionabili e un interruttore per la precedenza sulla musica.
- **Timer di Orologio senza Accessibilità.** Sono nelle preferenze `com.apple.mobiletimerd`, `MTTimers.MTTimers[].$MTTimer`. In corso: `MTTimerState` 3 e data di fine in `MTTimerFireTime.$MTTimerDate.MTTimerTimeDate`. Fermo: stato 1 e un intervallo al posto della data. Visto su macOS 27.2.1 con un timer reale. Lo legge l'helper XPC (`clockTimer`), perché il file è fuori dalla sandbox. Formato privato: se Apple lo cambia, il timer non compare. Lo stato "in pausa" non è stato osservato e viene ignorato.
- **Download:** entitlement `com.apple.security.files.downloads.read-only`, poi `Progress.addSubscriber(forFileURL:)` su ogni file `.download`, `.crdownload`, `.part` in `~/Downloads`. La sottoscrizione sulla **cartella** non consegna nulla; quella sul **singolo file** sì, anche in sandbox. Senza avanzamento pubblicato vale un file parziale scritto negli ultimi 30 s (anello indeterminato).
- **Ricarica:** `chargingAdvances` chiede un aumento di livello negli ultimi 10 minuti; l'inizio della carica conta come aumento. Con il Mac all'80%, alimentatore collegato e carica ferma non è comparsa, come voluto.
- **Quota AI:** residuo della finestra di 5 ore, solo con `AIUsageManager.state == .ready` e dato più recente di 10 minuti. Il manager si registra come spettatore di `AIUsageManager`, quindi l'interrogazione ogni 2 minuti resta attiva anche senza widget nel notch. Non sostituisce mai la musica.
- **Il filo va disegnato fuori dal notch.** La prima versione era una linea di 2 pt sul bordo inferiore, dentro la sagoma: nelle catture si vedeva, sullo schermo no, perché lì c'è l'alloggiamento della fotocamera (segnalato dall'utente). Ora `NotchOutline` traccia lati e fondo del notch spostati all'esterno di metà spessore (3 pt). Le catture non provano che un elemento dentro la sagoma sia visibile.
- Il filo segue sempre il notch a riposo: centrato, oppure a destra quando l'Ibrida aggiunge l'ala a sinistra. Il timer parte pieno e si svuota (`left / duration`), su richiesta dell'utente; le altre fonti si riempiono.
- Filo, su richiesta dell'utente: 2 pt, sfumatura dal 30% di opacità all'inizio al colore pieno sulla punta (`gradient`, il punto finale segue `fraction`), alone con `.shadow`, rosso sotto il 15% residuo del timer. Visto in una cattura all'84%; rosso e consumo con l'alone non verificati.
- Timer fermato a mano: spariva con fino a 5 s di ritardo (segnalato dall'utente), perché lo stato veniva riletto solo dal tick da 5 s. Ora, mentre un timer è in corso, il tick da 1 s rilegge Orologio tramite l'helper. L'avvio di un timer resta legato al tick da 5 s.
- Un solo tick da 5 s interroga timer e cartella: una novità può comparire con 5 s di ritardo. Il tick da 1 s esiste solo con un timer in corso.
- **Ibrida:** l'ala è solo a sinistra, quindi il notch è spostato di mezza ala (`progressShift`) e il rettangolo centrale usa la larghezza del notch a riposo (`width - 20`), altrimenti il bordo destro sporge.
- Provato con catture (argomento `-hideFromScreenRecording '<false/>'`): i tre stili con il timer, quota AI come ripiego, download simulato al 40%, ritorno alla quota AI a download finito. `selfCheck` di priorità e ricarica superati fuori dall'app (estrarre il file fino a `// MARK: - Live sources`).
- Consumo in Release, notch chiuso, timer in corso, 6 letture: funzione spenta 0,15%, ali 0,68%, filo 0,40%, ibrida 0,47%. Prima della correzione dell'animazione: ali 34%, filo 11%.
- Deviazione dal piano: un file solo invece di due, e la pagina delle impostazioni è nello stesso file.
- In esecuzione resta la build Debug di DerivedData; `/Applications/DullNotch.app` è ancora la 1.4.1 senza questa funzione.

### 2026-11-11 — Lumen: cadenza variabile
Richiesta dell'utente: ridurre il consumo di Lumen con meno fotogrammi e senza orologio a vuoto.
- `LumenDirector.tick` (pubblicato) sostituisce i 24 Hz fissi: 24 Hz per mosse con copione e volo vero (oltre 30 pt/s, tenuti 0,4 s), 15 Hz ferma a mezz'aria o con polvere in caduta, 8 Hz posata senza polvere, 5 Hz addormentata o fuori scena. La scelta è la funzione pura `LumenDirector.tick(...)`, con `assert` nel `selfCheck`.
- **Perché 15 e non 12:** il battito d'ali avanza a 15 passi al secondo, quindi a 15 Hz ogni posa delle ali si vede ancora. Perché mai sotto 5 Hz: `frame(at:)` limita `dt` a 0,25 s, oltre il tempo dell'animazione rallenterebbe.
- **La polvere teneva i 24 Hz quasi sempre:** in volo Lumen ne emette di continuo. Con la regola "effetti = 24 Hz" il risparmio era il 12%. La polvere scende al massimo a 16 pt/s, quindi regge i 15 Hz. La probabilità di emissione era per fotogramma: ora è scalata con `dt`, così la quantità di polvere non cambia con la cadenza.
- Simulazione di 1 ora con musica, fuori dall'app: 62.823 fotogrammi contro 86.400 (−27%); tempo a 24 Hz 41%, 15 Hz 43%, 8 Hz 10%, 5 Hz 6%. Percorsi e tempi delle mosse non sono stati toccati.
- Misura in Release: vedi tabella in "Misure di riferimento". App da 8,7% a 6,3%, WindowServer invariato. Una prova sola per build e il comportamento di Lumen è casuale: il dato è indicativo.
- **Il primo confronto era falso due volte.** Prima il notch della build nuova non si era aperto (app 2,8%): il puntatore era già sopra il notch e non c'è stato l'ingresso. Poi, con entrambe aperte, 30% contro 30,8%: dominava il cielo del Meteo e nascondeva Lumen. Per misurare Lumen togli il Meteo con `-homeWidgets` e fai entrare il puntatore da fuori.
- Per aprire il notch da script ha funzionato: `CGEvent` di tipo `mouseMoved` in cinque passi da (700, 400) a (756, 8), poi piccoli spostamenti ogni 1,5 s. Controlla sempre con una cattura.
- Resa visiva a 15 e 8 Hz non valutata dall'utente.
- Osservato una volta, causa non verificata: dopo molti riavvii ravvicinati il widget AI mostrava "Can't reach Claude".

### 2026-11-11 — Release 1.5.0
- Contiene l'avanzamento nel notch chiuso e la cadenza variabile di Lumen. `MARKETING_VERSION` 1.4.1 → 1.5.0, stessa procedura della 1.4.0. Prova: versione 1.5.0 nell'Info.plist, MacRemote incluso, `codesign` valido, app viva dopo 8 s.
- README: riga in What's new / Novità, sezione "Progress on the closed notch" / "Avanzamento nel notch chiuso" con tre catture dell'utente (`docs/progress-wings.png`, `-wire.png`, `-hybrid.png`), una riga in Performance / Prestazioni.
