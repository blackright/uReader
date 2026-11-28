package com.ureader.prototype.speech

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CancellationException

/** Isolated silent prototype. Recorded phonemes test inference; live frontend parity is checked separately. */
class KokoroRuntimeCaptureTest {
    @Test(timeout = 360000) fun captureNativeSegments() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = InstrumentationRegistry.getArguments().getString("corpusDir")!!
        require(Regex("french-quality-[a-z0-9-]{1,60}").matches(name))
        val root = File(context.filesDir.canonicalFile, name)
        require(root.canonicalFile == root.absoluteFile && root.isDirectory)
        val input = File(root, "cases.json")
        require(input.length() in 1..1048576)
        val config = JSONObject(input.readText())
        val cases = config.getJSONArray("cases")
        require(cases.length() in 1..32)
        val pins = config.getJSONArray("files")
        val trusted = (0 until pins.length()).associate { i ->
            val entry = pins.getJSONObject(i)
            entry.getString("relativePath") to (entry.getLong("byteSize") to entry.getString("sha256"))
        }
        val output = File(root, "native")
        check(output.mkdir())
        var frontendChecked = 0
        if (config.has("frontendCases")) {
            val differences = JSONArray()
            FrenchPhonemizer(root).use { frontend ->
                val expected = config.getJSONArray("frontendCases")
                require(expected.length() in 1..128)
                for (i in 0 until expected.length()) {
                    val row = expected.getJSONObject(i)
                    val original = frontend.original(row.getString("synthesisText"))
                    val actual = try { frontend.phonemize(row.getString("synthesisText")) }
                        catch (_: IllegalArgumentException) { null }
                    if (original != row.getString("originalPhonemes") || actual?.corrected != row.getString("phonemes")) {
                        differences.put(JSONObject().put("caseIndex", i).put("id", row.getString("id"))
                            .put("original", original).put("corrected", actual?.corrected ?: JSONObject.NULL))
                    }
                    frontendChecked++
                }
            }
            File(root, "frontend-parity.json").writeText(JSONObject().put("checked", frontendChecked)
                .put("differences", differences).toString(2))
            check(differences.length() == 0) { "French frontend parity differences: ${differences.length()}" }
        }
        var phones = OnnxKokoroSynthesizer.Phones("a")
        val threads = config.getInt("threads")
        val started = android.os.SystemClock.elapsedRealtime()
        val synth = OnnxKokoroSynthesizer(root, trusted, output, { phones }, threads)
        val loadMs = android.os.SystemClock.elapsedRealtime() - started
        val results = JSONArray()
        var cancellationPassed = false
        try {
            try {
                synth.synthesize("test") { throw CancellationException() }
                error("Cancellation ignored")
            } catch (_: CancellationException) {
                check(output.listFiles()!!.isEmpty())
                cancellationPassed = true
            }
            for (i in 0 until cases.length()) {
                val entry = cases.getJSONObject(i)
                val id = entry.getString("id")
                require(Regex("[a-z-]+-[0-9]{1,2}").matches(id))
                phones = OnnxKokoroSynthesizer.Phones(entry.getString("originalPhonemes"), entry.getString("phonemes"))
                val audio = synth.synthesize(entry.getString("synthesisText"), {})
                val target = File(output, "$id.wav")
                check(!target.exists() && audio.file.renameTo(target))
                results.put(JSONObject(audio.timings).put("id", id).put("wav", target.name)
                    .put("samples", audio.samples).put("totalMs", audio.totalMs)
                    .put("sha256", sha(target)))
            }
        } finally { synth.close() }
        File(root, "native-report.json").writeText(JSONObject().put("status", "captured_listening_pending")
            .put("inputSha256", sha(input)).put("cases", results).put("threads", threads)
            .put("loadMs", loadMs).put("cancellationPassed", cancellationPassed)
            .put("frontendCasesChecked", frontendChecked)
            .put("frontend", "recorded_phonemes_inference_probe_only")
            .put("audioPlaybackRequested", false).put("userPositionsWritten", false).toString(2))
    }

    private fun sha(file: File): String = file.inputStream().use {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(65536)
        while (true) { val count = it.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }
}
