import Foundation

/// Preference keys — same 3-key contract as sbusta_p7m/preferenze.py's
/// _CHIAVI_VALIDE, represented as a Swift enum instead of a runtime
/// string-set check: the type system already rules out the "unknown key"
/// case Python guards against with a ValueError, so no equivalent
/// runtime check is needed here.
public enum ChiavePreferenza: String {
    case destinazione
    case log
    case modalita
    /// macOS-app-only, NOT part of the shared preferenze.json/CLI
    /// contract (--get-preferenza/--set-preferenza only knows
    /// destinazione/log/modalita) — safe to add here because this
    /// Swift implementation reads/writes the JSON file directly and
    /// never round-trips through the Python CLI's key validation.
    case apriDestinazioneAutomaticamente
}

/// Swift port of sbusta_p7m/preferenze.py. This package targets macOS
/// only (see Package.swift), so only the darwin branch of the Python
/// module is ported — same file
/// (~/Library/Application Support/sbusta-p7m/preferenze.json), same flat
/// JSON schema, same semantics (an empty value removes the key instead
/// of persisting an empty string). Reading and writing this exact file
/// keeps a user's preferences intact across the switch from the Platypus
/// wrapper to this native app — no migration needed.
public enum Preferenze {
    private static let nomeFile = "preferenze.json"

    public static func cartellaConfig() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/sbusta-p7m", isDirectory: true)
    }

    // macOS convention: one Application Support folder for both config
    // and data, unlike Linux's XDG split (preferenze.py's cartella_dati()
    // does the same thing on darwin).
    public static func cartellaDati() -> URL { cartellaConfig() }

    public static func cartellaFallback() -> URL {
        cartellaDati().appendingPathComponent("estrazioni-fallback", isDirectory: true)
    }

    private static func percorsoPreferenze() -> URL {
        cartellaConfig().appendingPathComponent(nomeFile)
    }

    /// Returns the stored value for `chiave`, or nil if unset, the file
    /// is missing, or it's corrupted — never throws for the caller, same
    /// contract as preferenze.py's leggi().
    public static func leggi(_ chiave: ChiavePreferenza) -> String? {
        guard let dati = try? Data(contentsOf: percorsoPreferenze()),
              let json = try? JSONSerialization.jsonObject(with: dati) as? [String: Any] else {
            return nil
        }
        let valore = json[chiave.rawValue] as? String
        return (valore?.isEmpty ?? true) ? nil : valore
    }

    /// Persists chiave=valore (valore == "" removes the key instead of
    /// storing an empty string, letting a preference be cleared) — same
    /// contract as preferenze.py's scrivi().
    public static func scrivi(_ chiave: ChiavePreferenza, valore: String) throws {
        let percorso = percorsoPreferenze()
        var json: [String: Any] = [:]
        if let dati = try? Data(contentsOf: percorso),
           let esistente = try? JSONSerialization.jsonObject(with: dati) as? [String: Any] {
            json = esistente
        }
        if valore.isEmpty {
            json.removeValue(forKey: chiave.rawValue)
        } else {
            json[chiave.rawValue] = valore
        }
        try FileManager.default.createDirectory(at: cartellaConfig(), withIntermediateDirectories: true)
        var output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        output.append(0x0A) // trailing newline, matching preferenze.py
        try output.write(to: percorso, options: .atomic)
    }
}
