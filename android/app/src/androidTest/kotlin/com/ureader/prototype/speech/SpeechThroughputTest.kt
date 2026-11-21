package com.ureader.prototype.speech

import ai.onnxruntime.OrtSession
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.Random

/** Synthetic text only. No playback and no product database writes. */
class SpeechThroughputTest {
    @Test(timeout = 600000) fun compareHostOwnedConfigurations() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val host = context.assets.open("flutter_assets/assets/models/manifest.json").use {
            JSONObject(String(it.readBytes(), Charsets.UTF_8))
        }
        val pins = HashMap<String, Pair<Long, String>>()
        val files = host.getJSONArray("files")
        for (i in 0 until files.length()) {
            val f = files.getJSONObject(i)
            pins[f.getString("relativePath")] = f.getLong("byteSize") to f.getString("sha256")
        }
        val directory = File(context.filesDir.canonicalFile,
            "ureader-prototype/models/${host.getString("bundleId")}/${host.getString("bundleVersion")}")
        check(directory.isDirectory)
        val output = File(context.cacheDir.canonicalFile, "throughput-${System.nanoTime()}")
        check(output.mkdir())
        val sustained = InstrumentationRegistry.getArguments().getString("sustained") == "true"
        val corpus = listOf(
            "Chaque matin, Léa ouvre la petite porte du jardin.",
            "À Noël, Émilie prépare une crème brûlée.",
            "Le chat regarde les oiseaux. Puis il retourne dans la maison."
        )
        val texts = if (sustained) List(60) { corpus[it % corpus.size] } else corpus
        val baseline = HashMap<Int, ByteArray>()
        val configs = listOf(
            "one-no-opt" to OnnxFrenchSynthesizer.RuntimeTuning(),
            "two-no-opt" to OnnxFrenchSynthesizer.RuntimeTuning(2),
            "two-basic" to OnnxFrenchSynthesizer.RuntimeTuning(2, OrtSession.SessionOptions.OptLevel.BASIC_OPT),
            "two-all" to OnnxFrenchSynthesizer.RuntimeTuning(2, OrtSession.SessionOptions.OptLevel.ALL_OPT)
        )
        val results = JSONArray()
        try {
            for ((name, tuning) in (if (sustained) configs.take(1) else configs)) {
                val row = JSONObject().put("configuration", name)
                val synth = OnnxFrenchSynthesizer(directory, pins,
                    host.getJSONObject("runtimeCompatibility").getInt("expectedVoiceOffset"), output,
                    alignmentOutputName = host.getJSONObject("wordAlignment").getString("outputName"),
                    reuseResources = true, tuning = tuning)
                try {
                    val runs = JSONArray()
                    // Warm-up excluded from throughput; deterministic state replay checked below.
                    val first = synth.synthesize(texts[0], {}, noise(71))
                    val warmup = first.file.readBytes()
                    check(first.file.delete())
                    var totalMs = 0L
                    var audioMs = 0L
                    var exact = true
                    for (i in texts.indices) {
                        val audio = synth.synthesize(texts[i], {}, noise(71 + i % corpus.size))
                        val bytes = audio.file.readBytes()
                        if (i == 0) assertArrayEquals("Utterance state leaked", warmup, bytes)
                        val key = i % corpus.size
                        if (name == "one-no-opt" && !baseline.containsKey(key)) baseline[key] = bytes
                        val same = baseline[key]!!.contentEquals(bytes)
                        if (sustained) assertTrue("Output changed during sustained generation", same)
                        exact = exact && same
                        assertNotNull("Real alignment output required", audio.alignment)
                        totalMs += audio.timings.getValue("totalMs")
                        audioMs += audio.timings.getValue("audioMs")
                        runs.put(JSONObject(audio.timings).put("case", i).put("pcmIdenticalToBaseline", same))
                        check(audio.file.delete())
                    }
                    assertEquals(1, synth.initializationCount)
                    row.put("status", "measured").put("runs", runs)
                        .put("warmRtf", totalMs.toDouble() / audioMs)
                        .put("pcmIdenticalToBaseline", exact)
                } catch (error: Exception) {
                    row.put("status", "rejected").put("reason", error.javaClass.simpleName)
                    if (name == "one-no-opt") throw error
                } finally { synth.close() }
                results.put(row)
            }
            val report = JSONObject().put("status", "measured").put("configurations", results)
                .put("audioPlaybackRequested", false).put("alignmentCapture", true)
                .put("g1", "not_evaluated").put("sustainedReading", if (sustained) "generation_only_no_playback" else "not_evaluated")
            val file = File(context.filesDir, "throughput-report-${System.currentTimeMillis()}.json")
            check(file.createNewFile()); file.writeText(report.toString(2))
        } finally {
            // Retain files on failure for investigation; never recursively remove a computed path.
            if (output.listFiles()?.isEmpty() == true) check(output.delete())
        }
    }

    private fun noise(seed: Int): FloatArray {
        val random = Random(seed.toLong())
        return FloatArray(250 * 32) { random.nextGaussian().toFloat() * kotlin.math.sqrt(0.3f) }
    }
}
