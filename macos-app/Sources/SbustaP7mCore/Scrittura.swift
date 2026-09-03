import Foundation

/// Port of sbusta_p7m/cli.py's naming (_stem_senza_p7m, _nomi_output)
/// and per-file writing (_elabora_file) logic. Unlike the CLI, this
/// returns a structured result instead of printing to stdout/stderr —
/// there is no subprocess boundary to cross here (in-process, same app),
/// so there is no reason to route through a text contract the way the
/// Linux GTK4 front does when it later reuses cli.py's own refactor.

/// Strips every trailing ".p7m" extension (case-insensitive), without
/// touching any other extension already present (e.g. "nome.pdf.p7m" ->
/// "nome.pdf"). A file signed more than once has one .p7m per envelope
/// layer — all of them are stripped, not just the last one. Mirrors
/// cli.py's _stem_senza_p7m exactly.
func stemSenzaP7m(_ nomeFile: String) -> String {
    var nome = nomeFile
    while nome.lowercased().hasSuffix(".p7m") {
        nome = String(nome.dropLast(4))
    }
    return nome
}

/// Computes the (folder name, pdf filename, json filename) triple for a
/// given .p7m input path — mirrors cli.py's _nomi_output exactly,
/// including the "nome.p7m" vs "nome.pdf.p7m" naming distinction.
public func nomiOutput(percorsoP7m: String) -> (cartella: String, pdf: String, json: String) {
    let base = (percorsoP7m as NSString).lastPathComponent
    let senzaP7m = stemSenzaP7m(base)
    let pdfFilename: String
    let stem: String
    if senzaP7m.lowercased().hasSuffix(".pdf") {
        pdfFilename = senzaP7m
        stem = String(senzaP7m.dropLast(4))
    } else {
        pdfFilename = senzaP7m + ".pdf"
        stem = senzaP7m
    }
    return (stem, pdfFilename, stem + ".json")
}

/// Outcome of processing one .p7m file — mirrors the branches of
/// cli.py's _elabora_file (format/content error, unreadable, existing
/// destination never overwritten, write error, permission-denied
/// fallback), as a value type instead of printed lines + a bool.
public enum EsitoElaborazione {
    case successo(cartellaRadice: URL, cartellaFile: String, pdf: String, json: String, usatoFallback: Bool, avvisoNonPDF: Bool)
    case erroreEstrazione(String)
    case erroreLettura(String)
    case destinazioneEsistente(cartellaFile: String, pdf: String, json: String)
    case erroreScrittura(String)
}

private func nsErrorIndicaPermessiNegati(_ error: Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError
}

/// Extracts one .p7m file and writes its .pdf/.json pair under
/// `cartellaDestinazione` (falling back to Preferenze.cartellaFallback()
/// on a permission error, same as cli.py). Never throws — every failure
/// mode becomes an EsitoElaborazione case, same "always tell the caller
/// what happened, never crash the batch" contract as the Python CLI.
public func elaboraFile(percorsoP7m: String, cartellaDestinazione: URL) -> EsitoElaborazione {
    let nome = (percorsoP7m as NSString).lastPathComponent

    let risultato: RisultatoEstrazione
    do {
        risultato = try estrai(percorsoP7m: percorsoP7m)
    } catch let errore as P7mError {
        return .erroreEstrazione("\(nome): \(errore.description)")
    } catch {
        return .erroreLettura("\(nome): impossibile leggere il file (\(error.localizedDescription))")
    }

    let avvisoNonPDF = !risultato.dati.starts(with: Data("%PDF-".utf8))
    let (cartellaNome, pdfFilename, jsonFilename) = nomiOutput(percorsoP7m: percorsoP7m)
    let cartellaFile = cartellaDestinazione.appendingPathComponent(cartellaNome, isDirectory: true)
    let pdfPath = cartellaFile.appendingPathComponent(pdfFilename)
    let jsonPath = cartellaFile.appendingPathComponent(jsonFilename)

    if FileManager.default.fileExists(atPath: pdfPath.path) || FileManager.default.fileExists(atPath: jsonPath.path) {
        return .destinazioneEsistente(cartellaFile: cartellaNome, pdf: pdfFilename, json: jsonFilename)
    }

    let metadataConPdf = Metadata(
        fileOriginale: risultato.metadata.fileOriginale,
        pdfEstratto: pdfFilename,
        firmatari: risultato.metadata.firmatari
    )

    func scrivi(in cartella: URL) throws {
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        try risultato.dati.write(to: cartella.appendingPathComponent(pdfFilename), options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        var jsonData = try encoder.encode(metadataConPdf)
        jsonData.append(0x0A) // trailing newline, matching cli.py
        try jsonData.write(to: cartella.appendingPathComponent(jsonFilename), options: .atomic)
    }

    do {
        try scrivi(in: cartellaFile)
        return .successo(cartellaRadice: cartellaDestinazione, cartellaFile: cartellaNome, pdf: pdfFilename, json: jsonFilename, usatoFallback: false, avvisoNonPDF: avvisoNonPDF)
    } catch {
        guard nsErrorIndicaPermessiNegati(error) else {
            return .erroreScrittura("\(nome): impossibile scrivere il file di destinazione (\(error.localizedDescription))")
        }
        let cartellaFallbackRadice = Preferenze.cartellaFallback()
        let cartellaFallback = cartellaFallbackRadice.appendingPathComponent(cartellaNome, isDirectory: true)
        do {
            try scrivi(in: cartellaFallback)
            return .successo(cartellaRadice: cartellaFallbackRadice, cartellaFile: cartellaNome, pdf: pdfFilename, json: jsonFilename, usatoFallback: true, avvisoNonPDF: avvisoNonPDF)
        } catch let erroreFallback {
            return .erroreScrittura("\(nome): permessi negati sulla cartella di destinazione; anche il fallback è fallito (\(erroreFallback.localizedDescription))")
        }
    }
}
