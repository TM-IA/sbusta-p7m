# sbusta-p7m

Extract the PDF embedded in a `.p7m` envelope (CMS/PKCS#7, the format
used by Italian digital signatures), together with the signer's
certificate metadata, saved as a `.json` file next to the PDF.

## Status

Core extraction logic + CLI only. This is a partial component, not the
full application described in `PROJECT.md`: no signature/chain/revocation
validation, no platform integrations yet (Yazi, Nemo, Quick Look,
Android). Interface and packaging may still change.

## Requirements

- Python 3.9+
- [pipx](https://pipx.pypa.io/) (recommended for a standalone `sbusta-p7m`
  command), or plain `pip`/`venv`

## Install

```sh
git clone <repo-url>
cd sbusta-p7m
pipx install .
```

This installs a standalone `sbusta-p7m` command, independent from any
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
sbusta-p7m <file.p7m>
sbusta-p7m <folder> [-r] [-d <destination>]
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
not enough — use the official python.org installer), Platypus itself
(with its command-line tool installed), and this project's
`project-docs/icon/AppIcon.icns` available (symlinked from Nextcloud).

The app is **not code-signed**. To install it:

1. Copy `sbusta-p7m.app` wherever you like (e.g. `/Applications`).
2. Since it isn't signed, macOS Gatekeeper blocks the first launch.
   Clear the quarantine flag once:
   ```sh
   xattr -rd com.apple.quarantine /path/to/sbusta-p7m.app
   ```
3. Double-click to run, or drag a `.p7m` file onto the app icon.

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
   Copies everything to `~/.local/share/sbusta-p7m/` and registers a
   `.desktop` menu entry (also associated with `.p7m` files, so it
   shows up in a file manager's "Open With").
4. To remove it later: `~/.local/share/sbusta-p7m/uninstall.sh`.

Dialogs use `zenity`; if it isn't already installed, install it via
your distro's package manager first (e.g. `apt install zenity`,
`dnf install zenity`).

To build the tarball locally instead of downloading a CI artifact, run
`build-linux/build.sh` on a matching-architecture Linux machine (no
cross-compiling). See `linux-launcher/` for the wrapper script source.

## Known limitations

- No cryptographic validation of the signature, certificate chain, or
  revocation status: structural extraction only.
- Only the first signer of each envelope layer is read (co-signed
  envelopes with several signers at the same layer are not handled).
