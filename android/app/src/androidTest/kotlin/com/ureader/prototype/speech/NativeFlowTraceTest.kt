package com.ureader.prototype.speech

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Trace de diagnostic privée ; ne change ni le modèle publié ni les seuils du préflight. */
class NativeFlowTraceTest {
    @Test(timeout = 180000)
    fun captureFlowIntermediates() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val manifest = JSONObject(File(directory, "flow-trace-01-manifest.json").readText())
        val model = File(directory, "flow-trace-01.onnx")
        require(model.length() in 1..12000000)
        val digest = MessageDigest.getInstance("SHA-256").digest(model.readBytes())
            .joinToString("") { "%02x".format(it) }
        assertEquals(manifest.getString("traceSha256"), digest)
        assertEquals(ByteOrder.LITTLE_ENDIAN, ByteOrder.nativeOrder())
        val worker = Executors.newSingleThreadExecutor()
        try {
            worker.submit(Callable {
                val env = OrtEnvironment.getEnvironment("ureader-flow-trace")
                env.setTelemetry(false)
                assertEquals("1.25.0", env.version)
                OrtSession.SessionOptions().use { options ->
                    options.setInterOpNumThreads(1)
                    options.setIntraOpNumThreads(1)
                    options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.NO_OPT)
                    env.createSession(model.absolutePath, options).use { session ->
                        assertEquals(manifest.getInt("outputs").toLong(), session.numOutputs)
                        val fixture = manifest.getJSONObject("fixture")
                        val inputs = mutableMapOf<String, OnnxTensor>()
                        try {
                            for ((name, size) in mapOf("c" to 1024, "s" to 1, "t" to 1, "x" to 32)) {
                                val source = fixture.getJSONArray(name)
                                assertEquals(size, source.length())
                                val values = FloatArray(size) { source.getDouble(it).toFloat() }
                                inputs[name] = OnnxTensor.createTensor(env, FloatBuffer.wrap(values), longArrayOf(1, size.toLong()))
                            }
                            session.run(inputs).use { outputs ->
                                val file = File(directory, "flow-trace-device-${System.currentTimeMillis()}.zip")
                                check(file.createNewFile())
                                ZipOutputStream(FileOutputStream(file)).use { zip ->
                                    val index = JSONArray()
                                    var total = 0
                                    for ((i, entry) in outputs.withIndex()) {
                                        val tensor = entry.value as OnnxTensor
                                        val buffer = tensor.byteBuffer
                                        total += buffer.remaining()
                                        require(total <= 16000000)
                                        val name = "%04d.bin".format(i)
                                        zip.putNextEntry(ZipEntry(name))
                                        val block = ByteArray(minOf(65536, maxOf(1, buffer.remaining())))
                                        while (buffer.hasRemaining()) {
                                            val count = minOf(block.size, buffer.remaining())
                                            buffer.get(block, 0, count)
                                            zip.write(block, 0, count)
                                        }
                                        zip.closeEntry()
                                        index.put(JSONObject().put("file", name).put("outputName", entry.key)
                                            .put("shape", JSONArray(tensor.info.shape.toList()))
                                            .put("type", tensor.info.type.toString()))
                                    }
                                    zip.putNextEntry(ZipEntry("index.json"))
                                    zip.write(index.toString().toByteArray(Charsets.UTF_8))
                                    zip.closeEntry()
                                }
                            }
                        } finally {
                            inputs.values.forEach { it.close() }
                        }
                    }
                }
            }).get(150, TimeUnit.SECONDS)
        } finally {
            worker.shutdown()
            assertTrue(worker.awaitTermination(10, TimeUnit.SECONDS))
        }
    }
}
