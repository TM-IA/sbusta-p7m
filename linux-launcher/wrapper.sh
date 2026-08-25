#!/bin/sh
# zenity wrapper: native dialogs around the bundled sbusta-p7m-cli
# (Linux). Ported from the macOS Platypus wrapper — same logic,
# adapted to zenity's button model (see notes below). Built and
# exercised for the first time via GitHub Actions CI; no local Linux
# desktop available to test it by hand.

set -u

# Resolve paths relative to this script's own location, not the
# working directory the launcher happens to be started from (a
# .desktop Exec= line, or a file manager "Open With", does not
# necessarily set cwd to the install folder the way Platypus does on
# macOS by running the script from Resources/).
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CLI="$SCRIPT_DIR/sbusta-p7m-cli"
HELP_HTML="$SCRIPT_DIR/help/index.html"

scrivi_log_e_mostra() {
    # $1: exit code, $2: full CLI output (stdout+stderr), $3: folder to
    # write the log into. Same reasoning as the macOS wrapper: no GUI
    # dialog here can show a long scrollable batch output readably,
    # so only a short summary is shown, full text goes to a log file.
    esito_totale="$1"
    testo_completo="$2"
    cartella_log="$3"

    log_path="$cartella_log/sbusta-p7m-log.txt"
    {
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
        printf '%s\n' "$testo_completo"
        echo
    } >> "$log_path" 2>/dev/null

    riepilogo=$(printf '%s\n' "$testo_completo" | grep '^riepilogo:' | tail -1)
    if [ -z "$riepilogo" ]; then
        if [ "$esito_totale" -eq 0 ]; then
            riepilogo="Estrazione completata con successo."
        else
            riepilogo="Estrazione fallita."
        fi
    fi

    if [ "$esito_totale" -eq 0 ]; then
        zenity --info --title="sbusta-p7m" \
            --text="$riepilogo
Dettagli: $log_path" 2>/dev/null
    else
        zenity --error --title="sbusta-p7m — completato con errori" \
            --text="$riepilogo
Dettagli: $log_path" 2>/dev/null
    fi
}

if [ "$#" -gt 0 ]; then
    # Droplet-equivalent: one or more files/folders passed as
    # arguments (file manager "Open With", or a .desktop MIME
    # association). -r is harmless on a single file.
    output=""
    esito_totale=0
    for percorso in "$@"; do
        out=$("$CLI" "$percorso" -r 2>&1)
        esito=$?
        output="$output=== $percorso ===
$out

"
        if [ "$esito" -ne 0 ]; then
            esito_totale=1
        fi
    done
    if [ -d "$1" ]; then
        cartella_log="$1"
    else
        cartella_log=$(dirname "$1")
    fi
    scrivi_log_e_mostra "$esito_totale" "$output" "$cartella_log"
    exit "$esito_totale"
fi

# Interactive mode: ask what to process.
#
# zenity --question only gives a binary OK/Cancel outcome via exit
# code (0 = OK, 1 = Cancel); --extra-button adds a third option that
# ALSO exits 1, but prints its own label to stdout — so a third choice
# is distinguished from a plain Cancel by checking stdout, not just
# the exit code. This differs from macOS's "display dialog", which
# returns each button's name directly; ported carefully, not assumed
# to behave the same.
while :; do
    risposta=$(zenity --question --title="sbusta-p7m" \
        --text="Estrarre un file .p7m singolo o tutti i file in una cartella?" \
        --ok-label="File" --cancel-label="Cartella" --extra-button="Aiuto" 2>/dev/null)
    ret=$?
    if [ "$ret" -eq 0 ]; then
        tipo="File"
    elif [ "$risposta" = "Aiuto" ]; then
        xdg-open "$HELP_HTML" >/dev/null 2>&1 &
        continue
    else
        tipo="Cartella"
    fi
    break
done

if [ "$tipo" = "File" ]; then
    percorso=$(zenity --file-selection --title="Seleziona un file .p7m" \
        --file-filter="*.p7m" 2>/dev/null) || exit 0
    ricorsivo=""
else
    percorso=$(zenity --file-selection --directory \
        --title="Seleziona una cartella" 2>/dev/null) || exit 0
    ricorsivo="-r"
fi

# Same three-way choice as macOS (0.1.7): "Annulla" genuinely aborts,
# it does not mean "proceed with the source folder" — that was a real
# bug there, not repeated here from the start.
destinazione=""
while :; do
    scelta=$(zenity --question --title="sbusta-p7m" \
        --text="Cartella di destinazione?" \
        --ok-label="Cartella sorgente" --cancel-label="Annulla" \
        --extra-button="Scegli..." 2>/dev/null)
    ret=$?
    if [ "$ret" -eq 0 ]; then
        break
    elif [ "$scelta" = "Scegli..." ]; then
        destinazione=$(zenity --file-selection --directory \
            --title="Cartella di destinazione" 2>/dev/null)
        [ -n "$destinazione" ] && break
    else
        exit 0
    fi
done

if [ -n "$destinazione" ]; then
    # $ricorsivo intentionally unquoted: it is always either empty or
    # the single token "-r", never a value needing word-preservation.
    output=$("$CLI" "$percorso" $ricorsivo -d "$destinazione" 2>&1)
    esito=$?
    cartella_log="$destinazione"
else
    output=$("$CLI" "$percorso" $ricorsivo 2>&1)
    esito=$?
    if [ -d "$percorso" ]; then
        cartella_log="$percorso"
    else
        cartella_log=$(dirname "$percorso")
    fi
fi

scrivi_log_e_mostra "$esito" "$output" "$cartella_log"
exit "$esito"
