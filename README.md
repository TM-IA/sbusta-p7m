# p7m-reader

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
- [pipx](https://pipx.pypa.io/) (recommended for a standalone `p7m-reader`
  command), or plain `pip`/`venv`

## Install

```sh
git clone <repo-url>
cd p7m-reader
pipx install .
```

This installs a standalone `p7m-reader` command, independent from any
project virtual environment. To pick up local source changes, reinstall
with `pipx install . --force`.

Alternatively, without pipx:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python3 -m p7m_reader.cli <args>
```

## Usage

```sh
p7m-reader <file.p7m>
p7m-reader <folder> [-r] [-d <destination>]
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

For each `name.p7m` (or `name.pdf.p7m`), two files are written:

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
is `null`, never omitted.

## Known limitations

- No cryptographic validation of the signature, certificate chain, or
  revocation status: structural extraction only.
- Only the first signer of each envelope layer is read (co-signed
  envelopes with several signers at the same layer are not handled).
- Nested-envelope unwrapping has only been verified against a
  synthetically built double envelope (self-signed test certificate),
  not against a real double-signed Italian `.p7m.p7m` file.
