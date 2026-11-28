package com.ureader.prototype.speech

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Only embedded manifests select a trusted bundle; no caller-provided paths. */
internal class TrustedSpeechBundle(private val context: Context) {
    fun resolve(id: String, version: String, digest: String): PocketSpeechEngine? {
        val asset = if (id == "fr-kokoro-siwis") "kokoro-manifest.json" else "manifest.json"
        val bytes = context.assets.open("flutter_assets/assets/models/$asset").use { it.readBytes() }
        val actual = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        val manifest = JSONObject(String(bytes, Charsets.UTF_8))
        val gate = manifest.getJSONObject("activationGate")
        val kokoro = id == "fr-kokoro-siwis"
        val permitted = if (kokoro) {
            (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0 &&
                manifest.optString("engine") == "kokoro" &&
                manifest.optString("deliveryMode") == "local_native_preview" &&
                manifest.getJSONObject("voice").getString("id") == "ff_siwis" &&
                gate.optString("mode") == "development_preview" &&
                gate.optBoolean("requiresNativeProbe") && gate.optString("nativeProbeVerdict") == "passed" &&
                Regex("[a-f0-9]{64}").matches(gate.optString("evidenceSha256"))
        } else gate.optBoolean("requiresPositiveG0") && gate.optString("g0Verdict") == "passed"
        if (actual != digest || manifest.getString("bundleId") != id || manifest.getString("bundleVersion") != version ||
            !permitted) return null
        if (kokoro) {
            val proofBytes = context.assets.open("flutter_assets/assets/models/kokoro-evidence.json").use { it.readBytes() }
            val proofDigest = MessageDigest.getInstance("SHA-256").digest(proofBytes).joinToString("") { "%02x".format(it) }
            require(proofDigest == gate.getString("evidenceSha256"))
            val proof = JSONObject(String(proofBytes, Charsets.UTF_8))
            require(proof.getInt("schemaVersion") == 1 && proof.getString("scope") == "development_native_probe")
            require(proof.getInt("frontendCasesChecked") == 54 && proof.getInt("frontendDifferences") == 0 &&
                proof.getInt("nativeContractTestsPassed") >= 9 && proof.getBoolean("cancellationPassed"))
            val entries = manifest.getJSONArray("files")
            val pinned = (0 until entries.length()).associate { i ->
                val file = entries.getJSONObject(i)
                file.getString("relativePath") to file.getString("sha256")
            }
            require(proof.getString("modelSha256") == pinned["kokoro.onnx"] &&
                proof.getString("frontendArchiveSha256") == pinned["espeak-data.zip"])
            require(proof.getString("espeakSourceRevision") == manifest.getJSONObject("runtimeCompatibility").getString("espeakSourceRevision"))
        }
        require(manifest.getString("language") == "fr" && id in setOf("fr-official-aligned", "fr-kokoro-siwis"))
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
        require(entries.length() in 1..32)
        val pins = HashMap<String, Pair<Long, String>>()
        var totalBytes = 0L
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            val name = entry.getString("relativePath")
            require(SpeechWireCommand.validId(name))
            val file = File(directory, name)
            require(file.canonicalFile.parentFile == directory && file.canonicalFile == file.absoluteFile)
            val expected = entry.getLong("byteSize")
            require(expected > 0)
            totalBytes = Math.addExact(totalBytes, expected)
            require(totalBytes <= (if (kokoro) 512L else 256L) * 1024 * 1024)
            require(file.isFile && file.length() == expected)
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) { val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) }
            }
            val sha = entry.getString("sha256")
            require(hash.digest().joinToString("") { "%02x".format(it) } == sha)
            require(pins.put(name, expected to sha) == null)
        }
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
        if (kokoro) {
            require(pins.keys == setOf("kokoro.onnx", "siwis.f32", "vocab.json", "tokenizer.json", "espeak-data.zip"))
            val dataRoot = KokoroFrontendData.prepare(File(directory, "espeak-data.zip"), cache, pins.getValue("espeak-data.zip").second)
            val tokenizer = FrenchUnigramTokenizer(File(directory, "tokenizer.json").readText())
            val frontend = FrenchPhonemizer(dataRoot)
            try {
                val backend = OnnxKokoroSynthesizer(directory,
                    pins.filterKeys { it in setOf("kokoro.onnx", "siwis.f32", "vocab.json") },
                    outputs, frontend::phonemize, Runtime.getRuntime().availableProcessors().coerceIn(1, 4))
                return PocketSpeechEngine(backend = { request, check -> backend.synthesize(request.text, check) },
                    closeBackend = {
                        try { backend.close() } finally {
                            try { frontend.close() } finally {
                                KokoroFrontendData.release(dataRoot, cache, pins.getValue("espeak-data.zip").second)
                            }
                        }
                    },
                    tokenCounter = { text -> tokenizer.encode(text).size }, voiceId = "ff_siwis")
            } catch (error: Throwable) {
                frontend.close()
                throw error
            }
        }
        val offset = manifest.getJSONObject("runtimeCompatibility").getInt("expectedVoiceOffset")
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
        // Use up to four intra-op workers, selected by the numerical parity bench.
        // Do not oversubscribe devices reporting fewer available processors. The six-case
        // deterministic parity bench retained sample counts with at most 1 PCM LSB
        // of rounding difference. Idle workers must sleep: the three separate
        // session pools otherwise spend CPU spinning between main/flow/decoder runs.
        // Graph optimizations remain disabled.
        val backend = OnnxFrenchSynthesizer(directory, pins, offset, outputs,
            alignmentOutputName = if (available) alignment!!.getString("outputName") else null,
            reuseResources = true, tuning = OnnxFrenchSynthesizer.RuntimeTuning(
                Runtime.getRuntime().availableProcessors().coerceIn(1, 4), allowSpinning = false))
        val tokenizer = FrenchUnigramTokenizer(File(directory, "tokenizer.json").readText())
        return PocketSpeechEngine(backend = { request, check -> backend.synthesize(request.text, check) },
            closeBackend = backend::close, tokenCounter = { text -> tokenizer.encode(text).size }, alignmentAvailable = available, alignmentValidated = validated)
    }
}
