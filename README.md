# sbusta-p7m

Documentazione in inglese più sotto in questo stesso file.

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
recipient's system) is built locally, not by CI:

```sh
build-macos/build.sh
```

Produces `build-macos/dist/sbusta-p7m.app`, a universal2 binary
(arm64 + x86_64) built with PyInstaller and wrapped with
[Platypus](https://sveinbjorn.org/platypus). Requires, on the build
machine: a universal2 Python (Homebrew's own Python is arch-specific,
not enough — use the official
[python.org installer](https://www.python.org/downloads/macos/)),
Platypus itself
(with its command-line tool installed), and an `AppIcon.icns` at
`project-docs/icon/AppIcon.icns` — that path isn't part of this
repository, provide your own icon there before building.

The app is **not code-signed**. To install it:

1. Copy `sbusta-p7m.app` wherever you like (e.g. `/Applications`).
2. Since it isn't signed, macOS Gatekeeper blocks the first launch.
   Clear the quarantine flag once:
   ```sh
   xattr -rd com.apple.quarantine /path/to/sbusta-p7m.app
   ```
3. Double-click to run, or drag a `.p7m` file onto the app icon.

There's no CI build for macOS (Platypus's build step needs a one-time
interactive `sudo` to install its command-line tool, not practical on
a hosted runner). A built `.app` is instead attached manually to a
[GitHub Release](../../releases) when one is cut.

The app bundle embeds a binary built by
[Platypus](https://sveinbjorn.org/platypus) (BSD 3-Clause) — see
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) for the license
text, reproduced as that license requires.

See `macos-launcher/` for the wrapper script and Help content sources.

## Linux

A self-contained tarball (no Python required on the recipient's
system) is built by CI for both `x86_64` and `aarch64`, one per push
to `main` that touches `linux-launcher/`, `build-linux/`, or the
workflow itself:

1. Download the `sbusta-p7m-linux-x86_64` or `sbusta-p7m-linux-aarch64`
   artifact from the latest successful run under
   [Actions](../../actions/workflows/build-linux.yml) (matching your
   machine's architecture).
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

1. Download the `sbusta-p7m-android-debug` artifact from the latest
   successful run under
   [Actions](../../actions/workflows/build-android.yml).
2. Extract the `.apk` from the downloaded zip.
3. Enable "Install from unknown sources" for the file (it isn't
   signed for a release/store distribution), then install it.
4. Tap a `.p7m` attachment in a mail app to open it directly, or launch
   the app from the app drawer and pick a file via "Apri file .p7m…".

On opening, it shows a summary of the signer(s) — one entry per
signature layer, for documents signed more than once — with buttons to
open the extracted PDF, save it to a chosen folder, and optionally
export the metadata as JSON, both through the system's file picker. An
in-app "Aiuto" button shows brief usage instructions.

Uses [BouncyCastle](https://www.bouncycastle.org/) (`bcpkix-jdk18on`)
for CMS parsing, same logic as the Python core, ported field for
field. CI builds the APK and runs unit tests against a synthetically
signed envelope (`android-app/`); opening a real `.p7m` from an actual
mail app on a physical device has not been tested yet. No release
signing, no Play Store/F-Droid distribution in this phase.

## Known limitations

- No cryptographic validation of the signature, certificate chain, or
  revocation status: structural extraction only.
- Only the first signer of each envelope layer is read (co-signed
  envelopes with several signers at the same layer are not handled).
