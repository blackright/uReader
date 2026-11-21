package com.ureader.prototype.speech

import android.os.Debug
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class PocketSpeechEngineTest {
    private fun request(generation: Long = 1) = PocketSpeechEngine.Request("r$generation",
        PocketSpeechEngine.Token("session", generation), "Bonjour.")
    private fun temporaryAudio(): NativeAudio {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("worker-test-", ".wav", context.cacheDir)
        file.writeBytes(byteArrayOf(1))
        return NativeAudio(file, 24000, 1, 1, 0, 0, 0)
    }
    private fun rejected(action: () -> Unit) {
        try { action(); fail("Invalid worker command accepted") }
        catch (expected: IllegalStateException) { }
        catch (expected: IllegalArgumentException) { }
    }

    @Test fun cancelledLateOutputIsDeletedAndNextRequestRunsSerially() {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        var produced: NativeAudio? = null
        val engine = PocketSpeechEngine({ _, _ ->
            entered.countDown(); check(finish.await(5, TimeUnit.SECONDS))
            temporaryAudio().also { produced = it }
        })
        try {
            val first = engine.synthesize(request())
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            rejected { engine.synthesize(request(2)) }
            engine.cancel(request().token); engine.cancel(request().token)
            finish.countDown()
            assertTrue(first.get(5, TimeUnit.SECONDS) is PocketSpeechEngine.Outcome.Cancelled)
            assertFalse(produced!!.file.exists())
            rejected { engine.synthesize(request()) }
            val next = engine.synthesize(request(2)).get(5, TimeUnit.SECONDS) as PocketSpeechEngine.Outcome.Completed
            engine.release(next.audioHandle); engine.release(next.audioHandle)
            assertFalse(next.audio.file.exists())
            rejected { engine.synthesize(request()) }
        } finally { finish.countDown(); engine.dispose().get(5, TimeUnit.SECONDS) }
    }

    @Test fun disposeWaitsForInferenceAndIsIdempotent() {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val closed = CountDownLatch(1)
        val engine = PocketSpeechEngine({ _, _ ->
            entered.countDown(); check(finish.await(5, TimeUnit.SECONDS)); temporaryAudio()
        }, { closed.countDown() })
        try {
            val output = engine.synthesize(request())
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val disposal = engine.dispose()
            assertSame(disposal, engine.dispose())
            assertFalse(disposal.isDone)
            assertEquals(1L, closed.count)
            rejected { engine.synthesize(request(2)) }
            finish.countDown()
            assertTrue(output.get(5, TimeUnit.SECONDS) is PocketSpeechEngine.Outcome.Cancelled)
            disposal.get(5, TimeUnit.SECONDS)
            assertEquals(0L, closed.count)
            engine.cancel(request().token)
        } finally { finish.countDown(); engine.dispose().get(5, TimeUnit.SECONDS) }
    }

    @Test fun backendFailureDoesNotPoisonWorker() {
        var calls = 0
        val engine = PocketSpeechEngine({ _, _ ->
            if (++calls == 1) error("Injected failure")
            temporaryAudio()
        })
        try {
            assertTrue(engine.synthesize(request()).get(5, TimeUnit.SECONDS) is PocketSpeechEngine.Outcome.Failed)
            val next = engine.synthesize(request(2)).get(5, TimeUnit.SECONDS) as PocketSpeechEngine.Outcome.Completed
            engine.cancel(next.request.token)
            assertFalse(next.audio.file.exists())
        } finally { engine.dispose().get(5, TimeUnit.SECONDS) }
    }

    @Test fun cleanupStillRunsWhenBackendCloseFails() {
        val engine = PocketSpeechEngine({ _, _ -> temporaryAudio() }, { error("Injected close failure") })
        val output = engine.synthesize(request()).get(5, TimeUnit.SECONDS) as PocketSpeechEngine.Outcome.Completed
        val disposal = engine.dispose()
        try { disposal.get(5, TimeUnit.SECONDS); fail("Close failure hidden") }
        catch (expected: ExecutionException) { assertTrue(expected.cause is IllegalStateException) }
        assertFalse(output.audio.file.exists())
        assertSame(disposal, engine.dispose())
    }

    @Test(timeout = 180000) fun cancelsActualMainSourceInferenceWithoutLateWav() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val fixture = JSONObject(File(directory, "generation-fixtures.json").readText())
        val synth = OnnxFrenchSynthesizer(directory)
        val entered = CountDownLatch(1)
        val engine = PocketSpeechEngine({ request, check ->
            synth.synthesize(request.text, check, beforeInference = { entered.countDown() })
        })
        val existing = directory.listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet()
        try {
            val request = PocketSpeechEngine.Request("real-cancel", PocketSpeechEngine.Token("real-cancel", 1), fixture.getString("text"))
            val result = engine.synthesize(request)
            assertTrue(entered.await(20, TimeUnit.SECONDS))
            val start = android.os.SystemClock.elapsedRealtime()
            engine.cancel(request.token); engine.cancel(request.token)
            assertTrue(result.get(10, TimeUnit.SECONDS) is PocketSpeechEngine.Outcome.Cancelled)
            val latency = android.os.SystemClock.elapsedRealtime() - start
            assertEquals(existing, directory.listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet())
            assertTrue(directory.listFiles()!!.none { it.extension == "part" })
            val report = JSONObject().put("status", "passed").put("backend", "main-source OnnxFrenchSynthesizer")
                .put("cancelToWorkerExitMs", latency).put("cancelRepeated", true)
                .put("cancelledWavPublished", false).put("g0", "not_demonstrated")
            val output = File(directory, "main-worker-cancel-report-${System.currentTimeMillis()}.json")
            check(output.createNewFile()); output.writeText(report.toString(2))
        } finally { engine.dispose().get(10, TimeUnit.SECONDS) }
    }

    @Test(timeout = 180000) fun realMainSourceGenerationWithSampledMemory() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val fixture = JSONObject(File(directory, "generation-fixtures.json").readText())
        val reference = fixture.getJSONArray("noise")
        val noise = FloatArray(reference.length()) { reference.getDouble(it).toFloat() }
        val synthesizer = OnnxFrenchSynthesizer(directory)
        val engine = PocketSpeechEngine({ request, check -> synthesizer.synthesize(request.text, check, noise) })
        val baseline = Debug.getPss().toLong()
        val peak = AtomicLong(baseline)
        val measurements = AtomicLong()
        val monitor = Executors.newSingleThreadScheduledExecutor()
        monitor.scheduleAtFixedRate({
            val current = Debug.getPss().toLong()
            peak.updateAndGet { maxOf(it, current) }; measurements.incrementAndGet()
        }, 0, 50, TimeUnit.MILLISECONDS)
        try {
            val request = PocketSpeechEngine.Request("real-1", PocketSpeechEngine.Token("real", 1), fixture.getString("text"))
            val result = engine.synthesize(request).get(150, TimeUnit.SECONDS) as PocketSpeechEngine.Outcome.Completed
            assertEquals(69120, result.audio.samples)
            assertEquals(138284L, result.audio.file.length())
            assertEquals(24000, result.audio.sampleRate)
            assertTrue(result.audio.eosAt >= 0)
            val report = JSONObject().put("status", "passed").put("backend", "main-source OnnxFrenchSynthesizer")
                .put("baselinePssKiB", baseline).put("sampledPeakPssKiB", peak.get())
                .put("memorySamples", measurements.get()).put("requestedSamplingIntervalMs", 50)
                .put("memoryScope", "Instrumented process; sampled PSS, not a guaranteed peak or product threshold")
                .put("samples", result.audio.samples).put("totalMs", result.audio.totalMs)
                .put("frames", result.audio.frames).put("eosAtFrame", result.audio.eosAt)
                .put("androidApi", android.os.Build.VERSION.SDK_INT).put("g0", "not_demonstrated")
            val output = File(directory, "worker-memory-report-${System.currentTimeMillis()}.json")
            check(output.createNewFile()); output.writeText(report.toString(2))
            engine.release(result.audioHandle)
            assertFalse(result.audio.file.exists())
        } finally {
            monitor.shutdownNow(); monitor.awaitTermination(5, TimeUnit.SECONDS)
            engine.dispose().get(10, TimeUnit.SECONDS)
        }
    }
}
