package com.ureader.prototype.speech

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.FloatBuffer
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/** Préflight réel JNI ; aucune voix publiée, aucun son, aucune preuve G0. */
class NativeRuntimeProbeTest {
    @Test(timeout = 180000)
    fun allPrivateGraphsLoad() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val manifest = JSONObject(File(directory, "probe-manifest.json").readText())
        val worker = Executors.newSingleThreadExecutor()
        try {
            val report = worker.submit(Callable {
                val env = OrtEnvironment.getEnvironment("ureader-g0-probe")
                env.setTelemetry(false)
                assertEquals("1.25.0", env.version)
                val graphs = org.json.JSONArray()
                OrtSession.SessionOptions().use { options ->
                    options.setIntraOpNumThreads(1)
                    options.setInterOpNumThreads(1)
                    options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.NO_OPT)
                    val entries = manifest.getJSONArray("graphs")
                    assertEquals(3, entries.length())
                    for (i in 0 until entries.length()) {
                        val entry = entries.getJSONObject(i)
                        val name = entry.getString("file")
                        require(name in setOf("flow_lm_main_int8.onnx", "flow_lm_flow_int8.onnx", "mimi_decoder_int8.onnx"))
                        env.createSession(File(directory, name).absolutePath, options).use { session ->
                            assertEquals(entry.getInt("inputCount").toLong(), session.numInputs)
                            assertEquals(entry.getInt("outputCount").toLong(), session.numOutputs)
                            graphs.put(JSONObject().put("file", name).put("load", "passed")
                                .put("inputs", session.numInputs).put("outputs", session.numOutputs))
                        }
                    }
                }
                JSONObject().put("runtime", env.version).put("graphs", graphs)
                    .put("androidApi", android.os.Build.VERSION.SDK_INT)
                    .put("audioGenerated", false).put("g0", "not_demonstrated")
            }).get(150, TimeUnit.SECONDS)
            val file = File(directory, "native-load-report-${System.currentTimeMillis()}.json")
            check(file.createNewFile())
            file.writeText(report.toString(2))
        } finally {
            worker.shutdown()
            assertTrue(worker.awaitTermination(10, TimeUnit.SECONDS))
        }
    }

    @Test(timeout = 180000)
    fun privateGraphsLoadAndFlowMatchesHost() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val manifest = JSONObject(File(directory, "probe-manifest.json").readText())
        val worker = Executors.newSingleThreadExecutor()
        try {
            val report = worker.submit(Callable {
                val env = OrtEnvironment.getEnvironment("ureader-g0-probe")
                env.setTelemetry(false)
                assertEquals("1.25.0", env.version)
                val results = org.json.JSONArray()
                val entries = manifest.getJSONArray("graphs")
                OrtSession.SessionOptions().use { options ->
                    options.setIntraOpNumThreads(1)
                    options.setInterOpNumThreads(1)
                    // Diagnostic contrôlé : comparer le graphe sans fusions propres à une cible.
                    options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.NO_OPT)
                    for (i in 0 until entries.length()) {
                        val entry = entries.getJSONObject(i)
                        val name = entry.getString("file")
                        require(name in setOf("flow_lm_main_int8.onnx", "flow_lm_flow_int8.onnx", "mimi_decoder_int8.onnx"))
                        val file = File(directory, name)
                        assertEquals(entry.getLong("byteSize"), file.length())
                        val digest = MessageDigest.getInstance("SHA-256")
                        file.inputStream().use { input ->
                            val buffer = ByteArray(1024 * 1024)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                digest.update(buffer, 0, count)
                            }
                        }
                        assertEquals(entry.getString("sha256"), digest.digest().joinToString("") { "%02x".format(it) })
                        env.createSession(file.absolutePath, options).use { session ->
                            assertEquals(entry.getInt("inputCount").toLong(), session.numInputs)
                            assertEquals(entry.getInt("outputCount").toLong(), session.numOutputs)
                            val result = JSONObject().put("file", name).put("load", "passed")
                            if (name == "flow_lm_flow_int8.onnx") {
                                assertEquals("onnx.reference.ReferenceEvaluator", manifest.getString("referenceBackend"))
                                val fixtures = manifest.getJSONArray("flowFixtures")
                                assertEquals(5, fixtures.length())
                                val caseResults = org.json.JSONArray()
                                for (caseIndex in 0 until fixtures.length()) {
                                    val fixture = fixtures.getJSONObject(caseIndex)
                                    assertEquals(0.0001, fixture.getDouble("absoluteTolerance"), 0.0)
                                    val inputs = mutableMapOf<String, OnnxTensor>()
                                    try {
                                        for ((key, count) in mapOf("c" to 1024, "s" to 1, "t" to 1, "x" to 32)) {
                                            val values = fixture.getJSONArray(key)
                                            require(values.length() == count)
                                            val data = FloatArray(count) { values.getDouble(it).toFloat() }
                                            inputs[key] = OnnxTensor.createTensor(env, FloatBuffer.wrap(data), longArrayOf(1, count.toLong()))
                                        }
                                        // Deux exécutions réelles sur les mêmes handles, résultats libérés à chaque fois.
                                        var maximum = 0f
                                        val observed = org.json.JSONArray()
                                        repeat(2) { runIndex ->
                                            session.run(inputs).use { outputs ->
                                                val tensor = outputs[0] as OnnxTensor
                                                val values = tensor.floatBuffer
                                                val expected = fixture.getJSONArray("expected")
                                                assertEquals(expected.length(), values.remaining())
                                                for (j in 0 until expected.length()) {
                                                    val value = values.get()
                                                    assertTrue(value.isFinite())
                                                    if (runIndex == 0) observed.put(value.toDouble())
                                                    maximum = maxOf(maximum, abs(value - expected.getDouble(j).toFloat()))
                                                }
                                            }
                                        }
                                        val diagnostic = JSONObject().put("runtime", env.version)
                                            .put("fixtureId", fixture.getString("id"))
                                            .put("referenceBackend", manifest.getString("referenceBackend"))
                                            .put("optimization", "NO_OPT").put("actual", observed)
                                            .put("expected", fixture.getJSONArray("expected"))
                                            .put("maxAbsoluteError", maximum.toDouble())
                                            .put("absoluteTolerance", fixture.getDouble("absoluteTolerance"))
                                        val diagnosticFile = File(directory, "flow-diagnostics-${System.currentTimeMillis()}.json")
                                        check(diagnosticFile.createNewFile())
                                        diagnosticFile.writeText(diagnostic.toString(2))
                                        assertTrue("Écart numérique du préflight dépassé : $maximum", maximum <= fixture.getDouble("absoluteTolerance"))
                                        caseResults.put(JSONObject().put("id", fixture.getString("id"))
                                            .put("maxAbsoluteError", maximum.toDouble()).put("runs", 2))
                                    } finally {
                                        inputs.values.forEach { it.close() }
                                    }
                                }
                                result.put("flowRuns", fixtures.length() * 2).put("cases", caseResults)
                                    .put("referenceBackend", manifest.getString("referenceBackend"))
                                    .put("absoluteTolerance", 0.0001)
                            }
                            results.put(result)
                        }
                    }
                }
                JSONObject().put("runtime", env.version).put("graphs", results)
                    .put("androidApi", android.os.Build.VERSION.SDK_INT)
                    .put("audioGenerated", false).put("g0", "not_demonstrated")
            }).get(150, TimeUnit.SECONDS)
            val reportFile = File(directory, "native-probe-report-${System.currentTimeMillis()}.json")
            check(reportFile.createNewFile()) { "Une preuve existante ne doit pas être écrasée" }
            reportFile.writeText(report.toString(2))
        } finally {
            // Ne jamais fermer un handle sur un autre thread pendant l'inférence.
            worker.shutdown()
            assertTrue("Le worker doit terminer avant libération", worker.awaitTermination(10, TimeUnit.SECONDS))
        }
    }
}
