#!/bin/sh
# Platypus wrapper: native dialogs around the bundled sbusta-p7m.

set -u

# Platypus runs this script with the Resources/ folder of the .app
# bundle as the working directory (documented Platypus behavior): the
# bundled PyInstaller executable sits right here, referenced with a
# relative path — no PATH resolution, no external installation needed
# on the recipient's system.
CLI="./sbusta-p7m"

# Same path sbusta_p7m/preferenze.py's cartella_config() computes on
# macOS. Read directly here (see leggi_preferenza below) instead of
# always going through the CLI just to read a value back.
FILE_PREFERENZE="$HOME/Library/Application Support/sbusta-p7m/preferenze.json"

leggi_preferenza() {
    # $1: chiave ("destinazione" o "log"). Legge preferenze.json
    # direttamente in shell (grep/sed) invece di invocare il binario
    # PyInstaller solo per leggere una stringa: un binario --onefile
    # impiega circa 1-1.5s ad avviarsi (scompatta l'intero runtime
    # Python a ogni lancio), troppo lento da fare più volte per
    # aprire un dialogo. Formato JSON controllato da noi stessi
    # (sbusta_p7m/preferenze.py, json.dump(..., indent=2), un dict
    # piatto) — non un parser JSON generico. La scrittura
    # (--set-preferenza) resta invece sul CLI: molto meno frequente,
    # un costo accettabile per una modifica reale dell'utente.
    [ -f "$FILE_PREFERENZE" ] || return 0
    sed -n "s/^  \"$1\": \"\(.*\)\",\{0,1\}\$/\1/p" "$FILE_PREFERENZE" | head -1
}

scrivi_log_e_mostra() {
    # $1: exit code, $2: full CLI output (stdout+stderr), $3: folder to
    # write the log into. A "display dialog" box cannot be resized or
    # scrolled, so the full (possibly long) CLI output is never put
    # there directly — only a short summary, with the full text saved
    # to a log file the user can open if needed.
    esito_totale="$1"
    testo_completo="$2"
    cartella_log="$3"

    # A folder picked via "choose folder" always comes back with a
    # trailing "/" (documented AppleScript behavior) — strip it before
    # concatenating, or the log path ends up with a doubled "//".
    cartella_log="${cartella_log%/}"

    log_abilitato=$(leggi_preferenza log)
    log_path="$cartella_log/sbusta-p7m-log.txt"
    if [ "$log_abilitato" != "off" ]; then
        {
            echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
            printf '%s\n' "$testo_completo"
            echo
        } >> "$log_path" 2>/dev/null
        dettagli="
Dettagli: $log_path"
    else
        dettagli=""
    fi

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

    export P7M_OUTPUT="$riepilogo$dettagli"

    # When at least one file was saved to the fallback folder (see
    # sbusta_p7m/cli.py's "fallback: <cartella>" line), offer a button
    # to open it directly instead of leaving the user to find it.
    cartella_fallback=$(printf '%s\n' "$testo_completo" | grep '^fallback:' | tail -1 | sed 's/^fallback: //')

    if [ "$esito_totale" -eq 0 ]; then
        titolo="sbusta-p7m"
        icona=""
    else
        titolo="sbusta-p7m — completato con errori"
        icona=" with icon caution"
    fi

    # "activate" first: a faceless script's dialog does not reliably
    # become frontmost on its own (documented AppleScript/Cocoa
    # behavior for InterfaceType-less Platypus apps) — without this,
    # the menu bar can stay on whatever app was active before, and
    # keyboard input (Esc included) may not reach the dialog at all.
    if [ -n "$cartella_fallback" ]; then
        risultato=$(osascript <<EOF
tell application "System Events" to activate
set msg to system attribute "P7M_OUTPUT"
display dialog msg with title "$titolo" buttons {"Apri cartella", "OK"} default button "OK" cancel button "OK"$icona
button returned of result
EOF
        )
        [ "$risultato" = "Apri cartella" ] && open "$cartella_fallback"
    else
        osascript <<EOF
tell application "System Events" to activate
set msg to system attribute "P7M_OUTPUT"
display dialog msg with title "$titolo" buttons {"OK"} default button "OK" cancel button "OK"$icona
EOF
    fi
}

mostra_preferenze() {
    # Read once on entry, not on every loop iteration — and via
    # leggi_preferenza (shell-only, no CLI invocation) rather than the
    # CLI at all: reading twice through the CLI still took ~2-3s to
    # open this screen, since even one PyInstaller onefile startup is
    # noticeable, let alone two in a row. Local variables are updated
    # directly after each --set-preferenza (still going through the
    # CLI: writes are rare, this cost is fine there).
    dest_attuale=$(leggi_preferenza destinazione)
    log_attuale=$(leggi_preferenza log)

    while :; do
        if [ -n "$dest_attuale" ]; then
            bottone_dest="Rimuovi cartella predefinita"
            dest_testo="$dest_attuale"
        else
            bottone_dest="Imposta cartella predefinita..."
            dest_testo="(nessuna, usa la cartella del file sorgente)"
        fi
        if [ "$log_attuale" = "off" ]; then
            bottone_log="Attiva il log"
            log_testo="disattivato"
        else
            bottone_log="Disattiva il log"
            log_testo="attivo"
        fi

        scelta=$(osascript <<EOF 2>/dev/null
tell application "System Events" to activate
display dialog "Cartella predefinita: $dest_testo
Log: $log_testo" buttons {"$bottone_dest", "$bottone_log", "Chiudi"} default button "Chiudi" cancel button "Chiudi" with title "sbusta-p7m — Preferenze"
button returned of result
EOF
        ) || break

        case "$scelta" in
            "$bottone_dest")
                if [ -n "$dest_attuale" ]; then
                    "$CLI" --set-preferenza destinazione ""
                    dest_attuale=""
                else
                    nuova=$(osascript -e 'POSIX path of (choose folder with prompt "Cartella predefinita:")' 2>/dev/null)
                    nuova="${nuova%/}"
                    if [ -n "$nuova" ]; then
                        "$CLI" --set-preferenza destinazione "$nuova"
                        dest_attuale="$nuova"
                    fi
                fi
                ;;
            "$bottone_log")
                if [ "$log_attuale" = "off" ]; then
                    "$CLI" --set-preferenza log on
                    log_attuale="on"
                else
                    "$CLI" --set-preferenza log off
                    log_attuale="off"
                fi
                ;;
        esac
    done
}

if [ "$#" -gt 0 ]; then
    # Droplet mode: one or more files/folders dropped onto the app icon.
    # -r is harmless on a single file (the CLI only applies it to
    # folders), and is the more useful default for a dropped folder.
    # A configured default destination applies here too (see
    # mostra_preferenze); without it, log written next to the first
    # dropped item, same as before — with multiple drops there's no
    # single shared destination folder to prefer instead.
    destinazione_preferita=$(leggi_preferenza destinazione)
    output=""
    esito_totale=0
    for percorso in "$@"; do
        if [ -n "$destinazione_preferita" ]; then
            out=$("$CLI" "$percorso" -r -d "$destinazione_preferita" 2>&1)
        else
            out=$("$CLI" "$percorso" -r 2>&1)
        fi
        esito=$?
        output="$output=== $percorso ===
$out

"
        if [ "$esito" -ne 0 ]; then
            esito_totale=1
        fi
    done
    if [ -n "$destinazione_preferita" ]; then
        cartella_log="$destinazione_preferita"
    elif [ -d "$1" ]; then
        cartella_log="$1"
    else
        cartella_log=$(dirname "$1")
    fi
    scrivi_log_e_mostra "$esito_totale" "$output" "$cartella_log"
    exit "$esito_totale"
fi

# No in-dialog "Aiuto" button: the system Aiuto menu already opens the
# registered Help Book correctly (via HPDBookAccessPath). A button
# here would invoke Help Viewer via an external `open help:` call
# instead of the native "Show Help" action, which doesn't reliably
# land on the same page (opens Help Viewer's general view instead) —
# not worth a redundant, less reliable path to the same content.
#
# Interactive mode, two real steps: a top-level choice (Annulla /
# Seleziona... / Preferenze...), then — for "Seleziona..." — a single
# native picker that accepts files AND folders together, one or more
# at a time (NSOpenPanel via JXA: classic AppleScript's "choose file"/
# "choose folder" can't mix the two). Selected items are processed
# exactly like droplet mode (-r on each, harmless on a single file).
# "Annulla" is a real cancel button everywhere (AppleScript only binds
# Esc/Cmd-. to -128 when a "cancel button" is explicitly named — an
# assumption the previous version of this script never actually had
# verified for the Esc key specifically); cancelling at any deeper
# step returns to this top level instead of exiting the app.
while :; do  # top level: Annulla / Seleziona / Preferenze
    scelta=$(osascript <<'EOF' 2>/dev/null
tell application "System Events" to activate
display dialog "Estrarre uno o più file .p7m e/o cartelle." buttons {"Annulla", "Seleziona...", "Preferenze..."} default button "Seleziona..." cancel button "Annulla" with title "sbusta-p7m"
button returned of result
EOF
    ) || exit 0

    if [ "$scelta" = "Preferenze..." ]; then
        mostra_preferenze
        continue
    fi

    percorsi=$(osascript -l JavaScript <<'EOF' 2>/dev/null
ObjC.import('AppKit');
function run() {
    // Without this, osascript never becomes the frontmost process on
    // its own (same root cause as the "activate" added to the
    // AppleScript dialogs above) — the panel showed but clicks inside
    // it were misrouted, closing it immediately instead of selecting
    // anything. floatingPanel helps it keep focus once activated.
    $.NSApplication.sharedApplication.activateIgnoringOtherApps(true);
    var panel = $.NSOpenPanel.openPanel;
    panel.floatingPanel = true;
    panel.canChooseFiles = true;
    panel.canChooseDirectories = true;
    panel.allowsMultipleSelection = true;
    panel.message = "Seleziona uno o più file .p7m e/o cartelle";
    panel.prompt = "Estrai";
    if (panel.runModal() !== 1) return "";  // 1 = NSFileHandlingPanelOKButton
    var urls = panel.URLs;
    var paths = [];
    for (var i = 0; i < urls.count; i++) {
        paths.push(ObjC.unwrap(urls.objectAtIndex(i).path));
    }
    return paths.join("\n");
}
EOF
    )
    # Picker cancelled (or nothing usable returned): back to the top
    # level, not an app exit — mirrors "Annulla" everywhere else.
    [ -z "$percorsi" ] && continue

    destinazione=""
    annullato=0
    while :; do  # destination folder, applies to the whole selection
        scelta_dest=$(osascript <<'EOF' 2>/dev/null
tell application "System Events" to activate
display dialog "Cartella di destinazione?" buttons {"Annulla", "Cartella sorgente", "Scegli..."} default button "Cartella sorgente" cancel button "Annulla" with title "sbusta-p7m"
button returned of result
EOF
        )
        ret=$?
        if [ "$ret" -ne 0 ]; then
            # Esc, window close, or "Annulla" itself (now the cancel
            # button, so a click on it also raises -128): same effect.
            annullato=1
            break
        fi
        case "$scelta_dest" in
            "Cartella sorgente")
                break
                ;;
            "Scegli...")
                destinazione=$(osascript -e 'POSIX path of (choose folder with prompt "Cartella di destinazione:")' 2>/dev/null)
                destinazione="${destinazione%/}"
                # If this inner picker is itself cancelled,
                # $destinazione stays empty and we loop back to the
                # three-way choice above, instead of guessing what the
                # user meant.
                [ -n "$destinazione" ] && break
                ;;
        esac
    done
    # Cancelling the destination choice goes back to the top level
    # (re-pick what to extract), doesn't exit the app.
    [ "$annullato" -eq 1 ] && continue

    break  # proceeds to extraction
done

output=""
esito_totale=0
# Split $percorsi (newline-separated) into positional parameters
# without a subshell (a `| while read` pipeline would run the loop in
# one, losing $output/$esito_totale afterwards) and without word- or
# glob-splitting each path on spaces/*/? — same POSIX-safe idiom used
# nowhere else in this file yet because droplet mode gets its paths
# already split, as "$@", from Platypus itself.
oldifs="$IFS"
IFS='
'
set -f
set -- $percorsi
set +f
IFS="$oldifs"
for percorso in "$@"; do
    if [ -n "$destinazione" ]; then
        out=$("$CLI" "$percorso" -r -d "$destinazione" 2>&1)
    else
        out=$("$CLI" "$percorso" -r 2>&1)
    fi
    esito=$?
    output="$output=== $percorso ===
$out

"
    if [ "$esito" -ne 0 ]; then
        esito_totale=1
    fi
done
if [ -n "$destinazione" ]; then
    cartella_log="$destinazione"
elif [ -d "$1" ]; then
    cartella_log="$1"
else
    cartella_log=$(dirname "$1")
fi

scrivi_log_e_mostra "$esito_totale" "$output" "$cartella_log"
exit "$esito_totale"
