"""Command-line interface for sbusta_p7m.core.

Extracts the PDF and signer metadata from one .p7m file, or from every
.p7m file found in a folder (optionally recursive). Never raises an
unhandled exception out to the user for a malformed input file: errors
are reported per-file and the batch continues.
"""

import argparse
import json
import os
import sys

from . import preferenze
from .core import estrai, P7mFormatError, P7mContentError


def _stem_senza_p7m(nome_file):
    """Strip every trailing .p7m extension (case-insensitive), without
    touching any other extension already present (e.g. "nome.pdf.p7m"
    -> "nome.pdf"). A file signed more than once has one .p7m per
    envelope layer (e.g. "nome.pdf.p7m.p7m.p7m" for a triple-signed
    document) — all of them are stripped, not just the last one."""
    while nome_file.lower().endswith(".p7m"):
        nome_file = nome_file[:-4]
    return nome_file


def _nomi_output(percorso_p7m):
    """Compute the (folder_name, pdf_filename, json_filename) triple for
    a given .p7m input path, handling both "nome.p7m" and "nome.pdf.p7m"
    naming. folder_name has every extension stripped (.p7m, and .pdf if
    present): each processed file gets its own subfolder, named after
    it, holding its .pdf + .json pair."""
    base = os.path.basename(percorso_p7m)
    senza_p7m = _stem_senza_p7m(base)
    if senza_p7m.lower().endswith(".pdf"):
        pdf_filename = senza_p7m
        stem = senza_p7m[:-4]
    else:
        pdf_filename = senza_p7m + ".pdf"
        stem = senza_p7m
    return stem, pdf_filename, stem + ".json"


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

    folder_name, pdf_filename, json_filename = _nomi_output(percorso_p7m)
    cartella_file = os.path.join(cartella_destinazione, folder_name)
    pdf_path = os.path.join(cartella_file, pdf_filename)
    json_path = os.path.join(cartella_file, json_filename)

    if os.path.exists(pdf_path) or os.path.exists(json_path):
        print(
            f"errore: {nome}: file di destinazione già esistente "
            f"({folder_name}/{pdf_filename} o {folder_name}/{json_filename}), "
            "non sovrascritto",
            file=sys.stderr,
        )
        return False

    metadata["pdf_estratto"] = pdf_filename
    cartella_radice = cartella_destinazione

    try:
        os.makedirs(cartella_file, exist_ok=True)
        with open(pdf_path, "wb") as f:
            f.write(pdf_bytes)
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, ensure_ascii=False, indent=2)
            f.write("\n")
    except PermissionError as e:
        cartella_fallback = preferenze.cartella_fallback()
        cartella_file = os.path.join(cartella_fallback, folder_name)
        pdf_path = os.path.join(cartella_file, pdf_filename)
        json_path = os.path.join(cartella_file, json_filename)
        try:
            os.makedirs(cartella_file, exist_ok=True)
            with open(pdf_path, "wb") as f:
                f.write(pdf_bytes)
            with open(json_path, "w", encoding="utf-8") as f:
                json.dump(metadata, f, ensure_ascii=False, indent=2)
                f.write("\n")
        except OSError as e2:
            print(
                f"errore: {nome}: permessi negati sulla cartella di destinazione ({e}); "
                f"anche il fallback è fallito ({e2})",
                file=sys.stderr,
            )
            return False
        cartella_radice = cartella_fallback
        print(f"fallback: {cartella_fallback}")
    except OSError as e:
        print(f"errore: {nome}: impossibile scrivere il file di destinazione ({e})", file=sys.stderr)
        return False

    print(f"ok: {nome} -> {os.path.relpath(pdf_path, cartella_radice)}, "
          f"{os.path.relpath(json_path, cartella_radice)}")
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Estrae il PDF e i metadati del firmatario contenuti in una busta .p7m (CMS/PKCS#7)."
    )
    parser.add_argument(
        "percorso",
        help="percorso di un file .p7m, o di una cartella contenente file .p7m",
    )
    parser.add_argument(
        "-d", "--destinazione",
        help="cartella di destinazione per i file .pdf/.json estratti "
             "(predefinita: la stessa cartella del file sorgente)",
    )
    parser.add_argument(
        "-r", "--ricorsivo",
        action="store_true",
        help="se percorso è una cartella, cerca i file .p7m ricorsivamente",
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
