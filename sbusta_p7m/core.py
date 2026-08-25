"""Core extraction logic for .p7m (CMS/PKCS#7 SignedData) envelopes.

No cryptographic validation is performed here: this module only reads the
structure of the CMS envelope (asn1crypto, pure parsing, no external
binaries). Signature/chain/revocation validation is explicitly out of
scope for this phase.

This module knows nothing about destination paths on disk: it only
returns bytes and a metadata dict. Callers (the CLI, or a future Yazi
integration) decide where to write the output.
"""

import os

from asn1crypto import cms

# Defensive cap on how many nested CMS envelopes are unwrapped
# (file.pdf.p7m.p7m.p7m...). Real-world Italian digital signature
# envelopes are not expected to nest this deep; this only guards
# against a pathological/malicious input, not a known real limit.
MAX_LIVELLI = 10


class P7mError(Exception):
    """Base class for all errors raised by sbusta_p7m.core."""


class P7mFormatError(P7mError):
    """The file is not a well-formed CMS/PKCS#7 SignedData envelope."""


class P7mContentError(P7mError):
    """The envelope parsed correctly but the expected content is missing or unusable."""


def estrai(percorso_p7m):
    """Extract the embedded PDF and signer metadata from a DER-encoded
    .p7m (CMS SignedData) envelope, unwrapping nested envelopes when the
    embedded content is itself another CMS SignedData (a document signed
    more than once, e.g. "file.pdf.p7m.p7m") until the raw PDF emerges.

    Args:
        percorso_p7m: path to the .p7m file (str or os.PathLike).

    Returns:
        tuple[bytes, dict]: (pdf_bytes, metadata_dict). metadata_dict
        always contains every key of the schema below; any field that
        could not be resolved is explicitly None, never omitted:

            {
                "file_originale": str,
                "pdf_estratto": None,
                "firmatari": [
                    {
                        "cn": str | None,
                        "organizzazione": str | None,
                        "numero_seriale": str | None,
                        "validita_inizio": str | None,
                        "validita_fine": str | None,
                        "algoritmo_firma": str | None,
                        "signing_time": str | None,
                    },
                    ...  # one entry per envelope layer crossed,
                         # outermost signature first
                ],
            }

    Raises:
        P7mFormatError: the file is not a valid CMS/PKCS#7 SignedData
            envelope.
        P7mContentError: the envelope is valid CMS but the embedded
            content could not be recovered at all (e.g. detached
            signature on the outermost layer).
        OSError: propagated unchanged if the file cannot be read (not
            found, permission denied, etc.) — not wrapped, the built-in
            error is already clear enough.
    """
    with open(percorso_p7m, "rb") as f:
        data = f.read()

    firmatari = []
    livello = 0

    while True:
        try:
            content_info = cms.ContentInfo.load(data)
        except Exception as e:
            if livello == 0:
                raise P7mFormatError(
                    f"'{percorso_p7m}' is not a valid ASN.1/CMS structure"
                ) from e
            # Not a nested CMS envelope: `data` is the final raw content.
            break

        if content_info["content_type"].native != "signed_data":
            if livello == 0:
                raise P7mFormatError(
                    f"'{percorso_p7m}' is a CMS envelope but not of type "
                    f"signed_data (got '{content_info['content_type'].native}')"
                )
            # Some other CMS content type we don't know how to unwrap
            # further (e.g. enveloped/encrypted data): give up here.
            break

        signed_data = content_info["content"]
        encap_content = signed_data["encap_content_info"]
        inner_bytes = encap_content["content"].native

        if inner_bytes is None:
            if livello == 0:
                raise P7mContentError(
                    f"'{percorso_p7m}' has a detached signature (no embedded "
                    "content), not supported in this phase"
                )
            # A detached envelope was found while unwrapping an inner
            # layer: there is nothing further to extract from it, keep
            # `data` (this envelope's own bytes) as the final content.
            break

        firmatari.append(_metadata_livello(signed_data))
        data = inner_bytes
        livello += 1

        if data.startswith(b"%PDF-") or livello >= MAX_LIVELLI:
            break

    metadata = {
        "file_originale": os.path.basename(percorso_p7m),
        "pdf_estratto": None,
        "firmatari": firmatari,
    }
    return data, metadata


def _metadata_livello(signed_data):
    """Build the metadata entry for one envelope layer: the first
    signer's certificate fields, signature algorithm and signing time.

    Only the first SignerInfo of this layer is handled (a single CMS
    SignedData with several co-signers, as opposed to several nested
    envelopes, is out of scope in this phase)."""
    entry = {
        "cn": None,
        "organizzazione": None,
        "numero_seriale": None,
        "validita_inizio": None,
        "validita_fine": None,
        "algoritmo_firma": None,
        "signing_time": None,
    }

    signer_infos = signed_data["signer_infos"]
    if len(signer_infos) == 0:
        return entry

    signer_info = signer_infos[0]
    entry["algoritmo_firma"] = signer_info["signature_algorithm"]["algorithm"].native

    if signer_info["signed_attrs"].native is not None:
        for attr in signer_info["signed_attrs"]:
            if attr["type"].native == "signing_time":
                entry["signing_time"] = attr["values"][0].native.isoformat()
                break

    cert = _trova_certificato_firmatario(signed_data, signer_info)
    if cert is not None:
        subject = cert.subject.native
        entry["cn"] = subject.get("common_name")
        entry["organizzazione"] = subject.get("organization_name")
        entry["numero_seriale"] = str(cert.serial_number)
        entry["validita_inizio"] = cert.not_valid_before.isoformat()
        entry["validita_fine"] = cert.not_valid_after.isoformat()

    return entry


def _trova_certificato_firmatario(signed_data, signer_info):
    """Resolve the signer's certificate from the envelope's certificate
    set, matching it against signer_info['sid'].

    Returns None if the certificate set is absent, or no certificate
    matches — the caller must treat this as "metadata unavailable", not
    as an error: the PDF can still be extracted without it.
    """
    certificates = signed_data["certificates"]
    if certificates.native is None:
        return None

    sid = signer_info["sid"]
    if sid.name != "issuer_and_serial_number":
        # subject_key_identifier matching is not implemented in this
        # phase: real-world .p7m envelopes from Italian digital
        # signature providers use issuer_and_serial_number, per the
        # test files used to build this module.
        return None

    target_serial = sid.chosen["serial_number"].native
    target_issuer = sid.chosen["issuer"]

    for cert_choice in certificates:
        if cert_choice.name != "certificate":
            continue
        cert = cert_choice.chosen
        if cert.serial_number == target_serial and cert.issuer == target_issuer:
            return cert

    return None
