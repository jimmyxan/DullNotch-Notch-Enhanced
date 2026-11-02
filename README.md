<div align="center">

<img src="docs/icon.png" alt="DullNotch-Notch Enhanced icon" width="128" height="128">

# DullNotch-Notch Enhanced

**A Liquid Glass remake of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) for macOS 26 and later.**<br>


[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-black.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B%20·%20Liquid%20Glass%2026%2B-black.svg)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange.svg)](https://developer.apple.com/swift/)

[English](#english) · [Italiano](#italiano)

<br>

<img src="docs/home.png" alt="Open notch with Liquid Glass: Now Playing, calendar and weather widgets" width="860">

<br><br>

<table>
  <tr>
    <td align="center" width="60%">
      <img src="docs/mixer.png" alt="Mixer tab: one vertical fader per app playing sound" width="100%"><br>
      <sub><b>Mixer</b>: per-app volume, powered by OpenSoundSource</sub>
    </td>
    <td align="center" width="40%">
      <img src="docs/hud-settings.png" alt="HUD settings with color presets and live preview" width="85%"><br>
      <sub><b>HUD</b>: color presets, custom color, live preview</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="60%">
      <img src="docs/macremote.png" alt="MacRemote tab: pairing QR code with Copy link, New code and Stop" width="100%"><br>
      <sub><b>MacRemote</b>: control the Mac from your iPhone, paired from the notch</sub>
    </td>
    <td align="center" width="40%">
      <img src="docs/widgets-settings.png" alt="Widgets settings: drag-and-drop preview of the notch with a tray of available widgets" width="85%"><br>
      <sub><b>Widgets</b>: drag and drop to build your home</sub>
    </td>
  </tr>
</table>

</div>

---

## English

DullNotch-Notch Enhanced is a personal remake of **[Boring Notch](https://github.com/TheBoredTeam/boring.notch)** by TheBoredTeam. It keeps everything that makes the original great (music, calendar, shelf, HUDs, smooth Apple-style animations) and redesigns the look for the Liquid Glass era, plus a few new features.

> This is not a fork and is not affiliated with TheBoredTeam. All credit for the original app goes to them. The project stays under the same **GPL-3.0** license.

### Quick install

Download the latest release, no Xcode needed:

1. Open the **[latest release](https://github.com/jimmyxan/DullNotch-Notch-Enhanced/releases/latest)** and download `TheBoringNotch-x.y.z.zip` under *Assets*.
2. Unzip it and drag **TheBoringNotch.app** into your **Applications** folder.
3. If the original Boring Notch is installed, quit it and move it to the Trash: both apps share the same bundle identifier.
4. Open the app. It is not notarized by Apple, so the first launch is blocked: go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to TheBoringNotch, then confirm.
   Prefer the Terminal? Run `xattr -dr com.apple.quarantine /Applications/TheBoringNotch.app` and open the app normally.
5. The app lives in the notch and in the **menu bar** (no Dock icon). Use the menu bar item to open **Settings** or **Quit**.
6. Grant permissions when you need them:
   - **Accessibility**, to replace the system volume and brightness HUD (Settings › HUDs).
   - **Audio capture**, asked the first time you move a fader in the Mixer.
   - **Calendar**, to show your events.
   - **Bluetooth**, for the battery widget (AirPods, headphones, speakers).
   - **Location**, for the weather widget. Without it the weather uses an approximate position from your IP address.
   - **Accessibility for MacRemote**, the first time you start it from the notch (it is a separate helper app).

To update, download the newest release and replace the app in Applications. Afterwards, remove and re-add the app under *Accessibility*: macOS ties the permission to the exact build.

### What's new

| | |
|---|---|
| **Liquid Glass** | The open notch becomes real system glass (`glassEffect`), adapting live to the wallpaper and the apps underneath. The closed notch stays pure black so it blends with the hardware notch. |
| **Glass intensity** | A 0–100% slider. 0% is the classic black look; 100% uses the clearer glass variant. |
| **Seamless top edge** | The black band under the physical notch melts into the glass with an eased gradient: no visible seam. |
| **Readable by design** | A dimming floor keeps text legible on any background. *Reduce Transparency* switches back to solid black; *Increase Contrast* raises the floor. |
| **HUD colors** | Volume, brightness and keyboard HUDs: white, system accent, 11 macOS system colors or any custom color, with gradient, glow and a live preview. |
| **Mixer** | A new notch tab with one vertical fader per app playing sound (0–150%), native and driver-free. See below. |
| **Spotify everywhere** | Shows what you are playing on your phone, speakers or TV, even with the Spotify app closed on the Mac. Works with **Spotify Free**, through Last.fm. |
| **Quiet idle state** | When nothing plays on any device, a calm Spotify card replaces the placeholder track. |
| **Home widgets** | Build the home like an iPhone widget stack: Music, Calendar, Bluetooth battery, Weather and Mirror. Up to 1 large + 2 small; the notch resizes to fit. |
| **Bluetooth battery** | AirPods and Beats show left, right and case; other headphones and speakers show one percentage. |
| **Weather** | Apple-style card with the sky and motion of the current condition. Can stand in for the battery widget while nothing is connected. |
| **MacRemote** | A new notch tab that starts **[MacRemote](https://github.com/jimmyxan/MacRemote)** and shows the QR code to pair your iPhone. Bundled with the app. |

### Home widgets

<img src="docs/weather-offline.png" alt="Home widgets with the weather widget offline: the Claude Code mascot crying under a rain cloud" width="860">

The home of the open notch is a set of widgets you choose and arrange in **Settings › Widgets**:

- **Drag and drop on a live preview**: drag a widget from the tray into the notch, drop it on another widget to swap them (or to replace it when there is no room), drag it back to the tray to remove it. A list below does the same for keyboard users.
- **Size budget**: Music is large, the others are small, and the home holds up to **1 large + 2 small**. The notch grows and shrinks with what you put in it.
- **Bluetooth battery**: an animated ring with the level of the connected device. Click it with AirPods or Beats connected to open a detail view with **Left**, **Right** and **Case** (the case only appears while it is nearby and reporting).
- **Weather**: data from [Open-Meteo](https://open-meteo.com) (free, no API key). Rain, snow, thunderstorms, clouds and fog are animated, gently. Location comes from Location Services, or from your IP address if you don't allow it; you can grant it again or refresh from Settings. With no internet connection the widget shows the Claude Code mascot crying under a rain cloud (above).
- **Weather when nothing is connected** (on by default): while no Bluetooth device is connected, the battery widget is replaced by the weather, and it comes back as soon as a device connects.

### MacRemote

The **MacRemote** tab, next to the Mixer, integrates **[MacRemote](https://github.com/jimmyxan/MacRemote)** ([macremote.it](https://www.macremote.it)), my app to control the Mac from an iPhone over the local network: volume, media, brightness, keyboard, touchpad and more, from a web page in Safari. Nothing to install on the phone.

- **Included in every install**: MacRemote is built from its own repository (a git submodule) and shipped inside `TheBoringNotch.app`. There is nothing else to download.
- **Start → scan → done**: press **Start MacRemote**, scan the QR code with the iPhone camera (same Wi-Fi), and the remote opens.
- **Copy link**, **New code** (phones paired with the old link stop working) and **Stop** (MacRemote quits completely).
- If you already run a standalone MacRemote, the tab uses that one instead of starting a second copy.
- MacRemote runs as its own app, because it needs permissions the sandboxed notch cannot have (simulating keys and pointer, screen preview). macOS asks for **Accessibility** for MacRemote the first time.

If you find MacRemote useful, a ⭐ on [its repository](https://github.com/jimmyxan/MacRemote) helps.

### Mixer: native OpenSoundSource engine

The Mixer tab is built on the audio engine of **[OpenSoundSource](https://github.com/jimmyxan/OpenSoundSource)**, my per-app volume app for the menu bar. It is integrated natively, not as a plugin or a separate process:

- **CoreAudio process taps** (macOS 14.2+), no virtual audio driver to install.
- **Helper processes are grouped under their app**: Safari (WebKit GPU process), Chrome, Teams and Electron apps show up as one fader, a problem already solved in OpenSoundSource.
- **0–150%** with a magnetic snap at 100% and a soft-knee limiter, so boosted audio does not clip.
- **Zero cost at 100%**: the tap is removed when an app is back at unity gain.
- **Follows your devices**: volumes carry over when the default output changes, for example when you put on AirPods.
- **Fine control in a small space**: relative dragging (the knob never jumps), hold **⌥ Option** for 4× finer steps, click the percentage to reset, click the icon to mute.

The first time you move a fader, macOS asks for permission to capture app audio.

### Performance

- The glass is composited by WindowServer: no screen capture and no per-frame CPU work. It exists only while the notch is open and the slider is above 0%.
- The Mixer polls once per second only while its tab is visible, every 3 s while a custom volume is active, and not at all otherwise.
- With Spotify closed, Last.fm is checked every 15 s while music plays and every 60 s when idle. Spotify is never launched in the background.

### Spotify on other devices with Last.fm (tutorial)

Spotify's own Web API now requires Premium. Last.fm does not: Spotify sends your plays to Last.fm from every device, Free accounts included.

1. **Create a Last.fm account** at [last.fm/join](https://www.last.fm/join) (skip if you have one).
2. **Connect Spotify**: open [last.fm/settings/applications](https://www.last.fm/settings/applications) and click **Connect** next to *Spotify Scrobbling*.
3. **Get a free API key**: go to [last.fm/api/account/create](https://www.last.fm/api/account/create). Enter any application name (for example *TheBoringNotch*) and a short description. Leave *Callback URL* empty. Submit and copy the **API key**. You do not need the *Shared secret*: do not paste it anywhere.
4. **Set up the notch**: open the notch settings › **Media**, set **Music Source** to **Spotify**, then fill **Last.fm username** and **Last.fm API key** in *Spotify on other devices*.
5. **Try it**: close Spotify on the Mac and play something on your phone. Within about 15 seconds the notch shows the track. Your Last.fm profile should say *Scrobbling now*.

Good to know:
- Read-only: track, artist, album and artwork. Progress is estimated. Playback controls work only when the Spotify app is open on the Mac (no Premium needed).
- When you pause, Last.fm keeps the track as *now playing* for a few minutes.
- Your API key is stored only in the app's local preferences, never in this repository.

### Requirements

- macOS 14 or later. Liquid Glass needs macOS 26; on older systems the notch uses the classic blur.
- Mixer: macOS 14.2 or later.
- Xcode 26 to build.

### Build from source

```bash
git clone --recursive https://github.com/jimmyxan/DullNotch-Notch-Enhanced.git
cd DullNotch-Notch-Enhanced
open boringNotch.xcodeproj
```

Already cloned without `--recursive`? Run `git submodule update --init`. The build compiles the MacRemote submodule with Swift Package Manager and embeds it.

Select the `boringNotch` scheme and press **Run**. Accessibility permission is required to replace the system HUD.

> Automatic update checks are disabled: the bundled Sparkle feed belongs to the original Boring Notch and would replace this build.

### Credits

- **[Boring Notch](https://github.com/TheBoredTeam/boring.notch)** by TheBoredTeam and contributors: the original app this remake is built on.
- **[OpenSoundSource](https://github.com/jimmyxan/OpenSoundSource)**: the per-app volume engine behind the Mixer.
- **[MacRemote](https://github.com/jimmyxan/MacRemote)** ([macremote.it](https://www.macremote.it)): the iPhone remote behind the MacRemote tab, included as a submodule.
- Weather data by **[Open-Meteo](https://open-meteo.com)** (CC BY 4.0); IP location fallback by [ipwho.is](https://ipwho.is).
- Licensed under **GPL-3.0**, like the original. See [LICENSE](LICENSE) and [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).

---

## Italiano

DullNotch-Notch Enhanced è un remake personale di **[Boring Notch](https://github.com/TheBoredTeam/boring.notch)** di TheBoredTeam. Mantiene tutto ciò che rende ottimo l'originale (musica, calendario, shelf, HUD, animazioni fluide in stile Apple) e ridisegna l'aspetto per l'era Liquid Glass, con qualche funzione nuova.

> Non è un fork e non è affiliato a TheBoredTeam. Tutto il merito dell'app originale va a loro. Il progetto resta sotto la stessa licenza **GPL-3.0**.

### Installazione rapida

Scarica l'ultima release, senza bisogno di Xcode:

1. Apri l'**[ultima release](https://github.com/jimmyxan/DullNotch-Notch-Enhanced/releases/latest)** e scarica `TheBoringNotch-x.y.z.zip` sotto *Assets*.
2. Estrai lo zip e trascina **TheBoringNotch.app** nella cartella **Applicazioni**.
3. Se hai installato il Boring Notch originale, chiudilo e spostalo nel Cestino: le due app usano lo stesso identificativo.
4. Apri l'app. Non è notarizzata da Apple, quindi il primo avvio viene bloccato: vai in **Impostazioni di Sistema › Privacy e sicurezza**, scorri in basso e premi **Apri comunque** accanto a TheBoringNotch, poi conferma.
   Preferisci il Terminale? Esegui `xattr -dr com.apple.quarantine /Applications/TheBoringNotch.app` e apri l'app normalmente.
5. L'app vive nel notch e nella **barra dei menu** (nessuna icona nel Dock). Dall'icona nella barra dei menu apri le **Impostazioni** o **esci**.
6. Concedi i permessi quando servono:
   - **Accessibilità**, per sostituire le HUD di volume e luminosità di sistema (Impostazioni › HUDs).
   - **Cattura audio**, richiesta la prima volta che muovi uno slider nel Mixer.
   - **Calendario**, per mostrare i tuoi eventi.
   - **Bluetooth**, per il widget batteria (AirPods, cuffie, casse).
   - **Posizione**, per il widget meteo. Senza permesso il meteo usa una posizione approssimata dall'indirizzo IP.
   - **Accessibilità per MacRemote**, la prima volta che lo avvii dal notch (è un'app di supporto separata).

Per aggiornare, scarica la release più recente e sostituisci l'app in Applicazioni. Poi rimuovi e riaggiungi l'app in *Accessibilità*: macOS lega il permesso alla build esatta.

### Novità

| | |
|---|---|
| **Liquid Glass** | Il notch aperto diventa vero vetro di sistema (`glassEffect`), che si adatta in tempo reale allo sfondo e alle app sottostanti. Il notch chiuso resta nero pieno, così si fonde con il notch fisico. |
| **Intensità del vetro** | Uno slider da 0 a 100%. Lo 0% è il classico nero; il 100% usa la variante di vetro più trasparente. |
| **Bordo superiore senza stacchi** | La fascia nera sotto il notch fisico sfuma nel vetro con un gradiente morbido: nessuna linea visibile. |
| **Leggibile per design** | Uno strato scuro minimo mantiene i testi leggibili su qualsiasi sfondo. *Riduci trasparenza* torna al nero pieno; *Aumenta contrasto* scurisce di più. |
| **Colori HUD** | HUD di volume, luminosità e tastiera: bianco, accento di sistema, 11 colori di sistema macOS o qualsiasi colore personalizzato, con gradiente, glow e anteprima dal vivo. |
| **Mixer** | Una nuova tab del notch con uno slider verticale per ogni app che emette suono (0–150%), nativo e senza driver. Vedi sotto. |
| **Spotify ovunque** | Mostra cosa ascolti su telefono, casse o TV, anche con l'app Spotify chiusa sul Mac. Funziona con **Spotify Free**, tramite Last.fm. |
| **Stato di attesa discreto** | Quando non suona nulla su nessun dispositivo, una scheda Spotify sobria sostituisce il brano segnaposto. |
| **Widget nella home** | Componi la home come i widget di iPhone: Musica, Calendario, Batteria Bluetooth, Meteo e Specchio. Fino a 1 grande + 2 piccoli; il notch si adatta. |
| **Batteria Bluetooth** | AirPods e Beats mostrano sinistra, destra e custodia; altre cuffie e casse una sola percentuale. |
| **Meteo** | Scheda in stile Apple con il cielo e il movimento della condizione attuale. Può prendere il posto della batteria quando non c'è nulla collegato. |
| **MacRemote** | Una nuova tab del notch che avvia **[MacRemote](https://github.com/jimmyxan/MacRemote)** e mostra il QR per associare l'iPhone. Inclusa nell'app. |

### Widget nella home

La home del notch aperto è un insieme di widget che scegli e disponi in **Impostazioni › Widgets**:

- **Trascina e rilascia su un'anteprima dal vivo**: trascina un widget dal vassoio nel notch, rilascialo su un altro per scambiarli (o per sostituirlo se manca spazio), riportalo nel vassoio per toglierlo. Una lista sotto fa lo stesso da tastiera.
- **Spazio a disposizione**: Musica è grande, gli altri sono piccoli, e la home contiene fino a **1 grande + 2 piccoli**. Il notch si allarga e si restringe in base a cosa contiene.
- **Batteria Bluetooth**: un anello animato con la carica del dispositivo collegato. Con AirPods o Beats un clic apre il dettaglio con **Sinistra**, **Destra** e **Custodia** (la custodia compare solo se è vicina e comunica la carica).
- **Meteo**: dati da [Open-Meteo](https://open-meteo.com) (gratuito, senza chiave). Pioggia, neve, temporali, nuvole e nebbia sono animati, con discrezione. La posizione arriva da Localizzazione o, se non la concedi, dall'indirizzo IP; dalle Impostazioni puoi concederla di nuovo o aggiornare. Senza connessione internet il widget mostra la mascotte di Claude Code che piange sotto una nuvola di pioggia (immagine sopra).
- **Meteo quando non c'è nulla collegato** (attivo di default): finché nessun dispositivo Bluetooth è collegato, al posto della batteria compare il meteo, che torna batteria appena un dispositivo si collega.

### MacRemote

La tab **MacRemote**, accanto al Mixer, integra **[MacRemote](https://github.com/jimmyxan/MacRemote)** ([macremote.it](https://www.macremote.it)), la mia app per comandare il Mac dall'iPhone sulla rete locale: volume, media, luminosità, tastiera, touchpad e altro, da una pagina web in Safari. Niente da installare sul telefono.

- **Inclusa in ogni installazione**: MacRemote viene compilata dal suo repository (un submodule git) e inserita dentro `TheBoringNotch.app`. Non c'è altro da scaricare.
- **Avvia → inquadra → fatto**: premi **Start MacRemote**, inquadra il QR con la fotocamera dell'iPhone (stessa Wi-Fi) e si apre il telecomando.
- **Copy link**, **New code** (i telefoni associati con il vecchio link smettono di funzionare) e **Stop** (MacRemote si chiude del tutto).
- Se usi già MacRemote installata a parte, la tab usa quella invece di avviarne una seconda copia.
- MacRemote gira come app a sé perché le servono permessi che il notch in sandbox non può avere (simulare tasti e puntatore, anteprima dello schermo). La prima volta macOS chiede il permesso **Accessibilità** per MacRemote.

Se MacRemote ti è utile, una ⭐ sul [suo repository](https://github.com/jimmyxan/MacRemote) aiuta.

### Mixer: motore nativo di OpenSoundSource

La tab Mixer usa il motore audio di **[OpenSoundSource](https://github.com/jimmyxan/OpenSoundSource)**, la mia app per il volume per singola app dalla barra dei menu. È integrato in modo nativo, non come plugin o processo separato:

- **Process tap di CoreAudio** (macOS 14.2+), nessun driver audio virtuale da installare.
- **I processi helper sono raggruppati sotto la loro app**: Safari (processo GPU di WebKit), Chrome, Teams e le app Electron compaiono come un solo slider, problema già risolto in OpenSoundSource.
- **0–150%** con aggancio magnetico al 100% e limitatore morbido, così l'audio amplificato non distorce.
- **Costo zero al 100%**: il tap viene rimosso quando un'app torna al volume pieno.
- **Segue i tuoi dispositivi**: i volumi restano quando cambia l'uscita predefinita, per esempio quando indossi le AirPods.
- **Controllo fine in poco spazio**: trascinamento relativo (il pallino non salta), tieni premuto **⌥ Option** per passi 4 volte più fini, clic sulla percentuale per tornare al 100%, clic sull'icona per silenziare.

La prima volta che muovi uno slider, macOS chiede il permesso di catturare l'audio delle app.

### Prestazioni

- Il vetro è composto da WindowServer: nessuna cattura dello schermo e nessun lavoro della CPU a ogni frame. Esiste solo a notch aperto e con lo slider sopra lo 0%.
- Il Mixer si aggiorna una volta al secondo solo con la sua tab visibile, ogni 3 s se c'è un volume personalizzato attivo, altrimenti mai.
- Con Spotify chiuso, Last.fm viene controllato ogni 15 s durante l'ascolto e ogni 60 s quando non suona nulla. Spotify non viene mai avviato in background.

### Spotify su altri dispositivi con Last.fm (tutorial)

La Web API di Spotify ora richiede Premium. Last.fm no: Spotify invia a Last.fm i tuoi ascolti da ogni dispositivo, anche con account Free.

1. **Crea un account Last.fm** su [last.fm/join](https://www.last.fm/join) (salta se ne hai già uno).
2. **Collega Spotify**: apri [last.fm/settings/applications](https://www.last.fm/settings/applications) e premi **Connect** accanto a *Spotify Scrobbling*.
3. **Ottieni una chiave API gratuita**: vai su [last.fm/api/account/create](https://www.last.fm/api/account/create). Inserisci un nome qualsiasi (per esempio *TheBoringNotch*) e una breve descrizione. Lascia vuoto *Callback URL*. Invia e copia la **API key**. Lo *Shared secret* non serve: non incollarlo da nessuna parte.
4. **Configura il notch**: apri le impostazioni del notch › **Media**, imposta **Music Source** su **Spotify**, poi compila **Last.fm username** e **Last.fm API key** in *Spotify on other devices*.
5. **Prova**: chiudi Spotify sul Mac e fai partire un brano dal telefono. Entro circa 15 secondi il notch mostra il brano. Il tuo profilo Last.fm dovrebbe indicare *Scrobbling now*.

Da sapere:
- Solo lettura: brano, artista, album e copertina. L'avanzamento è stimato. I controlli funzionano solo con l'app Spotify aperta sul Mac (senza bisogno di Premium).
- Quando metti in pausa, Last.fm mostra il brano come *now playing* ancora per qualche minuto.
- La chiave API resta solo nelle preferenze locali dell'app, mai in questo repository.

### Requisiti

- macOS 14 o successivo. Il Liquid Glass richiede macOS 26; sui sistemi precedenti il notch usa la sfocatura classica.
- Mixer: macOS 14.2 o successivo.
- Xcode 26 per compilare.

### Compilazione dal codice

```bash
git clone --recursive https://github.com/jimmyxan/DullNotch-Notch-Enhanced.git
cd DullNotch-Notch-Enhanced
open boringNotch.xcodeproj
```

Hai già clonato senza `--recursive`? Esegui `git submodule update --init`. La build compila il submodule MacRemote con Swift Package Manager e lo include nell'app.

Seleziona lo schema `boringNotch` e premi **Run**. Per sostituire le HUD di sistema serve il permesso Accessibilità.

> I controlli automatici degli aggiornamenti sono disattivati: il feed Sparkle incluso appartiene al Boring Notch originale e sostituirebbe questa build.

### Crediti

- **[Boring Notch](https://github.com/TheBoredTeam/boring.notch)** di TheBoredTeam e collaboratori: l'app originale su cui si basa questo remake.
- **[OpenSoundSource](https://github.com/jimmyxan/OpenSoundSource)**: il motore di volume per singola app dietro il Mixer.
- **[MacRemote](https://github.com/jimmyxan/MacRemote)** ([macremote.it](https://www.macremote.it)): il telecomando per iPhone dietro la tab MacRemote, incluso come submodule.
- Dati meteo di **[Open-Meteo](https://open-meteo.com)** (CC BY 4.0); posizione da IP di riserva tramite [ipwho.is](https://ipwho.is).
- Licenza **GPL-3.0**, come l'originale. Vedi [LICENSE](LICENSE) e [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
