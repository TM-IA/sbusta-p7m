# TYPE:        script
# SCOPE:       p7m-reader
# VERSION:     0.1.0
# DESCRIPTION: command-line interface for batch .p7m extraction
# NAME:        cli.py

# changelog:
# 0.1.0 - initial implementation

"""Command-line interface for p7m_reader.core.

Extracts the PDF and signer metadata from one .p7m file, or from every
.p7m file found in a folder (optionally recursive). Never raises an
unhandled exception out to the user for a malformed input file: errors
are reported per-file and the batch continues.
"""

import argparse
import json
import os
import sys

from .core import estrai, P7mFormatError, P7mContentError


def _stem_senza_p7m(nome_file):
    """Strip the trailing .p7m extension (case-insensitive), without
    touching any other extension already present (e.g. "nome.pdf.p7m"
    -> "nome.pdf", not "nome.pdf.p7m" with .pdf appended again)."""
    if nome_file.lower().endswith(".p7m"):
        return nome_file[:-4]
    return nome_file


def _nomi_output(percorso_p7m):
    """Compute the (pdf_filename, json_filename) pair for a given .p7m
    input path, handling both "nome.p7m" and "nome.pdf.p7m" naming."""
    base = os.path.basename(percorso_p7m)
    senza_p7m = _stem_senza_p7m(base)
    if senza_p7m.lower().endswith(".pdf"):
        pdf_filename = senza_p7m
        json_stem = senza_p7m[:-4]
    else:
        pdf_filename = senza_p7m + ".pdf"
        json_stem = senza_p7m
    return pdf_filename, json_stem + ".json"


def _trova_file_p7m(cartella, ricorsivo):
    """Yield every .p7m file path under cartella, extension match
    case-insensitive (Linux is case-sensitive, macOS by default is not:
    without normalizing, behavior would differ across platforms)."""
    if ricorsivo:
        for root, _dirs, files in os.walk(cartella):
            for name in files:
                if name.lower().endswith(".p7m"):
                    yield os.path.join(root, name)
    else:
        for name in sorted(os.listdir(cartella)):
            path = os.path.join(cartella, name)
            if os.path.isfile(path) and name.lower().endswith(".p7m"):
                yield path


def _elabora_file(percorso_p7m, cartella_destinazione):
    """Extract one .p7m file and write its .pdf/.json output.

    Returns True on success, False on failure (already reported to
    stderr by this function)."""
    nome = os.path.basename(percorso_p7m)

    try:
        pdf_bytes, metadata = estrai(percorso_p7m)
    except (P7mFormatError, P7mContentError) as e:
        print(f"errore: {nome}: {e}", file=sys.stderr)
        return False
    except OSError as e:
        print(f"errore: {nome}: impossibile leggere il file ({e})", file=sys.stderr)
        return False

    if not pdf_bytes.startswith(b"%PDF-"):
        print(
            f"avviso: {nome}: il contenuto estratto non sembra un PDF valido "
            "(manca l'header %PDF-), estratto comunque",
            file=sys.stderr,
        )

    pdf_filename, json_filename = _nomi_output(percorso_p7m)
    pdf_path = os.path.join(cartella_destinazione, pdf_filename)
    json_path = os.path.join(cartella_destinazione, json_filename)

    if os.path.exists(pdf_path) or os.path.exists(json_path):
        print(
            f"errore: {nome}: file di destinazione già esistente "
            f"({pdf_filename} o {json_filename}), non sovrascritto",
            file=sys.stderr,
        )
        return False

    os.makedirs(cartella_destinazione, exist_ok=True)

    metadata["pdf_estratto"] = pdf_filename

    with open(pdf_path, "wb") as f:
        f.write(pdf_bytes)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"ok: {nome} -> {pdf_filename}, {json_filename}")
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Extract the PDF and signer metadata embedded in .p7m (CMS/PKCS#7) envelopes."
    )
    parser.add_argument(
        "percorso",
        help="path to a .p7m file, or a folder containing .p7m files",
    )
    parser.add_argument(
        "-d", "--destinazione",
        help="output folder for the extracted .pdf/.json files "
             "(default: same folder as each source file)",
    )
    parser.add_argument(
        "-r", "--ricorsivo",
        action="store_true",
        help="when percorso is a folder, search .p7m files recursively",
    )
    args = parser.parse_args(argv)

    if not os.path.exists(args.percorso):
        print(f"errore: '{args.percorso}' non esiste", file=sys.stderr)
        return 1

    if os.path.isfile(args.percorso):
        file_list = [args.percorso]
    else:
        file_list = list(_trova_file_p7m(args.percorso, args.ricorsivo))
        if not file_list:
            print(f"nessun file .p7m trovato in '{args.percorso}'", file=sys.stderr)
            return 1

    ok_count = 0
    fail_count = 0
    for percorso_p7m in file_list:
        cartella_destinazione = args.destinazione or os.path.dirname(percorso_p7m) or "."
        if _elabora_file(percorso_p7m, cartella_destinazione):
            ok_count += 1
        else:
            fail_count += 1

    if len(file_list) > 1:
        print(f"\nriepilogo: {ok_count} ok, {fail_count} falliti")

    return 1 if fail_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
