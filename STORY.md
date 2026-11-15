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

## Stato attuale (15 novembre 2026)
**Pomodoro** (non ancora in una release; provato dall'utente nell'app): widget piccolo `pomodoro`, tutto in `components/Notch/PomodoroWidget.swift`. Scelta dei tempi, card che si riempie di colore, attesa di una risposta a ogni scadenza, totali a fine sessione. Sul notch chiuso: filo durante il conto alla rovescia, ala sinistra o goccia a destra alla scadenza. Dettagli nel Registro, 2026-11-15.

**Claude Code nel notch chiuso** (release 1.6.0): la mascotte di Claude batte sulla tastiera mentre Claude lavora, festeggia per 20 s quando finisce e resta nascosta mentre aspetta. Codice in `components/Notch/ClaudeAgentStatus.swift`, posizione nelle viste in `ContentView` (`agentVisible`, `agentAlone`). Gli hook li installa l'helper XPC con il pulsante "Connect Claude Code" in Impostazioni → Progress. Sempre l'helper rileva l'interruzione con Esc, leggendo lo stato delle sessioni in `~/.claude/sessions`. Dettagli nel Registro, 2026-11-12.

**Avanzamento nel notch chiuso** (release 1.5.0): una fonte per volta, in ordine di priorità: timer di Orologio, download, ricarica solo se avanza, quota AI. Tre stili (`wings`, `wire`, `hybrid`), pagina Impostazioni → Progress. Tutto in `components/Notch/NotchProgress.swift`; l'aggancio al notch è in `ContentView` (`progressItem`, `progressWings`, `ProgressLiveActivity`). Dettagli nel Registro, 2026-11-11.

**Landing page** in `DullNotchSite/`, pubblicata su https://dullnotch.vercel.app (progetto Vercel `dullnotch`, account personale). Ha un repository suo, privato: `jimmyxan/dullnotch-site`; in questo repository la cartella è in `.gitignore`. Un solo `index.html` senza build, più `assets/`. Dettagli nel Registro, 2026-11-12.

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
- **`NSLog` dall'app arriva come `<private>`** in `log show`. Per un log di prova usa `os.Logger().notice("\(x, privacy: .public)")`.
- **Più sessioni insieme:** altre sessioni possono modificare questi stessi file. Rileggili prima di modificarli e controlla chi è in esecuzione.
- **Prove sulla finestra Impostazioni:** una build nuova non ha l'icona nella barra dei menu su macOS 27, quindi va aperta da codice in una copia dei sorgenti. Usa `orderFrontRegardless()`, non `showWindow()`: con il focus la pagina è cambiata da sola tra l'apertura e la cattura (causa non verificata) e una misura è finita su Media. Guarda sempre la cattura, non solo il numero.

## Lavoro aperto
- Pomodoro: l'utente ha confermato widget, filo, suono e faccia a riposo. Non confermati uno per uno: ala sinistra e goccia alla scadenza, riepilogo, consumo delle onde e della goccia. La sessione si perde chiudendo l'app. Non è in una release: la versione è ancora 1.6.0.
- Mascotte di Claude, non provato: con la musica attiva (prende il posto della copertina), con un timer reale, con due sessioni di Claude Code insieme, un Esc vero dopo il passaggio a `~/.claude/sessions` (vedi Registro, "Esc, seconda versione"), il pulsante Connect/Disconnect nella pagina Progress (la logica è provata fuori dall'app). Restano da fare `dullnotch run <comando>` e lo stato di errore.
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

### 2026-11-12 — Claude Code nel notch chiuso
Richiesta dell'utente: mentre Claude Code lavora, la sua mascotte batte su una tastiera. Quando finisce cambia animazione, resta 20 s e poi sparisce. Mentre aspetta input o un permesso non si vede nulla.
- **Trasporto: notifiche Darwin** (`notifyutil -p dullnotch.agent.working|done|idle`), scelte dall'utente al posto dello schema URL. Non avviano l'app se è chiusa e non aprono un'altra build registrata. `notify_register_dispatch` funziona nella sandbox (stato 0 e notifica ricevuta, verificato con un log).
- Hook in `~/.claude/settings.json` dell'utente, uniti a quelli esistenti (copia prima della modifica nello scratchpad della sessione). `UserPromptSubmit`, `PreToolUse` e `PostToolUse` mandano `working`; `Stop` manda `done`; `Notification` e `SessionEnd` mandano `idle`. Lo stesso blocco, con un pulsante Copia, è in Impostazioni → Progress → Claude Code.
- `working` scade dopo 10 minuti senza eventi, perché un'interruzione con Esc non lancia `Stop`. Lo stato è unico per tutte le sessioni (commento `ponytail:`).
- **Posizione**: Ali, al posto dell'icona; Ibrida, ala destra, e il notch torna simmetrico senza spostamento; Filo con un avanzamento, o nient'altro attivo, ala sinistra con lo scheletro dell'Ibrida; musica, al posto della copertina (scelta dell'utente).
- Sprite 12 × 11 disegnato con `Canvas`, 6 Hz da `Timer.publish` solo mentre è visibile. Nel "finito" saltella per 2 s, poi la vista non si ridisegna più. I pixel si sovrappongono di 0,3 pt: senza, l'antialiasing lasciava righe tra un pixel e l'altro.
- Provato con catture sulla Debug: mascotte da sola, i tre stili con un download simulato (file `.part` toccato), il "finito" e la scomparsa dopo 20 s. Provati anche gli hook reali di questa sessione. Musica non provata.
- Consumo in Release, notch chiuso, 8 letture: app 0,01% senza mascotte, 1,84% mentre batte; WindowServer senza differenze visibili (14% contro 12%, rumore).
- In esecuzione la Debug di DerivedData; `/Applications/DullNotch.app` è ancora la 1.5.0 senza questa funzione.

### 2026-11-12 — Claude Code: hook con un clic e Esc
Richiesta dell'utente: risolvere la mascotte che restava in "working" dopo un Esc, senza configurazioni a mano, così che serva anche ad altri utenti.
- **Esc non lancia nessun hook** (`Stop` no, `StopFailure` è solo per gli errori dell'API). Claude Code però scrive nel transcript `~/.claude/projects/<progetto>/<sessione>.jsonl` una riga `type: user` con `content[0].text` = `[Request interrupted by user…]`, anche nella forma `… for tool use]`. **Dopo quella riga arrivano subito righe di servizio** (`last-prompt`, `ai-title`, `mode`, `system`…): bisogna guardare l'ultima riga `user`/`assistant`, non l'ultima del file. Visto in 6 transcript reali.
- `claudeInterrupted(since:)` nell'helper: considera i `.jsonl` modificati dopo `since` e conta solo un'interruzione con `timestamp` successivo a `since`. Senza questo controllo, un nuovo prompt subito dopo un Esc potrebbe far sparire la mascotte prima che la sua riga arrivi nel transcript. L'app la interroga ogni 2 s, solo in `working`.
- `claudeHooks("status"|"install"|"remove")` nell'helper:
  - segue i symlink e scrive in modo atomico;
  - salva una sola volta `settings.json.dullnotch-backup`;
  - toglie ogni hook che contiene `dullnotch.agent.` prima di aggiungere i suoi, quindi sostituisce anche quelli messi a mano;
  - usa `/usr/bin/notifyutil` con il percorso completo.
  JSONSerialization riordina le chiavi del file (`sortedKeys`), i valori restano uguali.
- Il pulsante Copia e il blocco JSON nelle Impostazioni sono stati tolti: ora c'è "Connect Claude Code" / "Disconnect" con lo stato.
- **Prove**:
  - Logica dell'helper compilata fuori dall'app (estrai la sezione `// MARK: - Claude Code` più `import Foundation` e uno stub `class BoringNotchXPCHelper: NSObject {}`), sui casi seguenti:
    - interruzione seguita da righe di servizio: rilevata;
    - interruzione precedente al turno: ignorata;
    - nuovo prompt dopo l'interruzione: ignorata;
    - testo in un `tool_result`: ignorato;
    - 40 transcript veri: nessun falso positivo.
  - Install, status e remove eseguiti sul `settings.json` vero: le chiavi non-hook sono rimaste uguali, l'hook di codegraph è conservato, remove lascia solo quello. Ora gli hook sono installati.
  - Nell'app: mascotte in "working", riga d'interruzione in una cartella di prova in `projects`, mascotte sparita entro 3,5 s.
  - Helper durante l'interrogazione: 0,45% di un core in Debug.

### 2026-11-12 — Esc, seconda versione, e animazione del martello
- **La lettura dei transcript non bastava.** L'utente ha premuto Esc due volte su questa sessione (prompt delle 20:04:06 e 20:04:16 in `history.jsonl`) e la mascotte è rimasta. Nel transcript, dopo quei prompt, c'è solo `api-request`: **un Esc prima che Claude scriva qualcosa non lascia nessuna riga `[Request interrupted by user]`**. La riga c'è solo se l'interruzione arriva durante un output o un comando.
- **Segnale nuovo: `~/.claude/sessions/<pid>.json`.** Claude Code 2.1.322 tiene un file per ogni sessione aperta, con `pid`, `sessionId`, `status` (`busy`/`idle`), `waitingFor` e `statusUpdatedAt`; il codice del binario lo conferma (`e.status==="busy"`, `e.status==="idle"`). `status` è passato a `busy` nello stesso secondo del prompt.
- **Verificato con un registro in background** (cambi di stato ogni 0,5 s): un Esc riporta `status` a `idle` in circa 3 s; l'utente ha confermato che la mascotte sparisce. Valori visti: `busy`, `shell` (Claude esegue un comando), `waiting` con `waitingFor: "dialog open"`, `idle`. **Contare solo `busy` era sbagliato**: durante un Bash lungo la mascotte sarebbe sparita. Ora l'helper conta tutto ciò che non è `idle`.
- Non sono riuscito a pilotare una sessione interattiva di Claude Code da `expect`: il terminale resta vuoto, anche con un ambiente pulito, mentre `claude -p` funziona.
- L'helper ora ha `claudeBusySessions` al posto di `claudeInterrupted`. Conta i file con `status == "busy"` il cui `pid` è vivo (`kill(pid, 0)`); risponde −1 se la cartella manca, cioè con versioni vecchie, e in quel caso resta solo la scadenza di 10 minuti.
- L'app interroga ogni 2 s mentre è in `working` e nasconde la mascotte dopo **due** controlli di fila senza sessioni occupate. Così un `Stop` che arriva nel frattempo vince, e il "finito" non salta.
- Tolta la lettura dei transcript e il controllo del `timestamp`.
- **Animazione**: in `working` si sceglie a caso, a ogni nuovo turno, tra tastiera e martello (proposta A dell'anteprima https://claude.ai/artifact/ERqsdEv8ChmpNFCQcvQyzJ). La scelta sta in `ClaudeAgentStatus.hammers`, non nella vista, perché la vista si ricrea quando cambia il layout del notch. Il martello: su, su, metà, colpo, colpo, metà a 6 Hz, cioè un colpo al secondo; al colpo scintille, blocco illuminato, occhi socchiusi. Viste entrambe nelle catture.
- **Fine lavoro**: a ogni "finito" si sceglie a caso tra i saltelli e il caffè, la proposta 3 dell'anteprima https://claude.ai/artifact/1cnjbRRnEWtbkVL3Q6C8WK. La scelta sta in `ClaudeAgentStatus.coffee`.
  - Caffè: tazza fumante con il vapore che alterna due posizioni, occhi socchiusi, un sorso tra il fotogramma 8 e l'11, quando la tazza sale e il vapore si ferma.
  - **L'animazione di fine lavoro dura tutti i 20 s.** Segnalato dall'utente: "resta fermo con le braccia su". I saltelli duravano 2 s e poi la posa restava ferma per 18 s, quindi sembrava bloccata. Ora c'è un saltello al secondo (fotogrammi 3–4 di ogni 6) e il caffè beve un sorso ogni 4 s, a 6 Hz come in "working".
  - Trappola nelle prove: una serie di catture ravvicinate cadeva ogni volta sullo stesso fotogramma e sembrava un blocco. Il log del contatore mostrava invece che avanzava. Prima di dire "è bloccato", controlla il contatore.
  - Verificato con 25 catture 10 s dopo il "finito": la posa cambia. Il caffè lungo tutti i 20 s non è stato visto.

### 2026-11-12 — Verifica complessiva e release 1.6.0
- **Revisione** delle interazioni con le viste esistenti. Corretti tre punti:
  - **Interruttore spento**: `set()` torna subito a `hidden`, così l'helper non viene più interrogato.
  - **HUD in linea** (volume, luminosità) con la mascotte da sola o con l'Ibrida: il notch era spostato di mezza ala anche sotto l'HUD. Ora `progressShift` vale 0 mentre l'HUD è visibile (`inlineHUDShowing`). Il difetto c'era già con l'Ibrida della 1.5.0. Non provato con un HUD vero.
  - **Commento in testa** a `ClaudeAgentStatus.swift`: era rimasto vecchio.
- **Accettato, non corretto**:
  - se la musica è attiva ma `expandingView` mostra altro (né musica né batteria), non compare né la musica né la mascotte;
  - dopo ogni richiesta di permesso l'animazione di lavoro viene riestratta;
  - lo stato resta unico per tutte le sessioni.
- **Regressione** con catture sulla Debug: Ali, Filo e Ibrida con un download simulato, mascotte da sola, interruttore spento con `-claudeAgentEnabled '<false/>'` (nessuna mascotte). Tutto come prima.
- **Release 1.6.0**:
  - `MARKETING_VERSION` 1.5.0 → 1.6.0 in quattro punti.
  - Stessa procedura della 1.4.0, con l'helper XPC e MacRemote inclusi.
  - `codesign` valido; app viva dopo 8 s, un'istanza.
  - Mascotte al lavoro: 1,70% di un core in Release.
- **README**: riga in What's new / Novità, sezione "Claude Code on the closed notch" / "Claude Code nel notch chiuso", una riga in Performance / Prestazioni. Senza immagini.
- `/Applications/DullNotch.app` sostituita con la 1.6.0, estratta dallo zip della release: firma valida, app viva dopo 8 s, un'istanza, mascotte visibile.
- README: `docs/claude-code.gif` (934 × 216, 12 fps, 202 fotogrammi, 358 KB) ricavata dal video dell'utente `mergedVIDEO.mp4`. Il video non è nel repo (non tracciato). La GIF è fatta con uno script Swift (AVAssetImageGenerator + ImageIO) nello scratchpad, come quella di Convert.

### 2026-11-12 — Landing page
- `DullNotchSite/index.html`: pagina statica in inglese, CSS e JS nel file, nessuna dipendenza oltre al font Bricolage Grotesque da Google Fonts. Le immagini in `DullNotchSite/assets/` sono **copie** di quelle in `docs/`, così la cartella si pubblica da sola: se cambi una cattura in `docs/`, ricopiala.
- L'hero è un notch funzionante: si apre al passaggio del puntatore o al tocco, ha le schede Home, Mixer e Convert, e i pulsanti sotto lo schermo avviano timer, download e mascotte di Claude Code nei tre stili. Gli sprite della mascotte sono copiati da `ClaudeAgentStatus.swift`: se cambiano nell'app, la pagina non li segue.
- Il 3D è solo CSS, niente three.js. Vedi la voce "Landing page: 3D con lo scroll".
- I consumi nella pagina vengono da README e "Misure di riferimento". Nella demo i brani sono reali (titolo, durata e copertina da iTunes Search API, copertine 300 px in `assets/covers/`: sono immagini protette da copyright, scelta dell'utente); città, meteo ed eventi del calendario sono inventati.
- Provato in Chromium con Playwright a 1360 e 390 px: apertura, schede, timer con Ibrida, download fino alla fine, mascotte disegnata, nessun errore in console, nessuno scorrimento orizzontale. Non provato: Safari, Firefox, tocco reale, tastiera, il cursore verticale del Mixer fuori da Chromium.
- Filo della demo rifatto sulla ricetta di `NotchProgressWire` (traccia nera più tinta al 18%, linea da 2 pt con estremità tonde, sfumatura che finisce sulla punta, alone solo sulla linea). In stile Wire l'icona restava visibile nel notch: la regola che la nascondeva perdeva per specificità. Visto in Chromium, non in Safari. Differenza rimasta: in Wings il download mostra la percentuale, l'app un anello.
- 2026-11-15: con "Run Claude Code" il notch della demo si allargava da entrambi i lati (268 px centrati). Ora ha la sola ala sinistra, come nell'app e come Hybrid: 232 px spostati di 18 px a sinistra. Non provato in un browser, non ripubblicato su Vercel.

### 2026-11-12 — Landing page: 3D con lo scroll
Richiesta dell'utente: il MacBook che si apre scorrendo e il notch esploso a strati, adattati a schermi e dispositivi diversi.
- **MacBook**: `.stage` diventa una pista alta 190svh con dentro `.pin` in `position: sticky`. `onScroll` legge una volta la posizione e scrive variabili CSS (`--lid`, `--tilt`, `--yaw`, `--s`, `--ty`). Due tempi: il coperchio si apre mentre il portatile scende a metà schermo, poi la camera stringe sul notch. L'ultimo 20% della pista è fermo, per usare la demo.
- **Arrivo (`is-live`)**: le trasformazioni 3D vengono tolte e base e retro del coperchio nascosti. Serve perché sfocatura del vetro e puntatore lavorino su un livello piatto; nell'ultimo fotogramma le trasformazioni sono già l'identità, quindi il passaggio non si vede.
- **Adattamento**: la scala iniziale è il minimo tra tre limiti (fisso, larghezza, altezza della finestra), così il portatile entra sempre. Sui telefoni lo schermo è largo almeno 560 px e all'arrivo esce dai bordi: il notch resta in px veri e toccabile. Il 3D si attiva solo con finestra alta almeno 620 px e movimento consentito (`want3d`); altrimenti resta la pagina piatta di prima, con il suo ingresso.
- **Trappola**: `overflow-x: hidden` su `body` insieme a `overflow-x: clip` su `html` rompe lo sticky (il body diventa un contenitore di scorrimento). Entrambi devono essere `clip`.
- **Trappola nelle prove**: con `scroll-behavior: smooth` uno `scrollTo` da script è ancora in corso dopo 500 ms; un clic fatto prima della fine viene poi annullato dall'apertura automatica. Non è un difetto della pagina.
- **Notch esploso**: sezione dopo l'hero, quattro strati in vista isometrica (`.stack`), separati da `--e` che segue lo scorrimento. La legenda evidenzia uno strato al passaggio o al focus. Senza pin.
- Provato in Chromium: 1360×850 (chiuso, metà, arrivo, timer Ibrida), 390×800 (metà e arrivo, nessuno scorrimento orizzontale), 800×400 (ripiego piatto), nessun errore in console. Non provato: Safari, Firefox, tocco reale, fluidità su un telefono vero, `prefers-reduced-motion`.

### 2026-11-12 — Landing page: modello 3D vero del MacBook
Richiesta dell'utente: il portatile fatto in CSS era brutto; usare il modello che ha messo in `DullNotchSite/macbook-pro-m3-16-inch-2024/` (file `.blend` da Sketchfab più texture).
- **Conversione**: un browser non legge `.blend`. Blender 4.1 è in `/Applications`; `export-glb.py` (nella cartella del modello) si lancia con `Blender -b <file.blend> --python export-glb.py -- <uscita.glb>`. Toglie il cubo di ingombro, crea un nodo `Lid` sull'asse della cerniera con dentro le parti del coperchio, lo mette verticale, rinomina lo schermo in `Screen`, esporta con texture WebP e compressione Draco. Risultato `assets/macbook.glb`, 888 KB (5,5 MB senza Draco: il peso era la geometria, non le texture).
- **Pagina**: three.js 0.160 da jsDelivr con import dinamico, solo quando il 3D è attivo. Il portatile CSS è stato tolto. Il modello è disegnato su `#gl`; lo schermo HTML resta fermo nella posizione finale e invisibile.
- **Aggancio**: la camera finisce dritta davanti allo schermo, alla distanza in cui un'unità del modello copre gli stessi pixel dello schermo HTML (`gl.frame`). Poi lo schermo HTML compare sopra il modello e il canvas sparisce. Sullo schermo del modello è dipinta una copia dello sfondo (`paintWall`: sfumatura, archi, notch chiuso, barra dei menu). Gli archi CSS restano in pausa sul primo fotogramma fino all'arrivo, altrimenti non coincidono. Se cambi sfondo o archi in CSS, aggiorna `paintWall`.
- **Trappola**: `Box3.setFromObject(screen)` senza `true` dà una scatola troppo profonda, perché la mesh è inclinata dentro il suo nodo: la camera finiva l'11% troppo lontana.
- **Ripiego**: se three.js o il modello non si caricano, la pagina torna piatta. **Aprendo `index.html` come file il modello non si carica** (il browser blocca la lettura): serve un server, per esempio `python3 -m http.server` nella cartella del sito.
- Provato in Chromium: 1360×850 (chiuso, in apertura, aperto, arrivo, dissolvenza: schermo del modello e HTML coincidono al pixel) e 390×800 (metà e arrivo), nessun errore in console. Non provato: Safari, Firefox, telefono vero, ripiego senza WebGL.
- **Da chiarire con l'utente**: licenza e autore del modello (nessun file di licenza nella cartella). La cartella sorgente (11 MB) non va pubblicata.
- Controlli sotto lo schermo: in 3D ora stanno subito sotto lo schermo (`--pt`, calcolata in `onScroll`), non più in fondo al pin: su finestre alte restava un vuoto. Pulsanti e selettori ingranditi. **Trappola**: `font: … inherit` nella forma abbreviata non è valido e il browser scartava tutta la dichiarazione, quindi i pulsanti usavano il font piccolo di sistema (molto evidente in Safari). Visto in Chromium a 1250×1210.
- Pulsanti di download: al caricamento la pagina chiede a `api.github.com/…/releases/latest` il primo asset `.zip` e lo mette come `href`, così il clic scarica subito. Il nome del file contiene la versione, quindi `releases/latest/download/<nome>` non si può usare. Se l'API non risponde (limite: 60 richieste l'ora per IP) resta il link alla pagina della release. Verificato in Chromium: entrambi i pulsanti puntano a `DullNotch-1.6.0.zip`; il download vero non è stato avviato.

### 2026-11-12 — Landing page su Vercel
- Pubblicata in produzione con `vercel deploy --prod --yes --name dullnotch` da `DullNotchSite/`. La cartella è collegata al progetto (`.vercel/`, ignorata da git con il `.gitignore` creato dalla CLI). Non è collegata a GitHub: ogni aggiornamento va ripubblicato a mano con `vercel deploy --prod` dalla stessa cartella.
- `.vercelignore` esclude `macbook-pro-m3-16-inch-2024` (sorgente del modello). Verificato: `https://dullnotch.vercel.app/` e `/assets/macbook.glb` rispondono 200, il sorgente 404.
- Non verificato: la pagina pubblicata aperta in un browser (solo risposte HTTP).

### 2026-11-15 — Notch esploso: partenza ritardata
- Richiesta dell'utente: l'esplosione partiva troppo presto e si vedeva poco. Prima `--e` andava da 0 a 1 con il bordo alto di `.explode` tra il 92% e il 32% della finestra, quindi metà animazione era fuori vista. Ora tra il 65% e il 15% (`onScroll`). Non provato in un browser.

### 2026-11-15 — Sito in un repository separato
- `DullNotchSite/` ha un `.git` suo, con remoto `jimmyxan/dullnotch-site` (privato, ramo `main`, un commit del 2026-11-12). Qui la cartella è in `.gitignore`.
- Il sorgente del modello (`macbook-pro-m3-16-inch-2024`, 11 MB) è tracciato nel repository del sito; `.vercelignore` lo tiene fuori dalla pubblicazione.
- Collegamento Vercel ↔ GitHub: lo fa l'utente. Finché non c'è, vale ancora `vercel deploy --prod` a mano.
- **Trappola**: `.claude/hooks/story-check.sh` usa `git rev-parse --show-toplevel`. Con la shell dentro `DullNotchSite/` la radice diventa quella del sito, dove `STORY.md` non esiste, e l'hook segnala a ogni stop. Dalla radice invece non vede le modifiche al sito. Non corretto.

### 2026-11-15 — Pomodoro
Richiesta dell'utente: widget piccolo in stile "Livello" (scelto tra tre bozze HTML), tempi di focus e pausa, +5 minuti alla scadenza del focus, conferma dopo la pausa, fine sessione con i totali.
- **Logica**: `PomodoroSession`, struct pura in cima a `PomodoroWidget.swift`; ogni cambio riceve `now`. Fasi: `setup`, `focus`, `focusDone`, `rest`, `restDone`, `summary`. Nessuna fase passa alla successiva da sola. I totali contano solo il tempo trascorso davvero: non le pause del timer, non il tempo oltre la scadenza. `selfCheck` in Debug; la parte fino a `// MARK: - Live` si compila da sola con `swiftc -DDEBUG` (fatto: passa).
- **`PomodoroManager`**: pubblica `session` solo ai cambi di stato e `wire` a passi dello 0,5%. Il tick da 1 s vive solo mentre un tratto scorre. La card usa `TimelineView(.periodic)` da 1 s solo a notch aperto, per i numeri.
- **Notch chiuso, conto alla rovescia**: nuova fonte `ProgressSource.pomodoro`, prima per priorità, sempre disegnata come filo qualunque sia lo stile (`progressWings` la scarta). Non ha interruttore tra le fonti (`ProgressSource.optional`): segue solo "Show progress on the closed notch". Finché un tratto è in corso, timer e download non si vedono. In pausa il filo resta fermo.
- **Notch chiuso, scadenza** (`pomodoroWaiting`, `pomodoroAlone` in `ContentView`): se nessuno occupa le ali si apre la sinistra con `PomodoroWingGlyph` (la card in miniatura che si riempie). Altrimenti `PomodoroDrip`: una goccia si gonfia sotto l'estremità destra del notch, cade e svanisce, in ciclo. Arancione dopo il focus, verde dopo la pausa. Alla scadenza la fonte del filo si spegne, quindi le altre fonti tornano visibili.
- `AgentLiveActivity` è diventata `LeftWingActivity { … }`, usata da mascotte e Pomodoro.
- Tempi scelti salvati in `pomodoroFocusMinutes` e `pomodoroBreakMinutes`. La sessione è solo in memoria.
- **Provato**: `selfCheck` fuori dall'app; build Debug riuscita. **Non provato**: l'app non è mai stata avviata con questa modifica. Mai visti: la card nei suoi stati e se entra in altezza, i pulsanti, il filo, l'ala, la goccia (posizione sotto il notch e se viene tagliata), la tessera in Impostazioni → Widgets. Consumo di `keyframeAnimator` durante l'attesa non misurato.
- **Suono a fine focus** (richiesta dell'utente, "simile ad Apple Pay"): `PomodoroChime`, due note di campana in salita (Mi6, Si6) generate in memoria come WAV, nessun file audio nell'app. Suona solo quando un focus scade, non la pausa. `NSSound(data:)` creato a ogni riproduzione e senza dispositivo impostato: usa l'uscita predefinita del Mac in quel momento. Non usare `AudioServicesPlaySystemSound`: va sul dispositivo degli effetti sonori, che può essere un altro. Verificato: il WAV è valido (`afinfo`: mono, 44,1 kHz, 0,95 s). Non verificato da me: l'ascolto e il dispositivo.
- **Onde** (`PomodoroSurface`): la superficie del colore è fatta di due onde che scorrono in versi opposti mentre un tratto corre, ferme in pausa. Ogni onda è lunga due card e si anima solo lo spostamento di una larghezza, così il tracciato non si ricalcola e il ciclo non ha giunture. Consumo non misurato.
- **Prova rapida**, solo Debug: `open DullNotch.app --args -pomodoroDebugFocus 3` avvia un focus di 3 minuti al lancio.

- **Faccia a riposo** (richiesta dell'utente, seconda versione): senza sessione la card non deve sembrare avviata. Mostra "Start your focus" nel serif leggero del widget Quote, una riga con i tempi scelti e, sul fondo, un alone sfocato arancione fermo (`PomodoroCard(glow:)`), niente livello né onde. La scelta dei tempi e Start compaiono al passaggio del puntatore e spariscono quando esce; un clic la fissa. La prima versione (numero grande e fondo di liquido) è stata scartata: sembrava un timer già partito. Durante un tratto il colore non scende sotto `PomodoroCard.base` (10%). Build riuscita, non vista da me.

### 2026-11-15 — Impostazioni → Widgets: vassoio su due righe
Richiesta dell'utente: i widget disponibili erano su una riga sola da scorrere. Ora `tray` li divide in due righe di lunghezza simile (la prima prende widget finché ha metà della larghezza totale) e il vassoio è alto il doppio. Lo scorrimento orizzontale resta, per quando due righe non bastano. Build riuscita, non visto da me.

### 2026-11-15 — Pomodoro: README e installazione
- README (inglese e italiano): riga in tabella, paragrafo e `docs/widget-pomodoro.png`. L'immagine **non è una cattura**: è disegnata dalle viste vere con `ImageRenderer`, da uno script nello scratchpad che compila `PomodoroWidget.swift` insieme a controfigure di `ProgressItem`, `NotchProgressLogic.clock` e `WidgetCard`, e al modulo `Defaults` preso dai prodotti della build (`-I …/Build/Products/Debug` più `Defaults.o`). Utile per altre anteprime di widget senza aprire il notch. Se cambia il widget, l'immagine non lo segue.
- `/Applications/DullNotch.app` sostituita con una Release compilata dai sorgenti di oggi (procedura della 1.4.0): versione ancora 1.6.0, `codesign` valido, MacRemote incluso, app viva dopo 9 s, un'istanza. L'avviso aggiornamenti non la distingue dalla 1.6.0 pubblicata.

