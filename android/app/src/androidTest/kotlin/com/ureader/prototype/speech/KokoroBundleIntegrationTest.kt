package com.ureader.prototype.speech

import android.content.ContextWrapper
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/** The production resolver and live frontend, backed by an isolated installation fixture. */
class KokoroBundleIntegrationTest {
    @Test(timeout = 360000) fun synthesizeThroughTrustedBundle() {
        val real = InstrumentationRegistry.getInstrumentation().targetContext
        val name = InstrumentationRegistry.getArguments().getString("corpusDir")!!
        require(Regex("french-quality-kokoro-installed-[a-z0-9-]{1,45}").matches(name))
        val root = File(real.filesDir.canonicalFile, name)
        require(root.canonicalFile == root.absoluteFile && root.isDirectory)
        val context = object : ContextWrapper(real) { override fun getFilesDir(): File = root }
        val bytes = context.assets.open("flutter_assets/assets/models/kokoro-manifest.json").use { it.readBytes() }
        val digest = sha(bytes)
        val manifest = JSONObject(String(bytes, Charsets.UTF_8))
        val id = manifest.getString("bundleId")
        val version = manifest.getString("bundleVersion")
        val product = File(root, "ureader-prototype").also { check(it.mkdir()) }
        val models = File(product, "models/$id/$version").also { check(it.mkdirs()) }
        val files = manifest.getJSONArray("files")
        for (i in 0 until files.length()) {
            val file = files.getJSONObject(i)
            val filename = file.getString("relativePath")
            require(SpeechWireCommand.validId(filename))
            check(File(root, filename).renameTo(File(models, filename)))
        }
        val database = File(product, "prototype.sqlite")
        SQLiteDatabase.openOrCreateDatabase(database, null).use { db ->
            db.execSQL("CREATE TABLE installed_bundles (bundle_id TEXT, version TEXT, manifest_digest TEXT, status TEXT)")
            db.execSQL("INSERT INTO installed_bundles VALUES (?, ?, ?, 'ready')", arrayOf(id, version, digest))
        }
        val resolver = TrustedSpeechBundle(context)
        assertNull(resolver.resolve(id, version, "0".repeat(64)))
        val started = SystemClock.elapsedRealtime()
        val owner = checkNotNull(resolver.resolve(id, version, digest))
        val loadMs = SystemClock.elapsedRealtime() - started
        assertEquals("ff_siwis", owner.voiceId)
        assertFalse(owner.alignmentAvailable)
        val memorySample = android.os.Debug.getPss()
        val input = File(root, "cases.json")
        val cases = JSONObject(input.readText()).getJSONArray("cases")
        require(cases.length() in 1..32)
        val outputs = File(root, "native").also { check(it.mkdir()) }
        val results = JSONArray()
        try {
            for (i in 0 until cases.length()) {
                val row = cases.getJSONObject(i)
                val caseId = row.getString("id")
                require(Regex("[a-z-]+-[0-9]{1,2}").matches(caseId))
                val request = PocketSpeechEngine.Request(caseId,
                    PocketSpeechEngine.Token("kokoro-installed-probe", (i + 1).toLong()), row.getString("synthesisText"))
                val outcome = owner.synthesize(request).get(90, TimeUnit.SECONDS)
                check(outcome is PocketSpeechEngine.Outcome.Completed)
                val wav = owner.readAudio(outcome.audioHandle).get(10, TimeUnit.SECONDS)
                val target = File(outputs, "$caseId.wav")
                check(target.createNewFile()); target.writeBytes(wav)
                owner.release(outcome.audioHandle)
                results.put(JSONObject(outcome.audio.timings).put("id", caseId).put("wav", target.name)
                    .put("sha256", sha(wav)).put("samples", outcome.audio.samples).put("totalMs", outcome.audio.totalMs))
            }
        } finally { owner.dispose().get(30, TimeUnit.SECONDS) }
        val archiveHash = (0 until files.length()).map { files.getJSONObject(it) }
            .first { it.getString("relativePath") == "espeak-data.zip" }.getString("sha256")
        assertFalse(File(product, "cache/kokoro-frontend-$archiveHash").exists())
        File(root, "native-report.json").writeText(JSONObject().put("status", "captured_listening_pending")
            .put("scope", "isolated_trusted_bundle_integration").put("inputSha256", sha(input.readBytes()))
            .put("cases", results).put("loadMs", loadMs).put("voiceId", owner.voiceId)
            .put("memorySamplePssKiB", memorySample).put("memorySampleIsPeak", false)
            .put("frontend", "live_french_text").put("derivedDataReleased", true)
            .put("productDatabaseOpened", false).put("productVoiceInstalled", false)
            .put("audioPlaybackRequested", false).toString(2))
    }

    private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }
}
