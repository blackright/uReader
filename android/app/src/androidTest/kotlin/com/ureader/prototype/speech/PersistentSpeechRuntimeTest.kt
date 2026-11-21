package com.ureader.prototype.speech

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.Random

/** Silent device profiling. Uses the installed trusted voice, never the user's book. */
class PersistentSpeechRuntimeTest {
    @Test(timeout = 360000) fun warmUtterancesReuseSessionsAndResetTheirState() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manifest = context.assets.open("flutter_assets/assets/models/manifest.json").use {
            JSONObject(String(it.readBytes(), Charsets.UTF_8))
        }
        val pins = HashMap<String, Pair<Long, String>>()
        val files = manifest.getJSONArray("files")
        for (i in 0 until files.length()) {
            val f = files.getJSONObject(i)
            pins[f.getString("relativePath")] = f.getLong("byteSize") to f.getString("sha256")
        }
        val root = context.filesDir.canonicalFile
        val directory = File(root, "ureader-prototype/models/${manifest.getString("bundleId")}/${manifest.getString("bundleVersion")}")
        check(directory.isDirectory) { "Install the trusted voice before the runtime test" }
        val output = File(context.cacheDir.canonicalFile, "persistent-runtime-${System.nanoTime()}")
        check(output.parentFile == context.cacheDir.canonicalFile && output.mkdir())
        val synth = OnnxFrenchSynthesizer(directory, pins,
            manifest.getJSONObject("runtimeCompatibility").getInt("expectedVoiceOffset"), output,
            reuseResources = true)
        val noiseSource = Random(71)
        val noise = FloatArray(250 * 32) { noiseSource.nextGaussian().toFloat() * kotlin.math.sqrt(0.3f) }
        val rows = JSONArray()
        var baseline: ByteArray? = null
        try {
            repeat(3) { index ->
                val audio = synth.synthesize("Chaque matin, Léa ouvre la petite porte du jardin.", {}, noise)
                val bytes = audio.file.readBytes()
                if (baseline == null) baseline = bytes else assertArrayEquals("State leaked across utterances", baseline, bytes)
                assertEquals(1, synth.initializationCount)
                assertEquals(if (index == 0) 0L else 1L, audio.timings["reusedRuntime"])
                rows.put(JSONObject(audio.timings).put("index", index).put("samples", audio.samples)
                    .put("pcmIdentical", true))
                check(audio.file.delete())
            }
        } finally { synth.close() }
        var rejected = false
        try { synth.synthesize("Bonjour.", {}) } catch (expected: IllegalStateException) { rejected = true }
        assertTrue("Closed runtime accepted inference", rejected)
        val report = JSONObject().put("status", "passed").put("runs", rows)
            .put("initializations", synth.initializationCount).put("audioPlaybackRequested", false)
            .put("g1", "not_evaluated").put("api", android.os.Build.VERSION.SDK_INT)
        val reportFile = File(context.filesDir, "persistent-runtime-report-${System.currentTimeMillis()}.json")
        check(reportFile.createNewFile()); reportFile.writeText(report.toString(2))
        check(output.canonicalFile.parentFile == context.cacheDir.canonicalFile)
        check(output.delete())
    }
}
