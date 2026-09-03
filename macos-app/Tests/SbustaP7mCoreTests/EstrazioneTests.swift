import XCTest
@testable import SbustaP7mCore

/// Mirrors EstrazioneTest.kt (Android): pure library tests, no UI
/// involved. Fixtures under Resources/ are shared 1:1 with the Android
/// test suite (test-busta.p7m, test-busta-cofirmatari.p7m — same bytes,
/// copied verbatim) plus two fixtures added for this plan's extra
/// coverage (test-busta-annidata.p7m, test-busta-detached.p7m). Expected
/// values below were captured by running sbusta_p7m.core.estrai() on
/// these exact files (Python, ground truth) before writing this suite —
/// see project-docs/status/macos-swift.md.
final class EstrazioneTests: XCTestCase {

    private func percorsoFixture(_ nome: String) throws -> String {
        guard let url = Bundle.module.url(forResource: nome, withExtension: "p7m", subdirectory: "Resources") else {
            XCTFail("fixture mancante: \(nome).p7m")
            throw P7mError.formatoNonValido("fixture mancante: \(nome)")
        }
        return url.path
    }

    private func scriviFileTemporaneo(_ dati: Data) throws -> String {
        let percorso = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".p7m")
        try dati.write(to: percorso)
        return percorso.path
    }

    func testEstraePDFEMetadatiDaBustaValida() throws {
        let risultato = try estrai(percorsoP7m: percorsoFixture("test-busta"))

        XCTAssertTrue(risultato.dati.starts(with: Data("%PDF-".utf8)))
        XCTAssertEqual(risultato.metadata.firmatari.count, 1)

        let firmatario = risultato.metadata.firmatari[0]
        XCTAssertEqual(firmatario.cn, "Test Android Signer")
        XCTAssertEqual(firmatario.organizzazione, "sbusta-p7m tests")
        XCTAssertEqual(firmatario.numeroSeriale, "587330377902252870737647299842145253133970882159")
        XCTAssertEqual(firmatario.validitaInizio, "2026-08-26T03:01:44+00:00")
        XCTAssertEqual(firmatario.validitaFine, "2026-08-27T03:01:44+00:00")
        XCTAssertEqual(firmatario.signingTime, "2026-08-26T03:01:44+00:00")
        XCTAssertEqual(firmatario.livello, 0)
        XCTAssertNotNil(firmatario.algoritmoFirma, "l'algoritmo di firma deve essere presente")
    }

    func testEstraeNumeroArbitrarioDiCofirmatari() throws {
        // The fixture has 4, but the point of this test is that the code
        // assumes no fixed count (unlike maxLivelli for nesting depth) —
        // same intent as the Kotlin/Python tests this mirrors.
        let risultato = try estrai(percorsoP7m: percorsoFixture("test-busta-cofirmatari"))

        let cnAttesi: Set<String> = Set((1...4).map { "Test Android Cofirmatario \($0)" })
        let serialiAttesi: Set<String> = [
            "282942620207639414579752207253337668287767624980",
            "382071701124324200744283641339170222156859790808",
            "81788238112956493659841891442445199735954828162",
            "294943592730174452004018562475932938748389920366",
        ]

        XCTAssertEqual(risultato.metadata.firmatari.count, 4)
        XCTAssertEqual(Set(risultato.metadata.firmatari.map { $0.cn ?? "" }), cnAttesi)
        XCTAssertEqual(Set(risultato.metadata.firmatari.map { $0.numeroSeriale ?? "" }), serialiAttesi)
        for firmatario in risultato.metadata.firmatari {
            XCTAssertEqual(firmatario.livello, 0)
        }
    }

    func testBustaAnnidataHaDueLivelli() throws {
        let risultato = try estrai(percorsoP7m: percorsoFixture("test-busta-annidata"))

        XCTAssertTrue(risultato.dati.starts(with: Data("%PDF-".utf8)))
        XCTAssertEqual(risultato.metadata.firmatari.map { $0.livello }, [0, 1])
        for firmatario in risultato.metadata.firmatari {
            XCTAssertEqual(firmatario.cn, "Test macOS Signer")
            XCTAssertEqual(firmatario.numeroSeriale, "29929503141880378768889537540063488470944625710")
        }
    }

    func testFirmaDetachedSollevaContenutoNonRecuperabile() throws {
        XCTAssertThrowsError(try estrai(percorsoP7m: percorsoFixture("test-busta-detached"))) { error in
            guard case P7mError.contenutoNonRecuperabile = error else {
                XCTFail("atteso .contenutoNonRecuperabile, trovato \(error)")
                return
            }
        }
    }

    func testFileNonCMSSollevaFormatoNonValido() throws {
        let percorso = try scriviFileTemporaneo(Data("questo non è affatto una busta CMS".utf8))
        defer { try? FileManager.default.removeItem(atPath: percorso) }

        XCTAssertThrowsError(try estrai(percorsoP7m: percorso)) { error in
            guard case P7mError.formatoNonValido = error else {
                XCTFail("atteso .formatoNonValido, trovato \(error)")
                return
            }
        }
    }

    func testFileTroncatoSollevaFormatoNonValido() throws {
        let bytesValidi = try Data(contentsOf: URL(fileURLWithPath: percorsoFixture("test-busta")))
        let percorso = try scriviFileTemporaneo(bytesValidi.prefix(50))
        defer { try? FileManager.default.removeItem(atPath: percorso) }

        XCTAssertThrowsError(try estrai(percorsoP7m: percorso)) { error in
            guard case P7mError.formatoNonValido = error else {
                XCTFail("atteso .formatoNonValido, trovato \(error)")
                return
            }
        }
    }
}
