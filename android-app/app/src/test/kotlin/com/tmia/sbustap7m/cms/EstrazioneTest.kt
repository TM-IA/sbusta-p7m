package com.tmia.sbustap7m.cms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure JVM tests, no Android device/emulator involved. The test fixture
 * (test-busta.p7m) is a synthetically signed CMS envelope built with
 * `openssl cms -sign` and a throwaway self-signed certificate — same
 * technique used for the macOS/Linux builds, not a real Italian
 * digital-signature document (none is committed to this public repo).
 */
class EstrazioneTest {

    private fun leggiFixture(nome: String): ByteArray =
        javaClass.classLoader!!.getResourceAsStream(nome)!!.readBytes()

    @Test
    fun `estrae il PDF e i metadati da una busta valida`() {
        val bytes = leggiFixture("test-busta.p7m")
        val risultato = estrai("test-busta.p7m", bytes)

        assertTrue(
            "il contenuto estratto deve iniziare con l'header PDF",
            risultato.pdfBytes.size >= 5 &&
                String(risultato.pdfBytes, 0, 5, Charsets.US_ASCII) == "%PDF-"
        )

        assertEquals(1, risultato.firmatari.size)
        val firmatario = risultato.firmatari[0]
        assertEquals("Test Android Signer", firmatario.cn)
        assertEquals("sbusta-p7m tests", firmatario.organizzazione)
        assertEquals(0, firmatario.livello)
        assertTrue("il numero seriale deve essere presente", !firmatario.numeroSeriale.isNullOrBlank())
        assertTrue("la validità di inizio deve essere presente", !firmatario.validitaInizio.isNullOrBlank())
        assertTrue("la validità di fine deve essere presente", !firmatario.validitaFine.isNullOrBlank())
        assertTrue("l'algoritmo di firma deve essere presente", !firmatario.algoritmoFirma.isNullOrBlank())
    }

    @Test
    fun `estrae un numero arbitrario di co-firmatari dello stesso livello`() {
        // The fixture has 4, but the point of this test is that the
        // code assumes no fixed count (unlike MAX_LIVELLI for nesting,
        // there's no cap here): real documents with more co-signers
        // have been observed.
        val bytes = leggiFixture("test-busta-cofirmatari.p7m")
        val risultato = estrai("test-busta-cofirmatari.p7m", bytes)

        val cnAttesi = (1..4).map { "Test Android Cofirmatario $it" }
        assertEquals(cnAttesi.size, risultato.firmatari.size)
        assertEquals(cnAttesi.toSet(), risultato.firmatari.map { it.cn }.toSet())
        risultato.firmatari.forEach { assertEquals(0, it.livello) }
    }

    @Test
    fun `file non CMS solleva P7mFormatError`() {
        val bytesNonCms = "questo non è affatto una busta CMS".toByteArray(Charsets.UTF_8)

        assertThrows(P7mFormatError::class.java) {
            estrai("non-cms.p7m", bytesNonCms)
        }
    }

    @Test
    fun `file troncato solleva P7mFormatError`() {
        val bytesValidi = leggiFixture("test-busta.p7m")
        val troncato = bytesValidi.copyOfRange(0, 50)

        assertThrows(P7mFormatError::class.java) {
            estrai("troncato.p7m", troncato)
        }
    }
}
