package com.ureader.prototype.speech

import android.os.Debug
import android.os.SystemClock
import android.provider.Settings
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Bounded short-cycle measurement, not a long-session leak acceptance test. */
class AlignedMemoryCyclesTest {
    @Test(timeout = 240000) fun sixGenerationReleaseDisposeCycles() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-aligned-generation")
        fun radios(): JSONObject {
            val airplane = Settings.Global.getInt(context.contentResolver, "airplane_mode_on", -1)
            val wifi = Settings.Global.getInt(context.contentResolver, "wifi_on", -1)
            val policy = Settings.Global.getString(context.contentResolver, "airplane_mode_radios") ?: ""
            assertEquals(1, airplane); assertEquals(0, wifi)
            assertTrue(policy.split(',').contains("cell"))
            return JSONObject().put("airplane_mode_on", airplane).put("wifi_on", wifi).put("policy", policy)
        }
        fun snapshot(): JSONObject {
            val runtime = Runtime.getRuntime()
            return JSONObject().put("elapsedRealtimeMs", SystemClock.elapsedRealtime())
                .put("pssKiB", Debug.getPss()).put("nativeHeapAllocatedBytes", Debug.getNativeHeapAllocatedSize())
                .put("javaHeapUsedBytes", runtime.totalMemory() - runtime.freeMemory())
                .put("openFileDescriptors", File("/proc/self/fd").list()?.size ?: -1)
        }
        val fixture = JSONObject(File(directory, "aligned-cases.json").readText())
        val cases = fixture.getJSONArray("cases")
        val audit = JSONObject(File(directory, "audit-lock.json").readText())
        assertEquals(168, audit.getInt("expectedVoiceOffset"))
        val files = audit.getJSONArray("files")
        val pins = HashMap<String, Pair<Long, String>>()
        for (i in 0 until files.length()) {
            val entry = files.getJSONObject(i)
            pins[entry.getString("name")] = entry.getLong("byteSize") to entry.getString("sha256")
        }
        val baselineWavs = directory.listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet()
        val baseline = snapshot()
        val peak = AtomicLong(baseline.getLong("pssKiB"))
        val sampleCount = AtomicLong()
        val monitor = Executors.newSingleThreadScheduledExecutor()
        monitor.scheduleAtFixedRate({ peak.updateAndGet { maxOf(it, Debug.getPss()) }; sampleCount.incrementAndGet() },
            0, 100, TimeUnit.MILLISECONDS)
        val cycles = JSONArray()
        val report = JSONObject().put("status", "running").put("baseline", baseline)
            .put("radiosBefore", radios()).put("cycles", cycles).put("cycleCount", 6)
            .put("naturalSettlingMs", 2000).put("forcedGcDuringCycles", false)
            .put("androidApi", android.os.Build.VERSION.SDK_INT).put("g0", "not_demonstrated")
        val output = File(directory, "aligned-memory-report-${System.currentTimeMillis()}.json")
        check(output.createNewFile())
        try {
            for (i in 0 until 6) {
                val case = cases.getJSONObject(i % cases.length())
                val backend = OnnxFrenchSynthesizer(directory, pins, 168)
                val engine = PocketSpeechEngine({ request, check -> backend.synthesize(request.text, check) })
                val entry = JSONObject().put("cycle", i + 1).put("caseId", case.getString("id"))
                    .put("before", snapshot())
                try {
                    val request = PocketSpeechEngine.Request("memory-$i", PocketSpeechEngine.Token("memory", i.toLong()),
                        case.getString("text"))
                    val result = engine.synthesize(request).get(150, TimeUnit.SECONDS)
                    assertTrue(result is PocketSpeechEngine.Outcome.Completed)
                    val completed = result as PocketSpeechEngine.Outcome.Completed
                    entry.put("samples", completed.audio.samples).put("totalMs", completed.audio.totalMs)
                        .put("afterGeneration", snapshot())
                    assertEquals(44L + completed.audio.samples * 2L, completed.audio.file.length())
                    engine.release(completed.audioHandle)
                    assertFalse(completed.audio.file.exists())
                    val disposal = engine.dispose(); assertSame(disposal, engine.dispose())
                    disposal.get(10, TimeUnit.SECONDS)
                } finally { engine.dispose().get(10, TimeUnit.SECONDS) }
                entry.put("afterDispose", snapshot())
                Thread.sleep(2000)
                entry.put("afterNaturalWait", snapshot())
                assertEquals(baselineWavs, directory.listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet())
                assertTrue(directory.listFiles()!!.none { it.extension == "part" })
                entry.put("audioFilesCleaned", true)
                cycles.put(entry)
                output.writeText(report.toString(2))
            }
            report.put("afterNaturalCycles", snapshot())
            // Supplemental diagnostic only. This is not production cleanup or a GC guarantee.
            System.gc()
            Thread.sleep(5000)
            report.put("afterExplicitGcRequestAnd5s", snapshot()).put("explicitGcDiagnosticOnly", true)
                .put("sampledPeakPssKiB", peak.get()).put("memorySamples", sampleCount.get())
                .put("requestedSamplingIntervalMs", 100).put("radiosAfter", radios())
                .put("status", "measurement_completed").put("applicationResolverUnchanged", true)
                .put("leakVerdict", "not_established_by_this_short_campaign")
            output.writeText(report.toString(2))
        } finally {
            monitor.shutdownNow(); monitor.awaitTermination(5, TimeUnit.SECONDS)
            if (report.getString("status") != "measurement_completed") {
                report.put("status", "incomplete"); output.writeText(report.toString(2))
            }
        }
    }
}
