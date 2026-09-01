"""Shared per-platform paths and small persisted preferences for
sbusta_p7m. Used both as a write fallback (cli.py, when the resolved
destination folder isn't writable) and as the storage for user
preferences (default destination, logging on/off).
"""

import json
import os
import sys

_CHIAVI_VALIDE = {"destinazione", "log", "modalita"}
_FILE_PREFERENZE = "preferenze.json"


def cartella_config():
    """Per-platform config folder for sbusta-p7m (not created here —
    callers create it on first write)."""
    if sys.platform == "darwin":
        return os.path.join(os.path.expanduser("~"), "Library", "Application Support", "sbusta-p7m")
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "sbusta-p7m")


def cartella_dati():
    """Per-platform data folder for sbusta-p7m."""
    if sys.platform == "darwin":
        # macOS convention: one Application Support folder for both
        # config and data, unlike Linux's XDG split.
        return cartella_config()
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(base, "sbusta-p7m")


def cartella_fallback():
    """Safety-net folder used when the chosen destination can't be
    written to (e.g. a sandboxed Mail.app attachment path)."""
    return os.path.join(cartella_dati(), "estrazioni-fallback")


def _percorso_preferenze():
    return os.path.join(cartella_config(), _FILE_PREFERENZE)


def leggi(chiave):
    """Return the stored value for chiave, or None if unset, the file
    is missing, or it's corrupted — never raises for the caller."""
    if chiave not in _CHIAVI_VALIDE:
        raise ValueError(f"chiave preferenza sconosciuta: '{chiave}'")
    try:
        with open(_percorso_preferenze(), "r", encoding="utf-8") as f:
            dati = json.load(f)
    except (OSError, ValueError):
        return None
    valore = dati.get(chiave)
    return valore if valore else None


def scrivi(chiave, valore):
    """Persist chiave=valore (valore == "" removes the key instead of
    storing an empty string, letting a preference be cleared)."""
    if chiave not in _CHIAVI_VALIDE:
        raise ValueError(f"chiave preferenza sconosciuta: '{chiave}'")
    percorso = _percorso_preferenze()
    try:
        with open(percorso, "r", encoding="utf-8") as f:
            dati = json.load(f)
    except (OSError, ValueError):
        dati = {}
    if valore:
        dati[chiave] = valore
    else:
        dati.pop(chiave, None)
    os.makedirs(cartella_config(), exist_ok=True)
    with open(percorso, "w", encoding="utf-8") as f:
        json.dump(dati, f, ensure_ascii=False, indent=2)
        f.write("\n")
