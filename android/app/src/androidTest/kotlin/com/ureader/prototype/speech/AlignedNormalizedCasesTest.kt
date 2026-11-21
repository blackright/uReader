package com.ureader.prototype.speech

import android.os.Debug
import android.provider.Settings
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Private, explicitly provisioned G0 candidate. Never enables the application resolver. */
class AlignedNormalizedCasesTest {
    private fun directory() = File(
        InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "ureader-aligned-generation")

    private fun synthesizer(fromEmbeddedManifest: Boolean = false): OnnxFrenchSynthesizer {
        val audit = JSONObject(File(directory(), "audit-lock.json").readText())
        assertEquals(168, audit.getInt("expectedVoiceOffset"))
        val entries = if (fromEmbeddedManifest) {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val manifest = JSONObject(context.assets.open("flutter_assets/assets/models/manifest.json").bufferedReader().use { it.readText() })
            assertEquals("fr-official-aligned", manifest.getString("bundleId"))
            assertEquals(168, manifest.getJSONObject("runtimeCompatibility").getInt("expectedVoiceOffset"))
            assertEquals("not_demonstrated", manifest.getJSONObject("activationGate").getString("g0Verdict"))
            manifest.getJSONArray("files")
        } else audit.getJSONArray("files")
        val pins = HashMap<String, Pair<Long, String>>()
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            pins[entry.getString(if (fromEmbeddedManifest) "relativePath" else "name")] = entry.getLong("byteSize") to entry.getString("sha256")
        }
        try { OnnxFrenchSynthesizer(directory(), pins, 0); fail("Invalid host offset accepted") }
        catch (expected: IllegalArgumentException) { }
        return OnnxFrenchSynthesizer(directory(), pins, 168)
    }

    private fun radios(): JSONObject {
        val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
        val airplane = Settings.Global.getInt(resolver, "airplane_mode_on", -1)
        val wifi = Settings.Global.getInt(resolver, "wifi_on", -1)
        val policy = Settings.Global.getString(resolver, "airplane_mode_radios") ?: ""
        assertEquals("Airplane mode required", 1, airplane)
        assertEquals("Wi-Fi must be disabled", 0, wifi)
        assertTrue("Airplane policy must disable cellular radio", policy.split(',').contains("cell"))
        return JSONObject().put("airplane_mode_on", airplane).put("wifi_on", wifi)
            .put("airplaneModeRadios", policy)
    }

    @Test(timeout = 240000) fun normalizedAlignedCasesGenerateOffline() =
        generateCases("aligned-cases.json", 3, "aligned")

    @Test(timeout = 180000) fun exactProtocolExtractsGenerateOfflineWithEmbeddedPins() =
        generateCases("aligned-protocol-cases.json", 2, "protocol")

    private fun generateCases(fixtureName: String, caseCount: Int, prefix: String) {
        val before = radios()
        val fixture = JSONObject(File(directory(), fixtureName).readText())
        if (prefix == "protocol") {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val bytes = context.assets.open("flutter_assets/assets/models/manifest.json").use { it.readBytes() }
            val digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            assertEquals(fixture.getString("manifestSha256"), digest)
        }
        assertEquals("fr-numbers-v2", fixture.getString("normalizerVersion"))
        val values = fixture.getJSONArray("noise")
        val noise = FloatArray(values.length()) { values.getDouble(it).toFloat() }
        val backend = synthesizer(prefix == "protocol")
        val engine = PocketSpeechEngine({ request, check -> backend.synthesize(request.text, check, noise) })
        val baseline = Debug.getPss().toLong()
        val peak = AtomicLong(baseline)
        val count = AtomicLong()
        val monitor = Executors.newSingleThreadScheduledExecutor()
        monitor.scheduleAtFixedRate({ peak.updateAndGet { maxOf(it, Debug.getPss().toLong()) }; count.incrementAndGet() },
            0, 50, TimeUnit.MILLISECONDS)
        val cases = fixture.getJSONArray("cases")
        val results = JSONArray()
        val stamp = System.currentTimeMillis()
        try {
            assertEquals(caseCount, cases.length())
            val tokenizer = FrenchUnigramTokenizer(File(directory(), "tokenizer.json").readText())
            for (i in 0 until cases.length()) {
                val case = cases.getJSONObject(i)
                val text = case.getString("text")
                val tokens = case.getJSONArray("tokenIds")
                assertArrayEquals(IntArray(tokens.length()) { tokens.getInt(it) }, tokenizer.encode(text))
                val result = engine.synthesize(PocketSpeechEngine.Request("aligned-$i",
                    PocketSpeechEngine.Token("aligned", i.toLong()), text)).get(150, TimeUnit.SECONDS)
                assertTrue("Aligned case $i did not complete", result is PocketSpeechEngine.Outcome.Completed)
                val completed = result as PocketSpeechEngine.Outcome.Completed
                val audio = completed.audio
                assertEquals(24000, audio.sampleRate)
                assertTrue(audio.samples in 1..480000 && audio.eosAt >= 6)
                assertEquals(44L + audio.samples * 2L, audio.file.length())
                val wav = File(directory(), "$prefix-${case.getString("id")}-$stamp.wav")
                audio.file.copyTo(wav, overwrite = false)
                results.put(JSONObject().put("caseId", case.getString("id")).put("wav", wav.name)
                    .put("tokens", tokens.length()).put("samples", audio.samples)
                    .put("durationSeconds", audio.samples / 24000.0).put("totalMs", audio.totalMs)
                    .put("frames", audio.frames).put("eosAtFrame", audio.eosAt)
                    .put("intelligibility", "not_evaluated"))
                engine.release(completed.audioHandle)
                assertFalse(audio.file.exists())
            }
            engine.dispose().get(10, TimeUnit.SECONDS)
            val report = JSONObject().put("status", "mechanical_checks_passed").put("cases", results)
                .put("radiosBefore", before).put("radiosAfter", radios())
                .put("baselinePssKiB", baseline).put("sampledPeakPssKiB", peak.get())
                .put("afterDisposePssKiB", Debug.getPss()).put("memorySamples", count.get())
                .put("requestedSamplingIntervalMs", 50).put("normalizerVersion", "fr-numbers-v2")
                .put("expectedVoiceOffset", 168).put("androidApi", android.os.Build.VERSION.SDK_INT)
                .put("applicationResolverUnchanged", true).put("fixtureFile", fixtureName).put("g0", "not_demonstrated")
            val output = File(directory(), "$prefix-cases-report-$stamp.json")
            check(output.createNewFile()); output.writeText(report.toString(2))
        } finally {
            monitor.shutdownNow(); monitor.awaitTermination(5, TimeUnit.SECONDS)
            engine.dispose().get(10, TimeUnit.SECONDS)
        }
    }

    @Test(timeout = 180000) fun alignedCancellationLeavesNoLateWav() {
        val before = radios()
        val backend = synthesizer()
        val entered = CountDownLatch(1)
        val engine = PocketSpeechEngine({ request, check ->
            backend.synthesize(request.text, check, beforeInference = { entered.countDown() })
        })
        val existing = directory().listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet()
        try {
            val case = JSONObject(File(directory(), "aligned-cases.json").readText()).getJSONArray("cases").getJSONObject(0)
            val token = PocketSpeechEngine.Token("aligned-cancel", 1)
            val result = engine.synthesize(PocketSpeechEngine.Request("aligned-cancel", token, case.getString("text")))
            assertTrue(entered.await(30, TimeUnit.SECONDS))
            val start = android.os.SystemClock.elapsedRealtime()
            engine.cancel(token); engine.cancel(token)
            assertTrue(result.get(10, TimeUnit.SECONDS) is PocketSpeechEngine.Outcome.Cancelled)
            val elapsed = android.os.SystemClock.elapsedRealtime() - start
            val dispose = engine.dispose(); assertSame(dispose, engine.dispose()); dispose.get(10, TimeUnit.SECONDS)
            assertEquals(existing, directory().listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet())
            assertTrue(directory().listFiles()!!.none { it.extension == "part" })
            val report = JSONObject().put("status", "passed").put("cancelToWorkerExitMs", elapsed)
                .put("cancelRepeated", true).put("disposeIdempotent", true).put("lateWavPublished", false)
                .put("radiosBefore", before).put("radiosAfter", radios()).put("g0", "not_demonstrated")
            val output = File(directory(), "aligned-cancellation-report-${System.currentTimeMillis()}.json")
            check(output.createNewFile()); output.writeText(report.toString(2))
        } finally { engine.dispose().get(10, TimeUnit.SECONDS) }
    }
}
