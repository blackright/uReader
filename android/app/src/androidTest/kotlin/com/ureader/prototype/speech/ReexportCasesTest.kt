package com.ureader.prototype.speech

import android.os.Debug
import android.provider.Settings
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class ReexportCasesTest {
    @Test(timeout = 240000) fun threeOfficialExtractsGenerateWithRadiosDisabled() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        fun radios(): JSONObject {
            val result = JSONObject()
            for (name in listOf("airplane_mode_on", "wifi_on", "mobile_data")) {
                result.put(name, Settings.Global.getInt(context.contentResolver, name, -1))
            }
            assertEquals("Airplane mode required", 1, result.getInt("airplane_mode_on"))
            assertEquals("Wi-Fi must be disabled", 0, result.getInt("wifi_on"))
            // Android may retain the user's mobile-data preference while airplane mode
            // powers the cellular radio off. Verify the radio policy instead of that preference.
            val controlled = Settings.Global.getString(context.contentResolver, "airplane_mode_radios") ?: ""
            assertTrue("Airplane policy must disable cellular radio", controlled.split(',').contains("cell"))
            result.put("airplaneModeRadios", controlled)
            return result
        }
        val before = radios()
        val directory = File(context.filesDir, "ureader-reexport-generation")
        val fixture = JSONObject(File(directory, "g0-cases.json").readText())
        val asset = context.assets.open("flutter_assets/assets/models/manifest.json").use { it.readBytes() }
        val hash = MessageDigest.getInstance("SHA-256").digest(asset).joinToString("") { "%02x".format(it) }
        assertEquals(fixture.getString("manifestSha256"), hash)
        val manifest = JSONObject(String(asset, Charsets.UTF_8))
        assertEquals("local_g0_derivation", manifest.getString("deliveryMode"))
        val files = manifest.getJSONArray("files")
        val pins = HashMap<String, Pair<Long, String>>()
        for (i in 0 until files.length()) {
            val entry = files.getJSONObject(i)
            pins[entry.getString("relativePath")] = entry.getLong("byteSize") to entry.getString("sha256")
        }
        val values = fixture.getJSONArray("noise")
        val noise = FloatArray(values.length()) { values.getDouble(it).toFloat() }
        val synthesizer = OnnxFrenchSynthesizer(directory, pins)
        val engine = PocketSpeechEngine({ request, check -> synthesizer.synthesize(request.text, check, noise) })
        val monitor = Executors.newSingleThreadScheduledExecutor()
        val baselinePssKiB = Debug.getPss().toLong()
        val peak = AtomicLong(baselinePssKiB)
        val samples = AtomicLong()
        monitor.scheduleAtFixedRate({ peak.updateAndGet { maxOf(it, Debug.getPss().toLong()) }; samples.incrementAndGet() },0,50,TimeUnit.MILLISECONDS)
        val results = JSONArray()
        val stamp = System.currentTimeMillis()
        try {
            val cases = fixture.getJSONArray("cases")
            assertEquals(3, cases.length())
            val tokenizer = FrenchUnigramTokenizer(File(directory, "tokenizer.json").readText())
            for (i in 0 until cases.length()) {
                val case = cases.getJSONObject(i)
                val ids = case.getJSONArray("tokenIds")
                val text = case.getString("text")
                assertArrayEquals(IntArray(ids.length()) { ids.getInt(it) }, tokenizer.encode(text))
                val request = PocketSpeechEngine.Request("g0-case-$i", PocketSpeechEngine.Token("g0-cases", i.toLong()), text)
                val result = engine.synthesize(request).get(150, TimeUnit.SECONDS)
                assertTrue("Case $i did not complete", result is PocketSpeechEngine.Outcome.Completed)
                val completed = result as PocketSpeechEngine.Outcome.Completed
                val audio = completed.audio
                assertEquals(24000, audio.sampleRate)
                assertTrue(audio.samples in 1..480000 && audio.eosAt >= 6)
                assertEquals(44L + audio.samples * 2L, audio.file.length())
                val listening = File(directory, "g0-case-$i-$stamp.wav")
                assertFalse(listening.exists()); audio.file.copyTo(listening)
                results.put(JSONObject().put("passageId", case.getString("id"))
                    .put("sourceTextSha256", case.getString("sourceTextSha256"))
                    .put("preparedTextSha256", case.getString("preparedTextSha256"))
                    .put("startOffsetUtf16", 0).put("endOffsetUtf16", case.getInt("endOffsetUtf16"))
                    .put("tokens", ids.length()).put("samples", audio.samples).put("sampleRate", audio.sampleRate)
                    .put("frames", audio.frames).put("eosAtFrame", audio.eosAt).put("totalMs", audio.totalMs)
                    .put("durationSeconds", audio.samples / 24000.0).put("wav", listening.name)
                    .put("intelligibility", "not_evaluated"))
                engine.release(completed.audioHandle)
                assertFalse(audio.file.exists())
            }
            engine.dispose().get(10, TimeUnit.SECONDS)
            val afterDisposePssKiB = Debug.getPss().toLong()
            monitor.shutdownNow(); monitor.awaitTermination(5, TimeUnit.SECONDS)
            val report = JSONObject().put("cases", results).put("radiosBefore", before).put("radiosAfter", radios())
                .put("manifestSha256", hash).put("corpusSha256", fixture.getString("corpusSha256"))
                .put("sampledPeakPssKiB", peak.get()).put("memorySamples", samples.get())
                .put("baselinePssKiB", baselinePssKiB).put("afterDisposePssKiB", afterDisposePssKiB)
                .put("requestedSamplingIntervalMs",50).put("memoryScope","Sampled instrumented process, no product threshold")
                .put("androidApi", android.os.Build.VERSION.SDK_INT).put("g0","not_demonstrated")
            val output = File(directory,"g0-cases-report-$stamp.json")
            check(output.createNewFile()); output.writeText(report.toString(2))
        } finally {
            monitor.shutdownNow(); monitor.awaitTermination(5,TimeUnit.SECONDS)
            engine.dispose().get(10,TimeUnit.SECONDS)
        }
    }
}
