package com.ureader.prototype.speech

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Only the embedded manifest selects a laboratory bundle; no caller-provided paths. */
internal class TrustedSpeechBundle(private val context: Context) {
    fun resolve(id: String, version: String, digest: String): PocketSpeechEngine? {
        val bytes = context.assets.open("flutter_assets/assets/models/manifest.json").use { it.readBytes() }
        val actual = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        val manifest = JSONObject(String(bytes, Charsets.UTF_8))
        require(manifest.getJSONObject("activationGate").getBoolean("requiresPositiveG0"))
        if (actual != digest || manifest.getString("bundleId") != id || manifest.getString("bundleVersion") != version ||
            manifest.getJSONObject("activationGate").getString("g0Verdict") != "passed") return null
        require(manifest.getString("language") == "fr" && id == "fr-official-aligned")
        val rawParent = File(context.filesDir.canonicalFile, "ureader-prototype")
        val parent = rawParent.canonicalFile
        require(parent == rawParent.absoluteFile && parent.parentFile == context.filesDir.canonicalFile)
        val database = File(parent, "prototype.sqlite")
        if (!database.isFile || database.canonicalFile != database.absoluteFile) return null
        val ready = SQLiteDatabase.openDatabase(database.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            db.rawQuery("SELECT manifest_digest FROM installed_bundles WHERE bundle_id = ? AND version = ? AND status = 'ready'", arrayOf(id, version)).use { rows -> rows.moveToFirst() && rows.getString(0) == digest }
        }
        if (!ready) return null
        val directory = File(parent, "models/$id/$version")
        if (!directory.exists()) return null
        require(directory.canonicalFile == directory.absoluteFile && directory.path.startsWith(parent.path + File.separator))
        val entries = manifest.getJSONArray("files")
        val pins = HashMap<String, Pair<Long, String>>()
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            val name = entry.getString("relativePath")
            require(SpeechWireCommand.validId(name))
            val file = File(directory, name)
            require(file.canonicalFile.parentFile == directory && file.canonicalFile == file.absoluteFile)
            val expected = entry.getLong("byteSize")
            require(file.isFile && file.length() == expected)
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) { val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) }
            }
            val sha = entry.getString("sha256")
            require(hash.digest().joinToString("") { "%02x".format(it) } == sha)
            pins[name] = expected to sha
        }
        val offset = manifest.getJSONObject("runtimeCompatibility").getInt("expectedVoiceOffset")
        val cache = File(parent, "cache")
        val outputs = File(cache, "native")
        for (folder in listOf(cache, outputs)) {
            require(!java.nio.file.Files.isSymbolicLink(folder.toPath()) && folder.canonicalFile == folder.absoluteFile)
            check(folder.isDirectory || folder.mkdir())
        }
        // No engine exists while resolving a new bundle; remove only our abandoned native WAVs.
        for (orphan in outputs.listFiles() ?: emptyArray()) {
            if (Regex("generation-[0-9a-f-]{36}\\.(part|wav)").matches(orphan.name)) {
                require(!java.nio.file.Files.isSymbolicLink(orphan.toPath()) && orphan.canonicalFile.parentFile == outputs && orphan.isFile)
                check(orphan.delete())
            }
        }
        // Optional capability is selected solely by the trusted embedded manifest.
        // No current manifest qualifies G1, so existing bundles take the legacy path.
        val alignment = manifest.optJSONObject("wordAlignment")
        val configured = alignment != null && alignment.optInt("version") == 1 &&
            alignment.optString("alignerVersion") == "attention-l3h9-v1" &&
            Regex("^[!-~]{1,256}$").matches(alignment.optString("outputName")) &&
            alignment.optString("modelSha256") == pins["flow_lm_main_int8.onnx"]?.second
        val validated = configured && alignment!!.optString("g1Verdict") == "passed" &&
            Regex("^[a-f0-9]{64}$").matches(alignment.optString("evidenceSha256"))
        val preview = configured && (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0 &&
            alignment!!.optString("mode") == "development_preview" && alignment.optString("g1Verdict") == "not_evaluated" &&
            Regex("^[a-f0-9]{64}$").matches(alignment.optString("parityEvidenceSha256"))
        val available = validated || preview
        val backend = OnnxFrenchSynthesizer(directory, pins, offset, outputs,
            alignmentOutputName = if (available) alignment!!.getString("outputName") else null, reuseResources = true)
        val tokenizer = FrenchUnigramTokenizer(File(directory, "tokenizer.json").readText())
        return PocketSpeechEngine(backend = { request, check -> backend.synthesize(request.text, check) },
            closeBackend = backend::close, tokenCounter = { text -> tokenizer.encode(text).size }, alignmentAvailable = available, alignmentValidated = validated)
    }
}
