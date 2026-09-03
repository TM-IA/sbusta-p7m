import Foundation

/// Minimal, best-effort DER (Distinguished Encoding Rules) TLV reader —
/// NOT a general CMS parser (that job stays with CMSDecoder/Security.framework,
/// see project-docs/status/macos-swift.md). Exists for exactly one field
/// CMSDecoder's public API does not expose: a SignerInfo's own
/// signatureAlgorithm OID (`algoritmo_firma`, verified absent from
/// CMSDecoder.h — grep of the real SDK header found no
/// algorithm-related accessor).
///
/// Never throws: any unexpected shape (this only has to handle the CMS
/// SignedData structure that CMSDecoder has already accepted as valid,
/// so failures here are a bug in this walker, not a hostile input) makes
/// the affected entries come back `nil` — same "unresolved field is null,
/// never omitted" contract as the rest of the schema.
enum DERWalker {
    /// One decoded Tag-Length-Value node: `content` is the *inner* bytes
    /// (header stripped), `endOffset` is where the next sibling TLV
    /// starts.
    private struct TLV {
        let tag: UInt8
        let content: Data
        let endOffset: Int
    }

    /// Reads one TLV starting at `offset` into `data`. Only definite-length
    /// DER is handled (indefinite length, the 0x80 length-byte marker, is
    /// never used in DER — CMSDecoder already validated this data as DER
    /// before this walker ever runs, so this isn't a gap in practice).
    private static func leggiTLV(_ data: Data, offset: Int) -> TLV? {
        let base = data.startIndex
        guard offset >= 0, offset < data.count else { return nil }
        let tag = data[base + offset]
        var pos = offset + 1
        guard pos < data.count else { return nil }

        let firstLenByte = data[base + pos]
        pos += 1
        var lunghezza: Int
        if firstLenByte & 0x80 == 0 {
            lunghezza = Int(firstLenByte)
        } else {
            let numByte = Int(firstLenByte & 0x7f)
            guard numByte > 0, numByte <= 4, pos + numByte <= data.count else { return nil }
            lunghezza = 0
            for _ in 0..<numByte {
                lunghezza = (lunghezza << 8) | Int(data[base + pos])
                pos += 1
            }
        }
        guard lunghezza >= 0, pos + lunghezza <= data.count else { return nil }
        let content = data.subdata(in: (base + pos)..<(base + pos + lunghezza))
        return TLV(tag: tag, content: content, endOffset: pos + lunghezza)
    }

    /// Walks every sibling TLV directly inside `data` (not recursing),
    /// in encoding order — used to iterate SET OF / SEQUENCE contents
    /// field by field.
    private static func figliDiretti(_ data: Data) -> [TLV] {
        var risultato: [TLV] = []
        var offset = 0
        while offset < data.count {
            guard let tlv = leggiTLV(data, offset: offset) else { break }
            risultato.append(tlv)
            offset = tlv.endOffset
        }
        return risultato
    }

    private static func decodificaOID(_ bytes: Data) -> String? {
        guard let primo = bytes.first else { return nil }
        var componenti = [Int(primo) / 40, Int(primo) % 40]
        var valore = 0
        for byte in bytes.dropFirst() {
            valore = (valore << 7) | Int(byte & 0x7f)
            if byte & 0x80 == 0 {
                componenti.append(valore)
                valore = 0
            }
        }
        return componenti.map(String.init).joined(separator: ".")
    }

    /// Returns, in encoding order, the signatureAlgorithm OID (dotted
    /// string, e.g. "1.2.840.113549.1.1.1") of every SignerInfo found in
    /// the ContentInfo→SignedData at the start of `datiBusta`. Best
    /// effort: a shape this walker doesn't recognise yields fewer/nil
    /// entries rather than throwing — callers must not treat a short
    /// result as a format error (CMSDecoder already made that call).
    ///
    ///     ContentInfo ::= SEQUENCE { contentType OID, content [0] EXPLICIT SignedData }
    ///     SignedData  ::= SEQUENCE { version, digestAlgorithms SET, encapContentInfo SEQUENCE,
    ///                                certificates [0] IMPLICIT OPTIONAL, crls [1] IMPLICIT OPTIONAL,
    ///                                signerInfos SET OF SignerInfo }
    ///     SignerInfo  ::= SEQUENCE { version, sid, digestAlgorithm SEQUENCE,
    ///                                signedAttrs [0] IMPLICIT OPTIONAL,
    ///                                signatureAlgorithm SEQUENCE, signature OCTET STRING, ... }
    ///
    /// digestAlgorithms and signerInfos are BOTH tag 0x31 (SET OF) — they
    /// are told apart only by their position in the sequence, never by
    /// tag alone, hence the purely sequential walk below rather than a
    /// tag-based search.
    static func algoritmiFirma(daBusta datiBusta: Data) -> [String?] {
        guard let contentInfo = leggiTLV(datiBusta, offset: 0) else { return [] }
        let contentInfoFigli = figliDiretti(contentInfo.content)
        // [0] contentType OID, [1] content [0] EXPLICIT — the EXPLICIT
        // wrapper's own content is one nested TLV, the SignedData SEQUENCE.
        guard contentInfoFigli.count >= 2,
              let signedDataTLV = leggiTLV(contentInfoFigli[1].content, offset: 0) else { return [] }

        var cursore = figliDiretti(signedDataTLV.content).makeIterator()
        _ = cursore.next() // version
        _ = cursore.next() // digestAlgorithms (SET, tag 0x31 — same tag as signerInfos, positional only)
        _ = cursore.next() // encapContentInfo

        guard var prossimo = cursore.next() else { return [] }
        if prossimo.tag == 0xA0 { // certificates [0] IMPLICIT OPTIONAL
            guard let dopo = cursore.next() else { return [] }
            prossimo = dopo
        }
        if prossimo.tag == 0xA1 { // crls [1] IMPLICIT OPTIONAL
            guard let dopo = cursore.next() else { return [] }
            prossimo = dopo
        }
        // `prossimo` is now signerInfos, SET OF SignerInfo.
        let signerInfoTLVs = figliDiretti(prossimo.content)

        return signerInfoTLVs.map { signerInfoTLV in
            var it = figliDiretti(signerInfoTLV.content).makeIterator()
            _ = it.next() // version
            _ = it.next() // sid (SEQUENCE issuerAndSerialNumber, or [0] IMPLICIT subjectKeyIdentifier)
            _ = it.next() // digestAlgorithm

            guard var candidato = it.next() else { return nil }
            if candidato.tag == 0xA0 { // signedAttrs [0] IMPLICIT OPTIONAL
                guard let dopo = it.next() else { return nil }
                candidato = dopo
            }
            // `candidato` is now signatureAlgorithm, SEQUENCE { algorithm OID, ... }.
            guard let algoritmoOidTLV = figliDiretti(candidato.content).first else { return nil }
            return decodificaOID(algoritmoOidTLV.content)
        }
    }
}
