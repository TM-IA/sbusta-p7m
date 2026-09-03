import Foundation

/// Batch extraction log — unlike the Platypus wrapper (which wrote
/// sbusta-p7m-log.txt inside the destination folder of each run), this
/// lives at a single fixed location alongside preferenze.json
/// (~/Library/Application Support/sbusta-p7m/sbusta-p7m-log.txt),
/// independent of where any given extraction's output goes. Deliberate
/// behavior change, decided with the user: a fixed log location is what
/// makes a dedicated "apri cartella di log" button meaningful, decoupled
/// from "apri cartella di destinazione" (which reflects the current
/// batch's actual output folder, and can differ run to run).
public enum LogEstrazione {
    public static func percorso() -> URL {
        Preferenze.cartellaDati().appendingPathComponent("sbusta-p7m-log.txt")
    }

    private static let formattatoreTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter // local system time zone, same as the old wrapper's `date` command
    }()

    /// Appends one timestamped block to the log file — never overwrites,
    /// same append-only contract as the wrapper's log. Respects the
    /// `log` preference (default on): callers should check
    /// `Preferenze.leggi(.log) != "off"` before calling this, same as
    /// cli.py/wrapper.sh do, rather than this function silently no-oping.
    public static func aggiungi(_ testo: String) throws {
        let cartella = Preferenze.cartellaDati()
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        let blocco = "\n--- \(formattatoreTimestamp.string(from: Date())) ---\n\(testo)\n"

        let percorsoFile = percorso()
        if let handle = FileHandle(forWritingAtPath: percorsoFile.path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(Data(blocco.utf8))
        } else {
            try Data(blocco.utf8).write(to: percorsoFile)
        }
    }
}
