#!/bin/sh
# TYPE:        script
# SCOPE:       sbusta-p7m
# VERSION:     0.1.6
# DESCRIPTION: Platypus wrapper: native dialogs around the bundled sbusta-p7m-cli
# NAME:        wrapper.sh

# changelog:
# 0.1.6 - "Aiuto" now opens via the "help:" URL scheme (Help Viewer,
#         using the registered book) instead of "open" on the raw
#         .html file (default browser). Destination-folder dialog no
#         longer relies on an in-script AppleScript try/on error: on
#         Cancel it produced an error and skipped extraction instead
#         of falling back to the source folder as intended
# 0.1.5 - added an "Aiuto" button to the initial dialog, opening the
#         same HTML page registered as the app's Help Book (single
#         source of truth, accessible both from the dialog and from
#         the Help menu / cmd+?)
# 0.1.4 - log now appends a timestamped block per run instead of being
#         overwritten each time, so the history of past extractions
#         stays readable (previously only the latest run was kept)
# 0.1.3 - project renamed from p7m-reader to sbusta-p7m (the tool
#         unpacks/extracts, it doesn't "read" .p7m files): bundled
#         executable, log filename and dialog titles renamed accordingly
# 0.1.2 - fixed script exit code: both branches always exited 0 (or
#         inherited an unrelated command's exit status) regardless of
#         whether extraction actually failed
# 0.1.1 - "display dialog" cannot be resized/scrolled, so it cannot
#         hold the full output of a batch run readably: now shows only
#         a short summary and writes the full CLI output to a log file
#         in the destination folder, mentioned in the dialog
# 0.1.0 - initial implementation

set -u

# Platypus runs this script with the Resources/ folder of the .app
# bundle as the working directory (documented Platypus behavior): the
# bundled PyInstaller executable sits right here, referenced with a
# relative path — no PATH resolution, no external installation needed
# on the recipient's system.
CLI="./sbusta-p7m-cli"

scrivi_log_e_mostra() {
    # $1: exit code, $2: full CLI output (stdout+stderr), $3: folder to
    # write the log into. A "display dialog" box cannot be resized or
    # scrolled, so the full (possibly long) CLI output is never put
    # there directly — only a short summary, with the full text saved
    # to a log file the user can open if needed.
    esito_totale="$1"
    testo_completo="$2"
    cartella_log="$3"

    log_path="$cartella_log/sbusta-p7m-log.txt"
    {
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
        printf '%s\n' "$testo_completo"
        echo
    } >> "$log_path" 2>/dev/null

    # Reuse the CLI's own "riepilogo: N ok, M falliti" line verbatim
    # when present (batch mode) instead of recomputing counts here —
    # single source of truth. Single-file runs don't print that line,
    # so fall back to a plain sentence based on the exit code.
    riepilogo=$(printf '%s\n' "$testo_completo" | grep '^riepilogo:' | tail -1)
    if [ -z "$riepilogo" ]; then
        if [ "$esito_totale" -eq 0 ]; then
            riepilogo="Estrazione completata con successo."
        else
            riepilogo="Estrazione fallita."
        fi
    fi

    export P7M_OUTPUT="$riepilogo
Dettagli: $log_path"

    if [ "$esito_totale" -eq 0 ]; then
        osascript <<'EOF'
set msg to system attribute "P7M_OUTPUT"
display dialog msg with title "sbusta-p7m" buttons {"OK"} default button 1
EOF
    else
        osascript <<'EOF'
set msg to system attribute "P7M_OUTPUT"
display dialog msg with title "sbusta-p7m — completato con errori" buttons {"OK"} default button 1 with icon caution
EOF
    fi
}

if [ "$#" -gt 0 ]; then
    # Droplet mode: one or more files/folders dropped onto the app icon.
    # -r is harmless on a single file (the CLI only applies it to
    # folders), and is the more useful default for a dropped folder.
    # Log written next to the first dropped item: with multiple drops
    # there is no single shared destination folder to prefer instead.
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

# Interactive mode (double-click, no dropped files): ask what to process.
# "Aiuto" opens the same Help Book registered in Info.plist (Help menu,
# cmd+?) via the "help:" URL scheme, so it opens in Help Viewer — not
# the default browser, which is what plain "open" on the .html file
# would do — then re-asks, it doesn't just exit.
while :; do
    tipo=$(osascript <<'EOF' 2>/dev/null
display dialog "Estrarre un file .p7m singolo o tutti i file in una cartella?" buttons {"File", "Cartella", "Aiuto"} default button "File" with title "sbusta-p7m"
button returned of result
EOF
    ) || exit 0

    if [ "$tipo" = "Aiuto" ]; then
        open "help:anchor='' bookID='com.tm-ia.sbusta-p7m.help'"
        continue
    fi
    break
done

if [ "$tipo" = "File" ]; then
    percorso=$(osascript -e 'POSIX path of (choose file with prompt "Seleziona un file .p7m:")' 2>/dev/null) || exit 0
    ricorsivo=""
else
    percorso=$(osascript -e 'POSIX path of (choose folder with prompt "Seleziona una cartella:")' 2>/dev/null) || exit 0
    ricorsivo="-r"
fi

# No try/on error here: if "choose folder" is cancelled, osascript
# itself exits non-zero and prints nothing useful to stdout (the error
# goes to stderr, discarded below) — $destinazione ends up empty either
# way, without depending on AppleScript's own error-handling semantics
# inside the heredoc (a "try ... return \"\"" here didn't reliably fall
# through to the plain-CLI-call branch, cause unclear).
destinazione=$(osascript -e 'POSIX path of (choose folder with prompt "Cartella di destinazione (Annulla per usare quella del file sorgente):")' 2>/dev/null)

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
