import Foundation
import Security

/// Swift port of sbusta_p7m/core.py (and, in spirit, of the Kotlin port
/// Estrazione.kt) — same "firmatari" schema (including "livello", one
/// entry per SignerInfo, several co-signers on one layer contribute
/// several entries sharing that livello), same iterative unwrapping of
/// nested envelopes until the raw PDF emerges. Structural extraction
/// only: no signature/chain/revocation validation (see
/// project-docs/status/macos-swift.md for why CMSDecoder is safe to use
/// for this despite normally being trust-oriented).
///
/// Uses CMSDecoder (Security.framework) for everything except one field:
/// `algoritmo_firma` has no public CMSDecoder accessor (verified against
/// the real CMSDecoder.h header, not assumed) — that one field is read
/// with a small dedicated DER walker, see DERWalker.swift.

// Defensive cap on how many nested CMS envelopes are unwrapped, same as
// core.py's MAX_LIVELLI: guards a pathological input, not a known real
// limit.
private let maxLivelli = 10

private let isoFormatter: DateFormatter = {
    let formatter = DateFormatter()
    // Matches core.py's `.isoformat()` and the Kotlin port's isoFormat()
    // ("+00:00", not the "Z" that Foundation's ISO8601DateFormatter
    // defaults to) — cross-platform output consistency, not just a
    // Swift convention choice.
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxxxx"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter
}()

private func isPdf(_ dati: Data) -> Bool {
    let header = Data("%PDF-".utf8)
    return dati.count >= header.count && dati.prefix(header.count) == header
}

/// SecCertificateCopySerialNumberData returns the raw big-endian bytes of
/// the certificate's ASN.1 INTEGER serial number — arbitrarily large, no
/// bignum type in the Swift standard library. Converts to the same
/// decimal string format Python's `str(cert.serial_number)` produces. A
/// leading 0x00 padding byte (DER keeping the INTEGER's sign bit clear)
/// contributes 0 to the running total and needs no special-casing —
/// verified against the long decimal serials already known from the
/// Android-shared test fixtures (see EstrazioneTests.swift).
private func decimaleDaBytesBigEndian(_ bytes: Data) -> String {
    var cifre: [UInt8] = [0] // decimal digits, least-significant first
    for byte in bytes {
        var riporto = Int(byte)
        for i in 0..<cifre.count {
            let valore = Int(cifre[i]) * 256 + riporto
            cifre[i] = UInt8(valore % 10)
            riporto = valore / 10
        }
        while riporto > 0 {
            cifre.append(UInt8(riporto % 10))
            riporto /= 10
        }
    }
    while cifre.count > 1 && cifre.last == 0 {
        cifre.removeLast()
    }
    return cifre.reversed().map { String($0) }.joined()
}

/// Reads one component out of a certificate's Subject Name RDN array by
/// its OID (e.g. "2.5.4.10" for organizationName). organizationName is
/// NOT its own top-level SecCertificateCopyValues entry, it lives nested
/// inside the kSecOIDX509V1SubjectName section's RDN array (verified
/// empirically, not documented behavior).
private func componenteSubject(_ cert: SecCertificate, rdnOid: String) -> String? {
    guard let values = SecCertificateCopyValues(cert, [kSecOIDX509V1SubjectName] as CFArray, nil) as? [CFString: Any],
          let subjectEntry = values[kSecOIDX509V1SubjectName] as? [CFString: Any],
          let rdns = subjectEntry[kSecPropertyKeyValue] as? [[CFString: Any]] else {
        return nil
    }
    for rdn in rdns {
        if let label = rdn[kSecPropertyKeyLabel] as? String, label == rdnOid {
            return rdn[kSecPropertyKeyValue] as? String
        }
    }
    return nil
}

/// Reads a "Not Valid Before"/"Not Valid After" field — empirically these
/// come back as a `number` (CFAbsoluteTime, seconds since 2001-01-01),
/// not a CFDate.
private func dataValidita(_ cert: SecCertificate, oid: CFString) -> String? {
    guard let values = SecCertificateCopyValues(cert, [oid] as CFArray, nil) as? [CFString: Any],
          let entry = values[oid] as? [CFString: Any],
          let secondi = entry[kSecPropertyKeyValue] as? Double else {
        return nil
    }
    return isoFormatter.string(from: Date(timeIntervalSinceReferenceDate: secondi))
}

private struct SignerGrezzo {
    let cert: SecCertificate?
    let signingTime: String?
}

private struct LivelloDecodificato {
    /// nil means a detached signature: the envelope parsed but carries
    /// no embedded content.
    let contenuto: Data?
    let signer: [SignerGrezzo]
}

/// Decodes exactly one CMS layer with CMSDecoder. Throws P7mError.formatoNonValido
/// for anything CMSDecoder itself rejects (not ASN.1/DER at all, or DER
/// that isn't a SignedData ContentInfo — CMSDecoder is specifically a
/// SignedData decoder, so a different top-level CMS content type is
/// expected to fail here too, though this hasn't been exercised against
/// a real non-SignedData fixture, only inferred from CMSDecoder's own
/// purpose — flagged as an assumption, not verified fact).
private func decodificaLivello(_ dati: Data) throws -> LivelloDecodificato {
    var decoderOpt: CMSDecoder?
    var status = CMSDecoderCreate(&decoderOpt)
    guard status == errSecSuccess, let decoder = decoderOpt else {
        throw P7mError.formatoNonValido("CMSDecoderCreate fallita (status \(status))")
    }

    status = dati.withUnsafeBytes { raw -> OSStatus in
        guard let base = raw.baseAddress else { return errSecParam }
        return CMSDecoderUpdateMessage(decoder, base, dati.count)
    }
    guard status == errSecSuccess else {
        throw P7mError.formatoNonValido("CMSDecoderUpdateMessage fallita (status \(status))")
    }

    status = CMSDecoderFinalizeMessage(decoder)
    guard status == errSecSuccess else {
        throw P7mError.formatoNonValido("CMSDecoderFinalizeMessage fallita (status \(status))")
    }

    var contentCF: CFData?
    _ = CMSDecoderCopyContent(decoder, &contentCF)
    let contenuto = contentCF as Data?

    var numSigners = 0
    _ = CMSDecoderGetNumSigners(decoder, &numSigners)

    var signer: [SignerGrezzo] = []
    signer.reserveCapacity(numSigners)
    for i in 0..<numSigners {
        var certOpt: SecCertificate?
        _ = CMSDecoderCopySignerCert(decoder, i, &certOpt)

        var signTimeAbs: CFAbsoluteTime = 0
        let timeStatus = CMSDecoderCopySignerSigningTime(decoder, i, &signTimeAbs)
        let signingTime: String? = timeStatus == errSecSuccess
            ? isoFormatter.string(from: Date(timeIntervalSinceReferenceDate: signTimeAbs))
            : nil

        signer.append(SignerGrezzo(cert: certOpt, signingTime: signingTime))
    }

    return LivelloDecodificato(contenuto: contenuto, signer: signer)
}

/// Builds one metadata entry per SignerInfo of this envelope layer, same
/// "no cap, unlike maxLivelli" contract as core.py/Estrazione.kt.
/// `algoritmi` comes from DERWalker.algoritmiFirma, matched to `signer`
/// by index (both walk the same encoded signerInfos SET in the same
/// order) — see DERWalker.swift for why that pairing is best-effort, not
/// guaranteed by any API contract.
private func metadataFirmatariLivello(_ decodificato: LivelloDecodificato, algoritmi: [String?], livello: Int) -> [Firmatario] {
    if decodificato.signer.isEmpty {
        return [Firmatario(livello: livello)]
    }
    return decodificato.signer.enumerated().map { indice, grezzo in
        var cn: String? = nil
        var organizzazione: String? = nil
        var numeroSeriale: String? = nil
        var validitaInizio: String? = nil
        var validitaFine: String? = nil

        if let cert = grezzo.cert {
            var cnCF: CFString?
            SecCertificateCopyCommonName(cert, &cnCF)
            cn = cnCF as String?
            organizzazione = componenteSubject(cert, rdnOid: "2.5.4.10")
            validitaInizio = dataValidita(cert, oid: kSecOIDX509V1ValidityNotBefore)
            validitaFine = dataValidita(cert, oid: kSecOIDX509V1ValidityNotAfter)

            var errRef: Unmanaged<CFError>?
            if let serialData = SecCertificateCopySerialNumberData(cert, &errRef) as Data? {
                numeroSeriale = decimaleDaBytesBigEndian(serialData)
            }
        }

        return Firmatario(
            cn: cn,
            organizzazione: organizzazione,
            numeroSeriale: numeroSeriale,
            validitaInizio: validitaInizio,
            validitaFine: validitaFine,
            algoritmoFirma: indice < algoritmi.count ? algoritmi[indice] : nil,
            signingTime: grezzo.signingTime,
            livello: livello
        )
    }
}

/// Extracts the embedded PDF and signer metadata from a DER-encoded
/// .p7m (CMS SignedData) envelope, unwrapping nested envelopes when the
/// embedded content is itself another CMS SignedData (a document signed
/// more than once, e.g. "file.pdf.p7m.p7m") until the raw PDF emerges —
/// same logic as sbusta_p7m.core.estrai().
public func estrai(percorsoP7m: String) throws -> RisultatoEstrazione {
    var dati = try Data(contentsOf: URL(fileURLWithPath: percorsoP7m))
    let nomeFile = (percorsoP7m as NSString).lastPathComponent
    var firmatari: [Firmatario] = []
    var livello = 0

    while true {
        let decodificato: LivelloDecodificato
        do {
            decodificato = try decodificaLivello(dati)
        } catch {
            if livello == 0 {
                throw P7mError.formatoNonValido("'\(nomeFile)' non è una struttura ASN.1/CMS valida")
            }
            // Not a nested CMS envelope: `dati` is the final raw content.
            break
        }

        guard let contenutoInterno = decodificato.contenuto else {
            if livello == 0 {
                throw P7mError.contenutoNonRecuperabile(
                    "'\(nomeFile)' ha una firma detached (nessun contenuto incorporato), non supportata in questa fase"
                )
            }
            // A detached envelope found while unwrapping an inner layer:
            // keep `dati` (this envelope's own bytes) as the final content.
            break
        }

        let algoritmi = DERWalker.algoritmiFirma(daBusta: dati)
        firmatari.append(contentsOf: metadataFirmatariLivello(decodificato, algoritmi: algoritmi, livello: livello))

        dati = contenutoInterno
        livello += 1

        if isPdf(dati) || livello >= maxLivelli {
            break
        }
    }

    let metadata = Metadata(fileOriginale: nomeFile, pdfEstratto: nil, firmatari: firmatari)
    return RisultatoEstrazione(dati: dati, metadata: metadata)
}
