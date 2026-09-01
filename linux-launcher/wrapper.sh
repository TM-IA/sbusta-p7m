#!/bin/sh
# zenity wrapper: native dialogs around the bundled sbusta-p7m
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
CLI="$HOME/.local/bin/sbusta-p7m"
HELP_TXT="$SCRIPT_DIR/help/index.txt"

scrivi_log_e_mostra() {
    # $1: exit code, $2: full CLI output (stdout+stderr), $3: folder to
    # write the log into. Same reasoning as the macOS wrapper: no GUI
    # dialog here can show a long scrollable batch output readably,
    # so only a short summary is shown, full text goes to a log file.
    esito_totale="$1"
    testo_completo="$2"
    cartella_log="$3"

    log_abilitato=$("$CLI" --get-preferenza log 2>/dev/null)
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

    riepilogo=$(printf '%s\n' "$testo_completo" | grep '^riepilogo:' | tail -1)
    if [ -z "$riepilogo" ]; then
        if [ "$esito_totale" -eq 0 ]; then
            riepilogo="Estrazione completata con successo."
        else
            riepilogo="Estrazione fallita."
        fi
    fi

    # When at least one file was saved to the fallback folder (see
    # sbusta_p7m/cli.py's "fallback: <cartella>" line), offer a button
    # to open it directly instead of leaving the user to find it.
    # --info/--error only support a single OK button, so switch to
    # --question (ok-label/cancel-label repurposed, no real "cancel"
    # meaning here — same technique used elsewhere in this file for
    # two-way choices).
    cartella_fallback=$(printf '%s\n' "$testo_completo" | grep '^fallback:' | tail -1 | sed 's/^fallback: //')

    if [ -n "$cartella_fallback" ]; then
        if [ "$esito_totale" -eq 0 ]; then
            titolo="sbusta-p7m"
            icona=""
        else
            titolo="sbusta-p7m — completato con errori"
            icona="--icon-name=dialog-error"
        fi
        zenity --question --title="$titolo" $icona \
            --text="$riepilogo$dettagli" \
            --ok-label="Apri cartella" --cancel-label="OK" 2>/dev/null
        ret=$?
        [ "$ret" -eq 0 ] && xdg-open "$cartella_fallback" >/dev/null 2>&1 &
    elif [ "$esito_totale" -eq 0 ]; then
        zenity --info --title="sbusta-p7m" \
            --text="$riepilogo$dettagli" 2>/dev/null
    else
        zenity --error --title="sbusta-p7m — completato con errori" \
            --text="$riepilogo$dettagli" 2>/dev/null
    fi
}

mostra_preferenze() {
    while :; do
        dest_attuale=$("$CLI" --get-preferenza destinazione 2>/dev/null)
        log_attuale=$("$CLI" --get-preferenza log 2>/dev/null)

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

        risposta=$(zenity --question --title="sbusta-p7m — Preferenze" \
            --text="Cartella predefinita: $dest_testo
Log: $log_testo" \
            --ok-label="Chiudi" --cancel-label="Annulla" \
            --extra-button="$bottone_dest" --extra-button="$bottone_log" 2>/dev/null)
        ret=$?
        if [ "$ret" -eq 0 ]; then
            break
        fi
        case "$risposta" in
            "$bottone_dest")
                if [ -n "$dest_attuale" ]; then
                    "$CLI" --set-preferenza destinazione ""
                else
                    nuova=$(zenity --file-selection --directory --title="Cartella predefinita" 2>/dev/null)
                    [ -n "$nuova" ] && "$CLI" --set-preferenza destinazione "$nuova"
                fi
                ;;
            "$bottone_log")
                if [ "$log_attuale" = "off" ]; then
                    "$CLI" --set-preferenza log on
                else
                    "$CLI" --set-preferenza log off
                fi
                ;;
            *)
                break
                ;;
        esac
    done
}

if [ "$#" -gt 0 ]; then
    # Droplet-equivalent: one or more files/folders passed as
    # arguments (file manager "Open With", or a .desktop MIME
    # association). -r is harmless on a single file. A configured
    # default destination applies here too (see mostra_preferenze).
    destinazione_preferita=$("$CLI" --get-preferenza destinazione 2>/dev/null)
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

# Interactive mode: ask what to process.
#
# zenity --question only gives a binary OK/Cancel outcome via exit
# code (0 = OK, 1 = Cancel); --extra-button adds a third option that
# ALSO exits 1, but prints its own label to stdout — so a third choice
# is distinguished from a plain Cancel by checking stdout, not just
# the exit code. This differs from macOS's "display dialog", which
# returns each button's name directly; ported carefully, not assumed
# to behave the same.
# Wizard-style navigation with a real "back" across 3 levels: Annulla/
# Esc/window close at any level returns to the level above, it doesn't
# exit the app — only level 1 (nothing above it) is a real exit.
# Implemented with `continue 2` / `break 2` (nested loop levels):
# standard POSIX syntax (not a bashism), verified here where /bin/sh is
# bash, but not tested against dash in this session (on Debian/Ubuntu
# /bin/sh is dash) — to be reconfirmed if issues show up there.
while :; do  # level 1: File / Cartella / Aiuto / Preferenze
    # --no-cancel is not supported by this dialog type (verified:
    # zenity exits immediately with "--no-cancel is not supported for
    # this dialog"), so the Cancel button can't be hidden: it stays
    # visible, relabeled "Annulla".
    risposta=$(zenity --question --title="sbusta-p7m" \
        --text="Estrarre un file .p7m singolo o tutti i file in una cartella?" \
        --ok-label="File" --cancel-label="Annulla" \
        --extra-button="Cartella" --extra-button="Aiuto" --extra-button="Preferenze..." 2>/dev/null)
    ret=$?
    if [ "$ret" -eq 0 ]; then
        tipo="File"
    elif [ "$risposta" = "Cartella" ]; then
        tipo="Cartella"
    elif [ "$risposta" = "Aiuto" ]; then
        zenity --text-info --title="sbusta-p7m — Aiuto" \
            --filename="$HELP_TXT" --width=560 --height=440 2>/dev/null
        continue
    elif [ "$risposta" = "Preferenze..." ]; then
        mostra_preferenze
        continue
    else
        # No level above this one: Annulla/Esc/window close really do
        # exit the app.
        exit 0
    fi

    while :; do  # level 2: source file/folder selection
        if [ "$tipo" = "File" ]; then
            percorso=$(zenity --file-selection --title="Seleziona un file .p7m" \
                --file-filter="*.p7m" 2>/dev/null) || continue 2
            ricorsivo=""
        else
            percorso=$(zenity --file-selection --directory \
                --title="Seleziona una cartella" 2>/dev/null) || continue 2
            ricorsivo="-r"
        fi

        # Same three-way choice as macOS (0.1.7): "Annulla" genuinely
        # aborts, it does not mean "proceed with the source folder" —
        # that was a real bug there, not repeated here from the start.
        destinazione=""
        annullato=0
        while :; do  # level 3: destination folder
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
                # Annulla/Esc at level 3: goes back to level 2 (re-pick
                # source file/folder), doesn't exit the app.
                annullato=1
                break
            fi
        done
        [ "$annullato" -eq 1 ] && continue

        break 2  # proceeds to extraction, exiting both loops
    done
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
