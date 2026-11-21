package com.ureader.prototype.speech

import android.os.Debug
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class ReexportSpeechEngineTest {
    private fun testDirectory(): File {
        val name = InstrumentationRegistry.getArguments().getString("testBundleDirectory") ?: "ureader-reexport-generation"
        require(name in setOf("ureader-reexport-generation", "ureader-precision-probe"))
        return File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, name)
    }
    private fun readPins(directory: File): HashMap<String, Pair<Long, String>> {
        val files = JSONObject(File(directory, "reexport-generation-files.json").readText()).getJSONArray("files")
        val pins = HashMap<String, Pair<Long, String>>()
        for (i in 0 until files.length()) {
            val entry = files.getJSONObject(i)
            pins[entry.getString("name")] = entry.getLong("byteSize") to entry.getString("sha256")
        }
        return pins
    }

    @Test(timeout = 180000) fun reproducedBundleGeneratesCompleteWavWithFrozenTrustMetadata() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = testDirectory()
        val pins = readPins(directory)
        try { OnnxFrenchSynthesizer(directory, pins + ("../outside" to (1L to "a".repeat(64)))); fail("Unsafe pin accepted") }
        catch (expected: IllegalArgumentException) { }
        val synthesizer = OnnxFrenchSynthesizer(directory, pins)
        pins.clear() // The host's mutable map must not change the captured trust snapshot.
        val fixture = JSONObject(File(directory, "generation-fixtures.json").readText())
        val values = fixture.getJSONArray("noise")
        val noise = FloatArray(values.length()) { values.getDouble(it).toFloat() }
        val engine = PocketSpeechEngine({ request, check -> synthesizer.synthesize(request.text, check, noise) })
        val baseline = Debug.getPss().toLong()
        val peak = AtomicLong(baseline)
        val count = AtomicLong()
        val monitor = Executors.newSingleThreadScheduledExecutor()
        monitor.scheduleAtFixedRate({ peak.updateAndGet { maxOf(it, Debug.getPss().toLong()) }; count.incrementAndGet() }, 0, 50, TimeUnit.MILLISECONDS)
        try {
            val request = PocketSpeechEngine.Request("reexport-1", PocketSpeechEngine.Token("reexport", 1), fixture.getString("text"))
            val outcome = engine.synthesize(request).get(150, TimeUnit.SECONDS)
            assertTrue("Reproduced generation did not complete", outcome is PocketSpeechEngine.Outcome.Completed)
            val completed = outcome as PocketSpeechEngine.Outcome.Completed
            val audio = completed.audio
            assertTrue(audio.samples in 1..480000)
            assertEquals(24000, audio.sampleRate)
            assertEquals(44L + audio.samples * 2L, audio.file.length())
            assertTrue(audio.eosAt >= 6)
            val stamp = System.currentTimeMillis()
            val listening = File(directory, "reexport-listening-$stamp.wav")
            assertFalse(listening.exists())
            audio.file.copyTo(listening)
            val report = JSONObject().put("status", "passed").put("sampleRate", audio.sampleRate)
                .put("samples", audio.samples).put("frames", audio.frames).put("eosAtFrame", audio.eosAt)
                .put("durationSeconds", audio.samples / 24000.0).put("totalMs", audio.totalMs)
                .put("baselinePssKiB", baseline).put("sampledPeakPssKiB", peak.get()).put("memorySamples", count.get())
                .put("requestedSamplingIntervalMs", 50).put("wav", listening.name)
                .put("intelligibility", "not_evaluated").put("cancellation", "not_revalidated_for_reproduced_bundle")
                .put("hostTrustSnapshotFrozen", true).put("applicationResolverUnchanged", true)
                .put("androidApi", android.os.Build.VERSION.SDK_INT).put("g0", "not_demonstrated")
            val output = File(directory, "generation-report-$stamp.json")
            check(output.createNewFile()); output.writeText(report.toString(2))
            engine.release(completed.audioHandle)
            assertFalse(audio.file.exists())
        } finally {
            monitor.shutdownNow(); monitor.awaitTermination(5, TimeUnit.SECONDS)
            engine.dispose().get(10, TimeUnit.SECONDS)
        }
    }

    @Test(timeout = 180000) fun reproducedBundleCancellationLeavesNoLateWav() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = testDirectory()
        val synthesizer = OnnxFrenchSynthesizer(directory, readPins(directory))
        val entered = CountDownLatch(1)
        val engine = PocketSpeechEngine({ request, check ->
            synthesizer.synthesize(request.text, check, beforeInference = { entered.countDown() })
        })
        val before = directory.listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet()
        try {
            val text = JSONObject(File(directory, "generation-fixtures.json").readText()).getString("text")
            val request = PocketSpeechEngine.Request("reexport-cancel", PocketSpeechEngine.Token("reexport-cancel", 1), text)
            val output = engine.synthesize(request)
            assertTrue(entered.await(20, TimeUnit.SECONDS))
            val start = android.os.SystemClock.elapsedRealtime()
            engine.cancel(request.token); engine.cancel(request.token)
            assertTrue(output.get(10, TimeUnit.SECONDS) is PocketSpeechEngine.Outcome.Cancelled)
            val elapsed = android.os.SystemClock.elapsedRealtime() - start
            assertEquals(before, directory.listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet())
            assertTrue(directory.listFiles()!!.none { it.extension == "part" })
            val disposal = engine.dispose()
            assertSame(disposal, engine.dispose()); disposal.get(10, TimeUnit.SECONDS)
            val report = JSONObject().put("status", "passed").put("cancelToWorkerExitMs", elapsed)
                .put("cancelRepeated", true).put("disposeIdempotent", true).put("lateWavPublished", false)
                .put("bundle", "official_reexport").put("g0", "not_demonstrated")
            val file = File(directory, "cancellation-report-${System.currentTimeMillis()}.json")
            check(file.createNewFile()); file.writeText(report.toString(2))
        } finally { engine.dispose().get(10, TimeUnit.SECONDS) }
    }
}
