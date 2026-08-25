#!/bin/sh
# TYPE:        script
# SCOPE:       sbusta-p7m
# VERSION:     0.1.7
# DESCRIPTION: Platypus wrapper: native dialogs around the bundled sbusta-p7m-cli
# NAME:        wrapper.sh

# changelog:
# 0.1.7 - destination-folder step redesigned: "Annulla" was overloaded
#         to mean "proceed using the source folder", which is the
#         opposite of what Cancel means everywhere else — replaced
#         the native "choose folder" panel (Cancel-only) with an
#         explicit three-way "display dialog" (Annulla / Cartella
#         sorgente / Scegli...), where Annulla now genuinely aborts
#         without extracting anything. "Aiuto" in the dialog now opens
#         the raw HTML directly again (guaranteed to show the right
#         content) instead of the "help:" URL scheme, whose bookID
#         lookup isn't reliably reaching our book (opened Help
#         Viewer's generic landing page instead) — the Help menu
#         (cmd+?) still tries "help:" without the empty anchor='',
#         which may have been causing the fallback to a generic page
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

# HELP_HTML kept absolute-from-Resources (script's own working
# directory, documented Platypus behavior) so both this dialog button
# and, in principle, other tools can reference the exact same file —
# single source of truth with the registered Help Book's own page.
HELP_HTML="./sbusta-p7m Help.help/Contents/Resources/it.lproj/index.html"

# Interactive mode (double-click, no dropped files): ask what to process.
# "Aiuto" opens the HTML page directly (guaranteed correct content);
# then re-asks, it doesn't just exit.
while :; do
    tipo=$(osascript <<'EOF' 2>/dev/null
display dialog "Estrarre un file .p7m singolo o tutti i file in una cartella?" buttons {"File", "Cartella", "Aiuto"} default button "File" with title "sbusta-p7m"
button returned of result
EOF
    ) || exit 0

    if [ "$tipo" = "Aiuto" ]; then
        open "$HELP_HTML"
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

# Explicit three-way choice instead of overloading a native folder
# picker's Cancel button: "Annulla" here genuinely aborts (matches
# what Cancel means everywhere else), it does NOT mean "proceed with
# the source folder" as an earlier version of this script did.
destinazione=""
while :; do
    scelta=$(osascript <<'EOF' 2>/dev/null
display dialog "Cartella di destinazione?" buttons {"Annulla", "Cartella sorgente", "Scegli..."} default button "Cartella sorgente" with title "sbusta-p7m"
button returned of result
EOF
    ) || exit 0

    case "$scelta" in
        Annulla) exit 0 ;;
        "Cartella sorgente") break ;;
        "Scegli...")
            destinazione=$(osascript -e 'POSIX path of (choose folder with prompt "Cartella di destinazione:")' 2>/dev/null)
            # If this inner picker is itself cancelled, $destinazione
            # stays empty and we loop back to the three-way choice
            # above, instead of guessing what the user meant.
            [ -n "$destinazione" ] && break
            ;;
    esac
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
