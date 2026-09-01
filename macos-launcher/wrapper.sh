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
    # $1: chiave ("destinazione", "log" o "modalita"). Legge preferenze.json
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
    # "choose from list" instead of "display dialog": three
    # independent settings (cartella, log, modalità) plus a close
    # action don't fit in display dialog's 3-button cap. Read once on
    # entry via leggi_preferenza (shell-only, no CLI invocation) —
    # reading through the CLI still took ~2-3s to open this screen,
    # since even one PyInstaller onefile startup is noticeable, let
    # alone several. Local variables are updated directly after each
    # --set-preferenza (still going through the CLI: writes are rare,
    # this cost is fine there).
    dest_attuale=$(leggi_preferenza destinazione)
    log_attuale=$(leggi_preferenza log)
    modalita_attuale=$(leggi_preferenza modalita)
    [ -z "$modalita_attuale" ] && modalita_attuale="Chiedi"

    while :; do
        if [ -n "$dest_attuale" ]; then
            voce_dest="Cartella predefinita: $dest_attuale (clic per rimuovere)"
        else
            voce_dest="Cartella predefinita: nessuna (clic per impostare)"
        fi
        if [ "$log_attuale" = "off" ]; then
            voce_log="Log: disattivato (clic per attivare)"
        else
            voce_log="Log: attivo (clic per disattivare)"
        fi
        voce_modalita="Modalità apertura: $modalita_attuale (clic per cambiare)"

        scelta=$(osascript <<EOF 2>/dev/null
tell application "System Events" to activate
set sceltaLista to choose from list {"$voce_dest", "$voce_log", "$voce_modalita"} with prompt "Preferenze sbusta-p7m" with title "sbusta-p7m — Preferenze" cancel button name "Indietro"
if sceltaLista is false then
    return "CHIUDI"
else
    return item 1 of sceltaLista
end if
EOF
        )
        [ "$scelta" = "CHIUDI" ] && break

        case "$scelta" in
            "$voce_dest")
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
            "$voce_log")
                if [ "$log_attuale" = "off" ]; then
                    "$CLI" --set-preferenza log on
                    log_attuale="on"
                else
                    "$CLI" --set-preferenza log off
                    log_attuale="off"
                fi
                ;;
            "$voce_modalita")
                case "$modalita_attuale" in
                    Chiedi) modalita_attuale="File" ;;
                    File) modalita_attuale="Cartella" ;;
                    Cartella) modalita_attuale="Chiedi" ;;
                esac
                "$CLI" --set-preferenza modalita "$modalita_attuale"
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
# Interactive mode. The top level itself branches on the "modalita"
# preference (see mostra_preferenze): "Chiedi" (default) asks File vs
# Cartella via "choose from list" every time (not "display dialog",
# which caps out at 3 buttons — no room left for a real Annulla once
# Preferenze is also offered); "File" or "Cartella" skips straight to
# that picker, freeing enough room for a plain 3-button display dialog
# (Annulla/Preferenze/Seleziona — no type choice needed, it's already
# decided) instead of the plainer-looking list.
#
# Classic AppleScript has no single verb that lets you pick files and
# folders together (verified against Apple's own docs) — Cocoa's
# NSOpenPanel does, but calling it directly from JXA proved unreliable
# in this exact context (a faceless Platypus script): the panel opened
# but closed itself on any click inside it, even after forcing
# activation. "choose file"/"choose folder" are the same Standard
# Additions family already proven to work here (mostra_preferenze's
# folder picker), so those are used instead, each with "multiple
# selections allowed" — files and folders just can't be mixed in the
# same pick.
#
# Cancel behavior differs by verb, handled accordingly below:
# "choose from list" doesn't raise an error on Cancel/Esc, it returns
# boolean false (a well-known AppleScript asymmetry) — detected via
# the "ANNULLA" sentinel string. "choose file"/"choose folder" do
# raise -128, caught the same way as everywhere else in this script
# (nonzero osascript exit).
#
# "Annulla" (or Esc) at this top level is a real exit — nothing above
# it to go back to; cancelling at any deeper step returns here instead.
modalita=$(leggi_preferenza modalita)
[ -z "$modalita" ] && modalita="Chiedi"
destinazione_preferita=$(leggi_preferenza destinazione)

while :; do  # top level: File / Cartella / Preferenze
    if [ "$modalita" = "Chiedi" ]; then
        tipo=$(osascript <<'EOF' 2>/dev/null
tell application "System Events" to activate
set scelta to choose from list {"File", "Cartella", "Preferenze"} with prompt "Estrarre uno o più file .p7m, o tutti quelli in una o più cartelle?" with title "sbusta-p7m"
if scelta is false then
    return "ANNULLA"
else
    return item 1 of scelta
end if
EOF
        )
        [ "$tipo" = "ANNULLA" ] && exit 0

        if [ "$tipo" = "Preferenze" ]; then
            mostra_preferenze
            modalita=$(leggi_preferenza modalita)
            [ -z "$modalita" ] && modalita="Chiedi"
            destinazione_preferita=$(leggi_preferenza destinazione)
            continue
        fi
    else
        if [ "$modalita" = "File" ]; then
            testo_rapido="Estrarre uno o più file .p7m?"
        else
            testo_rapido="Estrarre tutti i file .p7m di una o più cartelle?"
        fi
        scelta_rapida=$(osascript <<EOF 2>/dev/null
tell application "System Events" to activate
display dialog "$testo_rapido" buttons {"Annulla", "Preferenze...", "Seleziona..."} default button "Seleziona..." cancel button "Annulla" with title "sbusta-p7m"
button returned of result
EOF
        ) || exit 0

        if [ "$scelta_rapida" = "Preferenze..." ]; then
            mostra_preferenze
            modalita=$(leggi_preferenza modalita)
            [ -z "$modalita" ] && modalita="Chiedi"
            destinazione_preferita=$(leggi_preferenza destinazione)
            continue
        fi
        tipo="$modalita"
    fi

    if [ "$tipo" = "File" ]; then
        percorsi=$(osascript <<'EOF' 2>/dev/null
tell application "System Events" to activate
set sceltaFile to choose file with prompt "Seleziona uno o più file .p7m:" multiple selections allowed true
set percorsi to ""
repeat with f in sceltaFile
    set percorsi to percorsi & POSIX path of f & linefeed
end repeat
return percorsi
EOF
        ) || continue
    else
        percorsi=$(osascript <<'EOF' 2>/dev/null
tell application "System Events" to activate
set sceltaCartelle to choose folder with prompt "Seleziona una o più cartelle:" multiple selections allowed true
set percorsi to ""
repeat with f in sceltaCartelle
    set percorsi to percorsi & POSIX path of f & linefeed
end repeat
return percorsi
EOF
        ) || continue
    fi
    # Picker cancelled at the AppleScript level would already have
    # been caught by the `|| continue` above; this only guards against
    # an empty-but-zero-exit edge case.
    [ -z "$percorsi" ] && continue

    if [ -n "$destinazione_preferita" ]; then
        # A configured default destination is used directly, same as
        # droplet mode — not offered as one more option alongside
        # "Cartella sorgente"/"Scegli...", the whole dialog is skipped.
        destinazione="$destinazione_preferita"
    else
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
    fi

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
