package com.tmia.sbustap7m.cms

import org.bouncycastle.asn1.ASN1ObjectIdentifier
import org.bouncycastle.asn1.cms.CMSAttributes
import org.bouncycastle.asn1.cms.Time
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x500.style.BCStyle
import org.bouncycastle.asn1.x500.style.IETFUtils
import org.bouncycastle.cert.X509CertificateHolder
import org.bouncycastle.cms.CMSSignedData
import org.bouncycastle.cms.SignerInformation
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Kotlin port of sbusta_p7m/core.py (Python). Mirrors it field for
 * field: same "firmatari" schema (including the "livello" field, one
 * entry per SignerInfo — several co-signers in one layer contribute
 * several entries), same iterative unwrapping of nested envelopes
 * until the raw PDF emerges. Not a reinterpretation.
 *
 * Uses explicit Java getter calls (.getFoo()) throughout rather than
 * Kotlin's synthetic property syntax: several BouncyCastle getters
 * have acronym names (getSID, getCRLs) whose Kotlin property-name
 * conversion is not obvious, and this code has not been compiled here
 * (no local Android/Kotlin toolchain in this session) — explicit calls
 * remove that whole class of risk.
 */

class P7mFormatError(message: String, cause: Throwable? = null) : Exception(message, cause)
class P7mContentError(message: String) : Exception(message)

data class Firmatario(
    val cn: String?,
    val organizzazione: String?,
    val numeroSeriale: String?,
    val validitaInizio: String?,
    val validitaFine: String?,
    val algoritmoFirma: String?,
    val signingTime: String?,
    val livello: Int,
)

data class RisultatoEstrazione(
    val pdfBytes: ByteArray,
    val firmatari: List<Firmatario>,
)

// Same defensive cap as core.py's MAX_LIVELLI: guards against
// pathological nesting, not a known real limit.
private const val MAX_LIVELLI = 10

private fun isoFormat(): SimpleDateFormat =
    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

/**
 * Extracts the embedded PDF and signer metadata from a DER-encoded
 * .p7m (CMS SignedData) envelope, unwrapping nested envelopes when the
 * embedded content is itself another CMS SignedData, until the raw
 * PDF emerges — same logic as sbusta_p7m.core.estrai().
 *
 * @param nomeFile used only for error messages (matches the Python
 *   side's error text, which names the file).
 */
fun estrai(nomeFile: String, bytesOriginali: ByteArray): RisultatoEstrazione {
    var dati = bytesOriginali
    val firmatari = mutableListOf<Firmatario>()
    var livello = 0

    while (true) {
        val bustaFirmata: CMSSignedData = try {
            CMSSignedData(dati)
        } catch (e: Exception) {
            if (livello == 0) {
                throw P7mFormatError("'$nomeFile' is not a valid ASN.1/CMS structure", e)
            }
            // Not a nested CMS envelope: `dati` is the final raw content.
            break
        }

        if (bustaFirmata.isDetachedSignature) {
            if (livello == 0) {
                throw P7mContentError(
                    "'$nomeFile' has a detached signature (no embedded content), not supported in this phase"
                )
            }
            // A detached envelope while unwrapping an inner layer: keep
            // `dati` (this envelope's own bytes) as the final content.
            break
        }

        val contenutoInterno = bustaFirmata.getSignedContent().getContent() as? ByteArray
        if (contenutoInterno == null) {
            if (livello == 0) {
                throw P7mContentError(
                    "'$nomeFile' has no extractable embedded content"
                )
            }
            break
        }

        firmatari.addAll(metadataFirmatariLivello(bustaFirmata, livello))

        dati = contenutoInterno
        livello += 1

        if (isPdf(dati) || livello >= MAX_LIVELLI) {
            break
        }
    }

    return RisultatoEstrazione(pdfBytes = dati, firmatari = firmatari)
}

private fun isPdf(bytes: ByteArray): Boolean {
    val header = "%PDF-".toByteArray(Charsets.US_ASCII)
    if (bytes.size < header.size) return false
    for (i in header.indices) {
        if (bytes[i] != header[i]) return false
    }
    return true
}

/**
 * Builds one metadata entry per SignerInfo of this envelope layer (a
 * single CMS SignedData can carry several co-signers, e.g. a document
 * signed in parallel by more than one party — distinct from several
 * nested envelopes, which is the outer while loop in estrai()). No
 * cap on how many, unlike MAX_LIVELLI for nesting depth: real-world
 * documents with several co-signers on one layer have been observed.
 */
private fun metadataFirmatariLivello(bustaFirmata: CMSSignedData, livello: Int): List<Firmatario> {
    val elencoFirmatari = bustaFirmata.getSignerInfos().getSigners()
    if (elencoFirmatari.isEmpty()) {
        return listOf(Firmatario(null, null, null, null, null, null, null, livello))
    }
    return elencoFirmatari.map { metadataSignerInfo(bustaFirmata, it).copy(livello = livello) }
}

/**
 * Builds the metadata entry for one signer: certificate fields,
 * signature algorithm and signing time. "livello" is a 0 placeholder
 * here, overwritten by the caller's .copy(livello = ...) above — kept
 * out of this function's parameters since nothing else in its body
 * needs it.
 */
private fun metadataSignerInfo(bustaFirmata: CMSSignedData, firmatario: SignerInformation): Firmatario {
    val algoritmoFirma = firmatario.getEncryptionAlgOID()

    var signingTime: String? = null
    val attributiFirmati = firmatario.getSignedAttributes()
    if (attributiFirmati != null) {
        val attributo = attributiFirmati.get(CMSAttributes.signingTime)
        if (attributo != null) {
            val valori = attributo.getAttributeValues()
            if (valori.isNotEmpty()) {
                val data = Time.getInstance(valori[0]).getDate()
                signingTime = isoFormat().format(data)
            }
        }
    }

    val certificato = trovaCertificatoFirmatario(bustaFirmata, firmatario)
        ?: return Firmatario(null, null, null, null, null, algoritmoFirma, signingTime, livello = 0)

    val soggetto: X500Name = certificato.getSubject()

    return Firmatario(
        cn = primoValoreRdn(soggetto, BCStyle.CN),
        organizzazione = primoValoreRdn(soggetto, BCStyle.O),
        numeroSeriale = certificato.getSerialNumber().toString(),
        validitaInizio = isoFormat().format(certificato.getNotBefore()),
        validitaFine = isoFormat().format(certificato.getNotAfter()),
        algoritmoFirma = algoritmoFirma,
        signingTime = signingTime,
        livello = 0,
    )
}

private fun primoValoreRdn(nome: X500Name, tipo: ASN1ObjectIdentifier): String? {
    val rdns = nome.getRDNs(tipo)
    if (rdns.isEmpty()) return null
    return IETFUtils.valueToString(rdns[0].getFirst().getValue())
}

/**
 * Resolves the signer's certificate from the envelope's certificate
 * store, matching it against the SignerInformation's SignerId (which
 * itself implements Selector, matching by issuer+serial — same
 * approach as core.py's _trova_certificato_firmatario).
 *
 * Returns null if the certificate store is empty or no certificate
 * matches — the caller must treat this as "metadata unavailable", not
 * an error: the PDF can still be extracted without it.
 */
@Suppress("UNCHECKED_CAST")
private fun trovaCertificatoFirmatario(
    bustaFirmata: CMSSignedData,
    firmatario: SignerInformation,
): X509CertificateHolder? {
    // SignerId implements the raw (unparameterized) Selector interface
    // on the Java side — Kotlin's stricter generics won't accept it
    // directly where Selector<X509CertificateHolder> is expected
    // (verified via a real compile error, not assumed); an explicit
    // unchecked cast is the standard way to bridge this from Kotlin.
    val selector = firmatario.getSID() as org.bouncycastle.util.Selector<X509CertificateHolder>
    val corrispondenze = bustaFirmata.getCertificates().getMatches(selector)
    return corrispondenze.firstOrNull() as? X509CertificateHolder
}
