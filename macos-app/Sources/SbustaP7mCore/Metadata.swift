import Foundation

/// One signer entry ("firmatario"). Field names and JSON keys mirror
/// sbusta_p7m/core.py exactly (see its docstring for the schema) and the
/// Kotlin port (Estrazione.kt's `Firmatario`) — every field is present in
/// the encoded JSON even when unresolved (encoded as `null`, never
/// omitted), matching both other implementations.
public struct Firmatario: Codable {
    public let cn: String?
    public let organizzazione: String?
    public let numeroSeriale: String?
    public let validitaInizio: String?
    public let validitaFine: String?
    public let algoritmoFirma: String?
    public let signingTime: String?
    public let livello: Int

    enum CodingKeys: String, CodingKey {
        case cn
        case organizzazione
        case numeroSeriale = "numero_seriale"
        case validitaInizio = "validita_inizio"
        case validitaFine = "validita_fine"
        case algoritmoFirma = "algoritmo_firma"
        case signingTime = "signing_time"
        case livello
    }

    public init(
        cn: String? = nil,
        organizzazione: String? = nil,
        numeroSeriale: String? = nil,
        validitaInizio: String? = nil,
        validitaFine: String? = nil,
        algoritmoFirma: String? = nil,
        signingTime: String? = nil,
        livello: Int
    ) {
        self.cn = cn
        self.organizzazione = organizzazione
        self.numeroSeriale = numeroSeriale
        self.validitaInizio = validitaInizio
        self.validitaFine = validitaFine
        self.algoritmoFirma = algoritmoFirma
        self.signingTime = signingTime
        self.livello = livello
    }
}

/// Result of `estrai(percorsoP7m:)`: the extracted content bytes plus the
/// metadata dict, same schema as `sbusta_p7m.core.estrai()` (Python) and
/// `RisultatoEstrazione` (Kotlin). `Metadata` alone is what gets encoded
/// to the sidecar `.json` file; the extracted bytes are written to the
/// `.pdf` file separately by the caller (naming/writing is not this
/// module's job, same separation of concerns as core.py).
public struct Metadata: Codable {
    public let fileOriginale: String
    public let pdfEstratto: String?
    public let firmatari: [Firmatario]

    enum CodingKeys: String, CodingKey {
        case fileOriginale = "file_originale"
        case pdfEstratto = "pdf_estratto"
        case firmatari
    }

    public init(fileOriginale: String, pdfEstratto: String? = nil, firmatari: [Firmatario]) {
        self.fileOriginale = fileOriginale
        self.pdfEstratto = pdfEstratto
        self.firmatari = firmatari
    }
}

public struct RisultatoEstrazione {
    public let dati: Data
    public let metadata: Metadata
}
