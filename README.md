# sbusta-p7m

Documentazione in inglese più sotto in questo stesso file.

Estrae il PDF contenuto in una busta `.p7m` (CMS/PKCS#7, il formato
usato dalla firma digitale italiana), insieme ai metadati del
certificato del firmatario, salvati in un file `.json` a lato.

## Stato

La logica di estrazione principale e la CLI sono complete e testate.
Esiste un launcher/app nativo per ciascuna piattaforma di destinazione
— macOS, Linux, Android — ciascuno a un diverso stadio di verifica nel
mondo reale (vedi le sezioni per piattaforma più sotto). Nessuna
validazione crittografica della firma, della catena di certificazione
o dello stato di revoca: solo estrazione strutturale, non previsto
cambiare.

Non ancora fatto: integrazioni più profonde con file manager/anteprime
(uno script di anteprima per Yazi, un thumbnailer per Nemo, un pannello
di anteprima Quick Look per macOS) — oggi, aprire un `.p7m` lancia
l'app/wrapper della piattaforma descritto più sotto, non mostra
un'anteprima inline senza lanciare nulla. L'interfaccia e il
pacchettizzamento potrebbero ancora cambiare.

## Requisiti

- Python 3.9+
- [pipx](https://pipx.pypa.io/) (consigliato per un comando
  `sbusta-py-p7m` autonomo), oppure semplice `pip`/`venv`

## Installazione

```sh
git clone <repo-url>
cd sbusta-p7m
pipx install .
```

Installa un comando `sbusta-py-p7m` autonomo, indipendente da
qualunque virtual environment di progetto. Per recepire modifiche
locali al sorgente, reinstalla con `pipx install . --force`.

In alternativa, senza pipx:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python3 -m sbusta_p7m.cli <args>
```

## Utilizzo

```sh
sbusta-py-p7m <file.p7m>
sbusta-py-p7m <cartella> [-r] [-d <destinazione>]
```

- `percorso` (posizionale): un singolo file `.p7m`, o una cartella. Se
  è una cartella, ogni file `.p7m` al suo interno viene elaborato
  (corrispondenza dell'estensione non case-sensitive).
- `-d`, `--destinazione <cartella>`: cartella di destinazione per i
  file `.pdf`/`.json` estratti. Di default, la stessa cartella del
  file sorgente. Creata automaticamente se non esiste.
- `-r`, `--ricorsivo`: se `percorso` è una cartella, cerca i file
  `.p7m` ricorsivamente nelle sottocartelle.

Un file malformato dentro un batch viene segnalato e saltato, non
interrompe il resto del batch. I file di output esistenti non vengono
mai sovrascritti. Il codice di uscita è `0` se tutti i file sono
riusciti, `1` altrimenti.

## Output

Per ogni `nome.p7m` (o `nome.pdf.p7m`), viene creata una sottocartella
`nome/` dentro la destinazione, contenente:

- `nome.pdf` — il PDF estratto, non modificato
- `nome.json` — metadati del firmatario, es.:

```json
{
  "file_originale": "name.pdf.p7m",
  "pdf_estratto": "name.pdf",
  "firmatari": [
    {
      "cn": "...",
      "organizzazione": "...",
      "numero_seriale": "...",
      "validita_inizio": "...",
      "validita_fine": "...",
      "algoritmo_firma": "...",
      "signing_time": "..."
    }
  ]
}
```

`firmatari` contiene una voce per ogni livello di firma attraversato.
La maggior parte dei file `.p7m` ha un solo livello (array di
lunghezza 1); i file firmati più di una volta (`nome.pdf.p7m.p7m`,
buste CMS annidate) producono una voce per livello, firma più esterna
per prima. Ogni campo che non è stato possibile risolvere è `null`,
mai omesso. Verificato su documenti italiani reali firmati fino a tre
volte.

## App macOS

Un `.app` autonomo, avviabile con doppio clic (nessun Python richiesto
sul sistema di chi lo riceve):

1. Scarica `sbusta-p7m.app.zip` dall'[ultima release](../../releases/latest)
   ed estrailo.
2. Non essendo firmata digitalmente, macOS Gatekeeper blocca il primo
   avvio. Rimuovi il flag di quarantena una volta sola:
   ```sh
   xattr -d com.apple.quarantine /path/to/sbusta-p7m.app
   ```
3. Doppio clic per avviarla, o trascina un file `.p7m` sull'icona
   dell'app.

Buildata interamente in CI (workflow `build-macos.yml`: universal2
arm64+x86_64 con PyInstaller, incapsulato con
[Platypus](https://sveinbjorn.org/platypus)) e allegata automaticamente
a ogni release. Per buildarla in locale — es. per modificarla —
serve un Python universal2 sulla macchina di build (quello di Homebrew
è specifico per architettura, non basta — usare l'
[installer ufficiale di python.org](https://www.python.org/downloads/macos/))
e Platypus stesso (con il suo tool a riga di comando installato):

```sh
build-macos/build.sh
```

Produce `build-macos/dist/sbusta-p7m.app`. L'icona
(`macos-launcher/AppIcon.icns`) fa parte di questo repository.

Il bundle dell'app incorpora un binario costruito da
[Platypus](https://sveinbjorn.org/platypus) (BSD 3-Clause) — vedi
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) per il testo della
licenza, riprodotto come richiesto da quella licenza.

Vedi `macos-launcher/` per lo script wrapper e le fonti del contenuto
di Aiuto.

## Linux

Un tarball autonomo (nessun Python richiesto sul sistema di chi lo
riceve), per `x86_64` e `aarch64`:

1. Scarica `sbusta-p7m-linux-x86_64.tar.gz` o
   `sbusta-p7m-linux-aarch64.tar.gz` (corrispondente all'architettura
   della tua macchina) dall'[ultima release](../../releases/latest).
2. Estrailo: `tar xzf sbusta-p7m-linux-<arch>.tar.gz`.
3. Installa per utente, senza bisogno di root:
   ```sh
   cd sbusta-p7m-linux-<arch>
   ./install.sh
   ```
   Copia il wrapper grafico, l'aiuto e l'icona in
   `~/.local/share/sbusta-p7m/`, l'eseguibile autonomo `sbusta-p7m` in
   `~/.local/bin/sbusta-p7m` (utilizzabile anche direttamente da
   terminale, stessa interfaccia CLI di `sbusta-py-p7m` sopra ma senza
   dipendenza da Python), e registra una voce di menu `.desktop`
   (associata anche ai file `.p7m`, così compare in "Apri con" del
   file manager).
4. Per rimuoverlo in seguito: `~/.local/share/sbusta-p7m/uninstall.sh`.

I dialoghi usano `zenity`; se non è già installato, installalo prima
tramite il gestore pacchetti della tua distribuzione (es.
`apt install zenity`, `dnf install zenity`).

Per buildare il tarball in locale invece di scaricare un artifact CI,
esegui `build-linux/build.sh` su una macchina Linux della stessa
architettura (nessuna cross-compilazione). Vedi `linux-launcher/` per
il sorgente dello script wrapper.

## Android

Un'app Kotlin nativa (non un porting che riusa il core Python —
Android non può eseguire uno script Python dentro un'estensione di
sistema, stesso vincolo di macOS) si registra per aprire direttamente
gli allegati `.p7m` dalle app di posta, e compare anche come app
normale con una propria icona nel launcher:

1. Scarica `sbusta-p7m.apk` dall'[ultima release](../../releases/latest).
2. Abilita "Installa da origini sconosciute" per il file (non è
   installata dal Play Store/F-Droid), poi installalo.
3. Tocca un allegato `.p7m` in un'app di posta per aprirlo
   direttamente, oppure lancia l'app dal cassetto applicazioni e
   scegli un file tramite "Apri file .p7m…".

All'apertura, mostra un riepilogo del/i firmatario/i — una voce per
livello di firma, per i documenti firmati più volte — con pulsanti per
aprire il PDF estratto, salvarlo in una cartella scelta, ed
eventualmente esportare i metadati come JSON, entrambi tramite il file
picker di sistema. Un pulsante "Aiuto" in-app mostra brevi istruzioni
d'uso.

Usa [BouncyCastle](https://www.bouncycastle.org/) (`bcpkix-jdk18on`)
per il parsing CMS, stessa logica del core Python, portata campo per
campo. La CI builda l'APK, lo firma con una chiave di firma dedicata
(così un aggiornamento installa correttamente sopra una versione
precedente, invece di scontrarsi con una firma di debug diversa a ogni
build) ed esegue test unitari contro una busta firmata sinteticamente
(`android-app/`); testato anche aprendo un `.p7m` reale da un'app di
posta reale su un dispositivo fisico. Nessuna distribuzione Play
Store/F-Droid in questa fase.

## Limiti noti

- Nessuna validazione crittografica della firma, della catena di
  certificazione o dello stato di revoca: solo estrazione strutturale.
- Viene letto solo il primo firmatario di ogni livello di busta (buste
  co-firmate con più firmatari allo stesso livello non sono gestite).

---

Extract the PDF embedded in a `.p7m` envelope (CMS/PKCS#7, the format
used by Italian digital signatures), together with the signer's
certificate metadata, saved as a `.json` file next to the PDF.

## Status

Core extraction logic and a CLI are complete and tested. A native
launcher/app exists for each target platform — macOS, Linux, Android —
each at a different stage of real-world verification (see the platform
sections below). No cryptographic validation of the signature,
certificate chain, or revocation status: structural extraction only,
not planned to change.

Not yet done: deeper file-manager/previewer integrations (a Yazi
preview script, a Nemo thumbnailer, a macOS Quick Look preview pane) —
today, opening a `.p7m` launches the platform app/wrapper described
below, it doesn't show an inline preview without launching anything.
Interface and packaging may still change.

## Requirements

- Python 3.9+
- [pipx](https://pipx.pypa.io/) (recommended for a standalone `sbusta-py-p7m`
  command), or plain `pip`/`venv`

## Install

```sh
git clone <repo-url>
cd sbusta-p7m
pipx install .
```

This installs a standalone `sbusta-py-p7m` command, independent from any
project virtual environment. To pick up local source changes, reinstall
with `pipx install . --force`.

Alternatively, without pipx:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python3 -m sbusta_p7m.cli <args>
```

## Usage

```sh
sbusta-py-p7m <file.p7m>
sbusta-py-p7m <folder> [-r] [-d <destination>]
```

- `percorso` (positional): a single `.p7m` file, or a folder. If it's a
  folder, every `.p7m` file inside it is processed (case-insensitive
  extension match).
- `-d`, `--destinazione <folder>`: output folder for the extracted
  `.pdf`/`.json` files. Defaults to each source file's own folder. Created
  automatically if it doesn't exist.
- `-r`, `--ricorsivo`: when `percorso` is a folder, search `.p7m` files
  recursively in subfolders.

A malformed file inside a batch is reported and skipped, it does not
stop the rest of the batch. Existing output files are never overwritten.
Exit code is `0` if every file succeeded, `1` otherwise.

## Output

For each `name.p7m` (or `name.pdf.p7m`), a `name/` subfolder is created
inside the destination, containing:

- `name.pdf` — the extracted PDF, unmodified
- `name.json` — signer metadata, e.g.:

```json
{
  "file_originale": "name.pdf.p7m",
  "pdf_estratto": "name.pdf",
  "firmatari": [
    {
      "cn": "...",
      "organizzazione": "...",
      "numero_seriale": "...",
      "validita_inizio": "...",
      "validita_fine": "...",
      "algoritmo_firma": "...",
      "signing_time": "..."
    }
  ]
}
```

`firmatari` holds one entry per signature layer crossed. Most `.p7m`
files have a single layer (array of length 1); files signed more than
once (`name.pdf.p7m.p7m`, nested CMS envelopes) produce one entry per
layer, outermost signature first. Any field that could not be resolved
is `null`, never omitted. Verified against real Italian documents signed
up to three times.

## macOS app

A self-contained, double-clickable `.app` (no Python required on the
recipient's system):

1. Download `sbusta-p7m.app.zip` from the
   [latest release](../../releases/latest) and extract it.
2. Since it isn't code-signed, macOS Gatekeeper blocks the first
   launch. Clear the quarantine flag once:
   ```sh
   xattr -d com.apple.quarantine /path/to/sbusta-p7m.app
   ```
3. Double-click to run, or drag a `.p7m` file onto the app icon.

Built entirely in CI (the `build-macos.yml` workflow: universal2
arm64+x86_64 with PyInstaller, wrapped with
[Platypus](https://sveinbjorn.org/platypus)) and attached to every
release automatically. To build it locally instead — e.g. to modify
it — the build machine needs a universal2 Python (Homebrew's own
Python is arch-specific, not enough — use the official
[python.org installer](https://www.python.org/downloads/macos/)) and
Platypus itself (with its command-line tool installed):

```sh
build-macos/build.sh
```

Produces `build-macos/dist/sbusta-p7m.app`. The icon
(`macos-launcher/AppIcon.icns`) is part of this repository.

The app bundle embeds a binary built by
[Platypus](https://sveinbjorn.org/platypus) (BSD 3-Clause) — see
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) for the license
text, reproduced as that license requires.

See `macos-launcher/` for the wrapper script and Help content sources.

## Linux

A self-contained tarball (no Python required on the recipient's
system), for both `x86_64` and `aarch64`:

1. Download `sbusta-p7m-linux-x86_64.tar.gz` or
   `sbusta-p7m-linux-aarch64.tar.gz` (matching your machine's
   architecture) from the [latest release](../../releases/latest).
2. Extract it: `tar xzf sbusta-p7m-linux-<arch>.tar.gz`.
3. Install per-user, no root required:
   ```sh
   cd sbusta-p7m-linux-<arch>
   ./install.sh
   ```
   Copies the GUI wrapper, help, and icon to `~/.local/share/sbusta-p7m/`,
   the standalone `sbusta-p7m` executable to `~/.local/bin/sbusta-p7m`
   (also usable directly from a terminal, same CLI interface as
   `sbusta-py-p7m` above but with no Python dependency), and registers a
   `.desktop` menu entry (also associated with `.p7m` files, so it
   shows up in a file manager's "Open With").
4. To remove it later: `~/.local/share/sbusta-p7m/uninstall.sh`.

Dialogs use `zenity`; if it isn't already installed, install it via
your distro's package manager first (e.g. `apt install zenity`,
`dnf install zenity`).

To build the tarball locally instead of downloading a CI artifact, run
`build-linux/build.sh` on a matching-architecture Linux machine (no
cross-compiling). See `linux-launcher/` for the wrapper script source.

## Android

A native Kotlin app (not a port that reuses the Python core — Android
can't run a Python script inside a system extension, same constraint
as macOS) registers to open `.p7m` attachments directly from mail apps,
and also appears as a regular app with its own launcher icon:

1. Download `sbusta-p7m.apk` from the
   [latest release](../../releases/latest).
2. Enable "Install from unknown sources" for the file (it isn't
   installed from the Play Store/F-Droid), then install it.
3. Tap a `.p7m` attachment in a mail app to open it directly, or launch
   the app from the app drawer and pick a file via "Apri file .p7m…".

On opening, it shows a summary of the signer(s) — one entry per
signature layer, for documents signed more than once — with buttons to
open the extracted PDF, save it to a chosen folder, and optionally
export the metadata as JSON, both through the system's file picker. An
in-app "Aiuto" button shows brief usage instructions.

Uses [BouncyCastle](https://www.bouncycastle.org/) (`bcpkix-jdk18on`)
for CMS parsing, same logic as the Python core, ported field for
field. CI builds the APK, signs it with a dedicated signing key (so an
update installs correctly over a previous version, instead of
colliding with a different debug signature on every build), and runs
unit tests against a synthetically signed envelope (`android-app/`);
also tested opening a real `.p7m` from an actual mail app on a
physical device. No Play Store/F-Droid distribution in this phase.

## Known limitations

- No cryptographic validation of the signature, certificate chain, or
  revocation status: structural extraction only.
- Only the first signer of each envelope layer is read (co-signed
  envelopes with several signers at the same layer are not handled).
