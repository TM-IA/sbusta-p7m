import SwiftUI
import AppKit
import SbustaP7mCore

/// Preferences window: reads/writes 2 of the 3 keys the Platypus
/// wrapper's Preferenze dialog exposed (destinazione, log), same file
/// (Preferenze.swift → ~/Library/Application Support/sbusta-p7m/preferenze.json).
/// `modalita` (File/Cartella/Chiedi) is deliberately not exposed here:
/// it only existed to work around AppleScript's 3-button dialog limit
/// (a fixed mode let the wrapper skip asking File-or-Cartella so a
/// button was free for Preferenze+Annulla) — NSOpenPanel already lets
/// this app's picker mix files and folders in one selection, so the
/// whole question is moot. The key itself stays valid in the shared
/// preferenze.json/CLI contract (Android/Linux still reference it),
/// just unused by this app's UI — same choice the Linux zenity wrapper
/// already made for the same underlying reason (no button-count limit
/// there either).
/// Presented as a sheet from ContentView (isPresented binding rather
/// than @Environment(\.dismiss), which needs macOS 12+ — this package
/// targets macOS 11).
struct PreferenzeView: View {
    @Binding var isPresented: Bool

    @State private var destinazione: String?
    @State private var logAttivo: Bool
    @State private var apriAutomaticamente: Bool
    @State private var erroreScrittura: String?

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _destinazione = State(initialValue: Preferenze.leggi(.destinazione))
        _logAttivo = State(initialValue: Preferenze.leggi(.log) != "off") // default on, matches cli.py
        _apriAutomaticamente = State(initialValue: Preferenze.leggi(.apriDestinazioneAutomaticamente) == "on")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Preferenze").font(.title2).bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Cartella di destinazione").font(.headline)
                Text(destinazione == nil
                     ? "Cartella sorgente (nessuna destinazione impostata)"
                     : "Cartella selezionata")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text(destinazione ?? "—")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    if destinazione != nil {
                        Button("Rimuovi") { impostaDestinazione(nil) }
                    }
                    Button("Scegli…") { scegliDestinazione() }
                }
            }

            Toggle("Log attivo", isOn: $logAttivo)
                .onChange(of: logAttivo) { nuovo in
                    salva(.log, nuovo ? "on" : "off")
                }

            Toggle("Apri automaticamente la cartella di destinazione dopo l'estrazione", isOn: $apriAutomaticamente)
                .onChange(of: apriAutomaticamente) { nuovo in
                    salva(.apriDestinazioneAutomaticamente, nuovo ? "on" : "off")
                }

            if let errore = erroreScrittura {
                Text(errore).foregroundColor(.red).font(.callout)
            }

            HStack {
                Spacer()
                Button("Chiudi") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private func scegliDestinazione() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Imposta come destinazione"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        impostaDestinazione(url.path)
    }

    private func impostaDestinazione(_ percorso: String?) {
        destinazione = percorso
        salva(.destinazione, percorso ?? "")
    }

    private func salva(_ chiave: ChiavePreferenza, _ valore: String) {
        do {
            try Preferenze.scrivi(chiave, valore: valore)
            erroreScrittura = nil
        } catch {
            erroreScrittura = "Impossibile salvare la preferenza: \(error.localizedDescription)"
        }
    }
}
