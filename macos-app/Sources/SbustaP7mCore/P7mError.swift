import Foundation

/// Same two-way error distinction as sbusta_p7m.core.py's
/// P7mFormatError/P7mContentError (and the Kotlin port's equivalent
/// classes) — no shared base type is needed on the Swift side beyond
/// `Error` conformance, callers switch on the concrete case.
public enum P7mError: Error, CustomStringConvertible {
    /// The file is not a well-formed CMS/PKCS#7 SignedData envelope.
    case formatoNonValido(String)
    /// The envelope parsed correctly but the expected content is
    /// missing or unusable (e.g. a detached signature on the outermost
    /// layer).
    case contenutoNonRecuperabile(String)

    public var description: String {
        switch self {
        case .formatoNonValido(let messaggio): return messaggio
        case .contenutoNonRecuperabile(let messaggio): return messaggio
        }
    }
}
