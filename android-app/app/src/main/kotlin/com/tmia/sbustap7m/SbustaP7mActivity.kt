package com.tmia.sbustap7m

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.View
import android.widget.Button
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import com.tmia.sbustap7m.cms.Firmatario
import com.tmia.sbustap7m.cms.P7mContentError
import com.tmia.sbustap7m.cms.P7mFormatError
import com.tmia.sbustap7m.cms.RisultatoEstrazione
import com.tmia.sbustap7m.cms.estrai
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * Entry point reachable two ways: (1) ACTION_VIEW on
 * application/pkcs7-mime and application/x-pkcs7-mime, e.g. tapping a
 * .p7m attachment in a mail app (see AndroidManifest.xml); (2) direct
 * launch from the app drawer (MAIN/LAUNCHER), which shows an initial
 * "pick a file" state instead of an error. Mirrors the desktop
 * wrappers' summary step: shows signer metadata, then lets the user
 * open or save the extracted PDF and export the metadata as JSON,
 * each through an explicit destination picker (Storage Access
 * Framework) — no automatic file-next-to-source save, Android's
 * sandboxed storage model doesn't support that the way a desktop
 * filesystem does (see plan decisions).
 */
class SbustaP7mActivity : AppCompatActivity() {

    private var risultatoCorrente: RisultatoEstrazione? = null
    private var nomeBaseCorrente: String = "documento"
    private var pdfFileCorrente: File? = null

    private lateinit var testoStato: TextView
    private lateinit var testoFirmatari: TextView
    private lateinit var pulsanteApriFile: Button
    private lateinit var pulsanteApriPdf: Button
    private lateinit var pulsanteSalvaPdf: Button
    private lateinit var pulsanteEsportaJson: Button

    private val apriFileLauncher =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) {
                pulsanteApriFile.visibility = View.GONE
                elaboraUri(uri)
            }
        }

    private val salvaPdfLauncher =
        registerForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
            if (uri != null) {
                salvaPdfSuUri(uri)
            }
        }

    private val esportaJsonLauncher =
        registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
            if (uri != null) {
                scriviJsonSuUri(uri)
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_sbusta_p7m)

        // targetSdk 35+ enforces edge-to-edge by default: content draws
        // behind the status bar unless it accounts for the inset
        // itself. A fixed dp margin would be wrong on any device whose
        // status bar/cutout differs from the one it was tuned on — this
        // reads the real inset at runtime instead, on top of the
        // existing 16dp layout padding.
        val layoutRadice = findViewById<View>(R.id.layout_radice)
        val paddingBase = layoutRadice.paddingTop
        ViewCompat.setOnApplyWindowInsetsListener(layoutRadice) { view, insets ->
            val barreSistema = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(top = paddingBase + barreSistema.top)
            insets
        }

        testoStato = findViewById(R.id.testo_stato)
        testoFirmatari = findViewById(R.id.testo_firmatari)
        pulsanteApriFile = findViewById(R.id.pulsante_apri_file)
        pulsanteApriPdf = findViewById(R.id.pulsante_apri_pdf)
        pulsanteSalvaPdf = findViewById(R.id.pulsante_salva_pdf)
        pulsanteEsportaJson = findViewById(R.id.pulsante_esporta_json)
        val pulsanteAiuto = findViewById<Button>(R.id.pulsante_aiuto)

        pulsanteApriPdf.isEnabled = false
        pulsanteSalvaPdf.isEnabled = false
        pulsanteEsportaJson.isEnabled = false
        pulsanteApriPdf.setOnClickListener { apriPdf() }
        pulsanteSalvaPdf.setOnClickListener { salvaPdfLauncher.launch("$nomeBaseCorrente.pdf") }
        pulsanteEsportaJson.setOnClickListener {
            esportaJsonLauncher.launch("$nomeBaseCorrente.json")
        }
        pulsanteAiuto.setOnClickListener { mostraAiuto() }
        pulsanteApriFile.setOnClickListener {
            // "*/*" rather than the two declared MIME types: mail apps
            // are not consistent about the MIME type they report for a
            // .p7m attachment (sometimes a generic
            // application/octet-stream) — the same risk already
            // flagged for the intent-filter, sidestepped here by
            // filtering on nothing and letting estrai() itself reject
            // whatever isn't a valid CMS envelope.
            apriFileLauncher.launch(arrayOf("*/*"))
        }

        val uri: Uri? = intent?.data
        if (uri == null) {
            testoStato.text = getString(R.string.testo_stato_iniziale)
            return
        }
        pulsanteApriFile.visibility = View.GONE
        elaboraUri(uri)
    }

    private fun elaboraUri(uri: Uri) {
        nomeBaseCorrente = nomeSenzaEstensione(nomeFileDaUri(uri) ?: "documento")

        val bytes = try {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            null
        }

        if (bytes == null) {
            testoStato.text = getString(R.string.titolo_errore)
            return
        }

        val risultato = try {
            estrai(nomeBaseCorrente, bytes)
        } catch (e: P7mFormatError) {
            testoStato.text = "${getString(R.string.titolo_errore)}: ${e.message}"
            return
        } catch (e: P7mContentError) {
            testoStato.text = "${getString(R.string.titolo_errore)}: ${e.message}"
            return
        } catch (e: Exception) {
            testoStato.text = "${getString(R.string.titolo_errore)}: ${e.message}"
            return
        }

        risultatoCorrente = risultato
        testoStato.text = "${risultato.firmatari.size} firmatario/i trovato/i."
        testoFirmatari.text = formattaFirmatari(risultato.firmatari)
        pulsanteEsportaJson.isEnabled = true
        pulsanteSalvaPdf.isEnabled = true

        pdfFileCorrente = try {
            scriviPdfInCache(risultato.pdfBytes)
        } catch (e: Exception) {
            null
        }
        pulsanteApriPdf.isEnabled = pdfFileCorrente != null
    }

    private fun mostraAiuto() {
        AlertDialog.Builder(this)
            .setTitle(R.string.titolo_aiuto)
            .setMessage(R.string.testo_aiuto)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun salvaPdfSuUri(uri: Uri) {
        val risultato = risultatoCorrente ?: return
        contentResolver.openOutputStream(uri)?.use { stream ->
            stream.write(risultato.pdfBytes)
        }
    }

    private fun apriPdf() {
        val file = pdfFileCorrente ?: return
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/pdf")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }

    private fun scriviPdfInCache(pdfBytes: ByteArray): File {
        val cartella = File(cacheDir, "estratti")
        cartella.mkdirs()
        val file = File(cartella, "$nomeBaseCorrente.pdf")
        FileOutputStream(file).use { it.write(pdfBytes) }
        return file
    }

    private fun scriviJsonSuUri(uri: Uri) {
        val risultato = risultatoCorrente ?: return
        val json = firmatariAJson(nomeBaseCorrente, risultato).toString(2)
        contentResolver.openOutputStream(uri)?.use { stream ->
            stream.write(json.toByteArray(Charsets.UTF_8))
        }
    }

    /**
     * Reads the display name of a content:// Uri via the standard
     * OpenableColumns query, same as any file picker/attachment
     * source is expected to support.
     */
    private fun nomeFileDaUri(uri: Uri): String? {
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, null, null, null, null)
            val indice = cursor?.getColumnIndex(OpenableColumns.DISPLAY_NAME) ?: -1
            if (cursor != null && indice >= 0 && cursor.moveToFirst()) {
                return cursor.getString(indice)
            }
        } finally {
            cursor?.close()
        }
        return uri.lastPathSegment
    }

    private fun nomeSenzaEstensione(nomeFile: String): String {
        var nome = nomeFile
        while (nome.lowercase().endsWith(".p7m")) {
            nome = nome.substring(0, nome.length - 4)
        }
        if (nome.lowercase().endsWith(".pdf")) {
            nome = nome.substring(0, nome.length - 4)
        }
        return nome.ifBlank { "documento" }
    }

    private fun formattaFirmatari(firmatari: List<Firmatario>): String =
        firmatari.joinToString(separator = "\n\n") { f ->
            "Livello: ${f.livello}\n" +
                "CN: ${f.cn ?: "-"}\n" +
                "Organizzazione: ${f.organizzazione ?: "-"}\n" +
                "Numero seriale: ${f.numeroSeriale ?: "-"}\n" +
                "Validità: ${f.validitaInizio ?: "-"} — ${f.validitaFine ?: "-"}\n" +
                "Algoritmo: ${f.algoritmoFirma ?: "-"}\n" +
                "Data firma: ${f.signingTime ?: "-"}"
        }

    /** Same JSON schema as sbusta_p7m/core.py's estrai(): "firmatari"
     * array with the same field names, "file_originale"/"pdf_estratto"
     * kept parallel to the Python side even though this JSON export is
     * an optional user action here, not the primary output. */
    private fun firmatariAJson(nomeBase: String, risultato: RisultatoEstrazione): JSONObject {
        // JSONObject.NULL used explicitly for every possibly-missing
        // field: passing Kotlin `null` straight to put() is ambiguous
        // across org.json implementations (reference vs Android's own
        // fork), JSONObject.NULL is the one unambiguous, documented
        // way to get a real "null" in the output, matching the "null,
        // never omitted" schema from the Python side.
        val array = JSONArray()
        for (f in risultato.firmatari) {
            val obj = JSONObject()
            obj.put("cn", f.cn ?: JSONObject.NULL)
            obj.put("organizzazione", f.organizzazione ?: JSONObject.NULL)
            obj.put("numero_seriale", f.numeroSeriale ?: JSONObject.NULL)
            obj.put("validita_inizio", f.validitaInizio ?: JSONObject.NULL)
            obj.put("validita_fine", f.validitaFine ?: JSONObject.NULL)
            obj.put("algoritmo_firma", f.algoritmoFirma ?: JSONObject.NULL)
            obj.put("signing_time", f.signingTime ?: JSONObject.NULL)
            obj.put("livello", f.livello)
            array.put(obj)
        }
        val root = JSONObject()
        root.put("file_originale", "$nomeBase.p7m")
        root.put("pdf_estratto", "$nomeBase.pdf")
        root.put("firmatari", array)
        return root
    }
}
