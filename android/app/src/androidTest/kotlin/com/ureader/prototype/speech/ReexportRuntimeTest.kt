package com.ureader.prototype.speech

import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Real JNI loading only: no synthesis or G0 verdict inferred. */
class ReexportRuntimeTest {
    @Test(timeout = 180000) fun reproducedGraphsLoadOnWorker() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-reexport-probe")
        val worker = Executors.newSingleThreadExecutor()
        try {
            val report = worker.submit(Callable {
                val env = OrtEnvironment.getEnvironment("ureader-reexport-probe")
                env.setTelemetry(false)
                assertEquals("1.25.0", env.version)
                val entries = JSONObject(File(directory, "reexport-probe.json").readText()).getJSONArray("graphs")
                assertEquals(3, entries.length())
                val expected = mapOf("main-official-int8.onnx" to (14 to 14),
                    "flow-official-int8.onnx" to (4 to 1), "mimi-official-int8.onnx" to (25 to 25))
                val seen = HashSet<String>()
                val graphs = JSONArray()
                OrtSession.SessionOptions().use { options ->
                    options.setIntraOpNumThreads(1); options.setInterOpNumThreads(1)
                    options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.NO_OPT)
                    for (i in 0 until entries.length()) {
                        val entry = entries.getJSONObject(i)
                        val name = entry.getString("name")
                        require(name in expected && seen.add(name))
                        val file = File(directory, name)
                        assertEquals(entry.getLong("byteSize"), file.length())
                        val digest = MessageDigest.getInstance("SHA-256")
                        file.inputStream().use { stream ->
                            val buffer = ByteArray(65536)
                            while (true) { val n = stream.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
                        }
                        assertEquals(entry.getString("sha256"), digest.digest().joinToString("") { "%02x".format(it) })
                        env.createSession(file.path, options).use { session ->
                            assertEquals(expected.getValue(name).first.toLong(), session.numInputs)
                            assertEquals(expected.getValue(name).second.toLong(), session.numOutputs)
                            graphs.put(JSONObject().put("file", name).put("load", "passed")
                                .put("inputs", session.numInputs).put("outputs", session.numOutputs))
                        }
                    }
                }
                JSONObject().put("runtime", env.version).put("graphs", graphs)
                    .put("androidApi", android.os.Build.VERSION.SDK_INT).put("audioGenerated", false)
                    .put("g0", "not_demonstrated")
            }).get(150, TimeUnit.SECONDS)
            val file = File(directory, "load-report-${System.currentTimeMillis()}.json")
            check(file.createNewFile()); file.writeText(report.toString(2))
        } finally { worker.shutdown(); assertTrue(worker.awaitTermination(10, TimeUnit.SECONDS)) }
    }
}
