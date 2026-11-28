package com.ureader.prototype.speech

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.Random

/** Silent export of explicitly supplied private text; never opens the product database. */
class FrenchQualityCaptureTest {
    @Test(timeout = 360000) fun captureNativeSegments() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val name = InstrumentationRegistry.getArguments().getString("corpusDir")!!
        require(Regex("french-quality-[a-z0-9-]{1,60}").matches(name))
        val root = File(context.filesDir.canonicalFile, name)
        require(root.canonicalFile == root.absoluteFile && root.isDirectory)
        val input = File(root, "cases.json")
        require(input.canonicalFile.parentFile == root && input.length() in 1..1048576)
        val cases = JSONObject(input.readText()).getJSONArray("cases")
        require(cases.length() in 1..32)
        val manifest = context.assets.open("flutter_assets/assets/models/manifest.json").use {
            JSONObject(String(it.readBytes(), Charsets.UTF_8))
        }
        val pins = HashMap<String, Pair<Long, String>>()
        val entries = manifest.getJSONArray("files")
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            pins[entry.getString("relativePath")] = entry.getLong("byteSize") to entry.getString("sha256")
        }
        val models = File(context.filesDir.canonicalFile,
            "ureader-prototype/models/${manifest.getString("bundleId")}/${manifest.getString("bundleVersion")}")
        val output = File(root, "native")
        check(output.mkdir())
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)
        val synth = OnnxFrenchSynthesizer(models, pins,
            manifest.getJSONObject("runtimeCompatibility").getInt("expectedVoiceOffset"), output,
            alignmentOutputName = manifest.getJSONObject("wordAlignment").getString("outputName"),
            reuseResources = true, tuning = OnnxFrenchSynthesizer.RuntimeTuning(threads, allowSpinning = false))
        val results = JSONArray()
        try {
            for (i in 0 until cases.length()) {
                val entry = cases.getJSONObject(i)
                val id = entry.getString("id")
                require(Regex("[a-z-]+-[0-9]{1,2}").matches(id))
                val text = entry.getString("synthesisText")
                require(text.length in 1..4096 && entry.getInt("tokens") in 1..50)
                val seed = entry.optInt("seed", 71 + i)
                require(seed in 0..10000)
                val random = Random(seed.toLong())
                val noise = FloatArray(250 * 32) { random.nextGaussian().toFloat() * kotlin.math.sqrt(0.3f) }
                val audio = synth.synthesize(text, {}, noise)
                val target = File(output, "$id.wav")
                check(!target.exists() && audio.file.renameTo(target))
                results.put(JSONObject(audio.timings).put("id", id).put("wav", target.name)
                    .put("samples", audio.samples).put("frames", audio.frames)
                    .put("sha256", sha(target)).put("seed", seed))
            }
        } finally { synth.close() }
        val report = File(root, "native-report.json")
        check(report.createNewFile())
        report.writeText(JSONObject().put("status", "captured_listening_pending")
            .put("inputSha256", sha(input)).put("cases", results)
            .put("threads", threads).put("allowSpinning", false)
            .put("audioPlaybackRequested", false).put("userPositionsWritten", false)
            .put("g1", "not_evaluated").toString(2))
    }

    private fun sha(file: File): String = MessageDigest.getInstance("SHA-256")
        .digest(file.readBytes()).joinToString("") { "%02x".format(it) }
}
