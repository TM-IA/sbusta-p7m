import SwiftUI
import AppKit
import SbustaP7mCore

// First testable vertical slice of the macOS Swift rewrite: enough UI to
// pick file(s)/folder(s), run the real extraction+writing pipeline
// (SbustaP7mCore.elaboraFile), and see the result. Deliberately minimal —
// the full wizard/preferences UI from plan step 1.3 (three-level
// navigation, dedicated destination dialog, Preferences window, help)
// is not implemented yet.

@main
struct SbustaP7mMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct RigaEsito: Identifiable {
    let id = UUID()
    let testo: String
    let successo: Bool
}

struct ContentView: View {
    @State private var righe: [RigaEsito] = []
    @State private var elaborazioneInCorso = false
    @State private var mostraPreferenze = false
    @State private var cartellaDestinazioneUltima: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("sbusta-p7m").font(.title)
            Text("Estrae il PDF e i metadati del firmatario da una busta .p7m (CMS/PKCS#7).")
                .foregroundColor(.secondary)

            HStack {
                Button(elaborazioneInCorso ? "Elaborazione in corso…" : "Seleziona file o cartella…") {
                    selezionaESovraElabora()
                }
                .disabled(elaborazioneInCorso)

                Button("Preferenze…") {
                    mostraPreferenze = true
                }
            }

            if !righe.isEmpty {
                List(righe) { riga in
                    Text(riga.testo)
                        .foregroundColor(riga.successo ? Color.primary : Color.red)
                }
                .frame(minHeight: 220)

                HStack {
                    if let cartella = cartellaDestinazioneUltima {
                        Button("Apri cartella di destinazione") {
                            NSWorkspace.shared.open(cartella)
                        }
                    }
                    Button("Apri cartella di log") {
                        NSWorkspace.shared.open(Preferenze.cartellaDati())
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 380)
        .sheet(isPresented: $mostraPreferenze) {
            PreferenzeView(isPresented: $mostraPreferenze)
        }
    }

    private func selezionaESovraElabora() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Seleziona"
        panel.message = "Seleziona uno o più file .p7m, o una o più cartelle che li contengono."

        guard panel.runModal() == .OK else { return }
        let percorsi = panel.urls

        elaborazioneInCorso = true
        righe = []

        DispatchQueue.global(qos: .userInitiated).async {
            let percorsiFile = espandiSelezione(percorsi)
            let destinazionePreferita = Preferenze.leggi(.destinazione)

            let risultati: [RigaEsito] = percorsiFile.map { percorsoP7m in
                let cartellaDestinazione: URL
                if let dest = destinazionePreferita {
                    cartellaDestinazione = URL(fileURLWithPath: dest)
                } else {
                    cartellaDestinazione = URL(fileURLWithPath: percorsoP7m).deletingLastPathComponent()
                }
                let esito = elaboraFile(percorsoP7m: percorsoP7m, cartellaDestinazione: cartellaDestinazione)
                return rigaDa(esito, nome: (percorsoP7m as NSString).lastPathComponent)
            }

            // Destination folder tracked for the "Apri cartella di
            // destinazione" button and the auto-open preference: the
            // shared preference if set, otherwise the folder of the
            // first processed file — same simplification as the old
            // wrapper's single "cartella_log" for a whole batch (a
            // batch spanning several source folders with no fixed
            // destination only gets the first one tracked here).
            let cartellaBatch: URL? = {
                if let dest = destinazionePreferita { return URL(fileURLWithPath: dest) }
                guard let primo = percorsiFile.first else { return nil }
                return URL(fileURLWithPath: primo).deletingLastPathComponent()
            }()

            if !risultati.isEmpty, Preferenze.leggi(.log) != "off" {
                try? LogEstrazione.aggiungi(risultati.map { $0.testo }.joined(separator: "\n"))
            }

            DispatchQueue.main.async {
                self.righe = risultati.isEmpty
                    ? [RigaEsito(testo: "Nessun file .p7m trovato nella selezione.", successo: false)]
                    : risultati
                self.elaborazioneInCorso = false
                self.cartellaDestinazioneUltima = cartellaBatch
                if Preferenze.leggi(.apriDestinazioneAutomaticamente) == "on", let cartella = cartellaBatch {
                    NSWorkspace.shared.open(cartella)
                }
            }
        }
    }
}

/// Expands the panel selection (files and/or folders) into a flat list
/// of .p7m file paths — folders are scanned non-recursively for now
/// (the recursive option from the CLI's -r flag isn't wired into this
/// minimal UI yet, tracked as open work for plan step 1.3).
private func espandiSelezione(_ urls: [URL]) -> [String] {
    var risultato: [String] = []
    let fm = FileManager.default
    for url in urls {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
        if isDir.boolValue {
            if let contenuti = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for file in contenuti.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where file.pathExtension.lowercased() == "p7m" {
                    risultato.append(file.path)
                }
            }
        } else if url.pathExtension.lowercased() == "p7m" {
            risultato.append(url.path)
        }
    }
    return risultato
}

private func rigaDa(_ esito: EsitoElaborazione, nome: String) -> RigaEsito {
    switch esito {
    case .successo(_, let cartellaFile, let pdf, _, let usatoFallback, let avviso):
        var testo = "OK: \(nome) → \(cartellaFile)/\(pdf)"
        if usatoFallback { testo += " (cartella di fallback, permessi negati sulla destinazione)" }
        if avviso { testo += " [avviso: il contenuto non sembra un PDF valido]" }
        return RigaEsito(testo: testo, successo: true)
    case .erroreEstrazione(let messaggio):
        return RigaEsito(testo: "Errore: \(messaggio)", successo: false)
    case .erroreLettura(let messaggio):
        return RigaEsito(testo: "Errore: \(messaggio)", successo: false)
    case .destinazioneEsistente(let cartellaFile, let pdf, let json):
        return RigaEsito(testo: "Errore: \(nome): \(cartellaFile)/\(pdf) o \(json) già esistente, non sovrascritto", successo: false)
    case .erroreScrittura(let messaggio):
        return RigaEsito(testo: "Errore: \(messaggio)", successo: false)
    }
}
