package com.ureader.prototype.speech

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.os.SystemClock
import android.util.Half
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil

/** Bounded protocol experiment. No Flutter bridge, playback, or production activation. */
class FrenchGenerationProbeTest {
    @Test(timeout = 180000) fun generatesCompleteFrenchWavOnWorker() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val worker = Executors.newSingleThreadExecutor()
        try {
            worker.submit(Callable { generate(directory) }).get(160, TimeUnit.SECONDS)
        } finally { worker.shutdownNow() }
    }

    @Test(timeout = 180000) fun cancellationReleasesResourcesWithoutPublishing() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val worker = Executors.newSingleThreadExecutor()
        val cancelled = AtomicBoolean(false)
        val enteredInference = CountDownLatch(1)
        val previousWavs = directory.listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet()
        try {
            val future = worker.submit(Callable { generate(directory, cancelled) { enteredInference.countDown() } })
            assertTrue("Inference not entered", enteredInference.await(15, TimeUnit.SECONDS))
            val start = SystemClock.elapsedRealtime()
            cancelled.set(true); cancelled.set(true)
            try { future.get(10, TimeUnit.SECONDS); fail("Cancelled generation completed") }
            catch (e: ExecutionException) { assertTrue(e.cause is CancellationException) }
            val latency = SystemClock.elapsedRealtime() - start
            assertEquals(previousWavs,
                directory.listFiles()!!.filter { it.extension == "wav" }.map { it.name }.toSet())
            assertTrue(directory.listFiles()!!.none { it.extension == "part" })
            // A new real generation on the same serial worker verifies resource recovery.
            worker.submit(Callable { generate(directory) }).get(150, TimeUnit.SECONDS)
            val report = JSONObject().put("cancelRepeated", true).put("cancelToWorkerExitMs", latency)
                .put("cancelledWavPublished", false).put("subsequentGeneration", "passed")
                .put("scope", "native protocol experiment, not Flutter session lifecycle")
                .put("g0", "not_demonstrated")
            val output = File(directory, "cancellation-report-${System.currentTimeMillis()}.json")
            check(output.createNewFile()); output.writeText(report.toString(2))
        } finally { cancelled.set(true); worker.shutdownNow() }
    }

    private fun generate(directory: File, cancelled: AtomicBoolean = AtomicBoolean(false),
                         enteringInference: () -> Unit = {}) {
        assertNotEquals(android.os.Looper.getMainLooper().thread, Thread.currentThread())
        val fixture = JSONObject(File(directory, "generation-fixtures.json").readText())
        val files = fixture.getJSONArray("files")
        val allowed = setOf("flow_lm_main_int8.onnx", "flow_lm_flow_int8.onnx", "mimi_decoder_int8.onnx",
            "text_embeddings.f16", "estelle.f16", "tokenizer.json", "manifest.json")
        assertEquals(7, files.length())
        val seen = HashSet<String>()
        for (i in 0 until files.length()) {
            val entry = files.getJSONObject(i)
            val name = entry.getString("name")
            assertTrue(allowed.contains(name) && seen.add(name))
            val file = File(directory, name)
            assertEquals(entry.getLong("byteSize"), file.length())
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) { val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) }
            }
            assertEquals(entry.getString("sha256"), hash.digest().joinToString("") { "%02x".format(it) })
        }
        val manifest = JSONObject(File(directory, "manifest.json").readText())
        assertEquals(24000, manifest.getInt("sample_rate"))
        assertEquals(1, manifest.getInt("sampler_decode_steps"))
        val text = fixture.getString("text")
        val ids = FrenchUnigramTokenizer(File(directory, "tokenizer.json").readText()).encode(text)
        val expected = fixture.getJSONArray("tokenIds")
        assertArrayEquals(IntArray(expected.length()) { expected.getInt(it) }, ids)
        assertTrue(ids.size in 1..50)
        val env = OrtEnvironment.getEnvironment("ureader-g0-generation")
        env.setTelemetry(false)
        fun floats(values: FloatArray, vararg shape: Long) =
            OnnxTensor.createTensor(env, FloatBuffer.wrap(values), shape)
        fun longs(values: LongArray, vararg shape: Long) =
            OnnxTensor.createTensor(env, LongBuffer.wrap(values), shape)
        fun values(tensor: OnnxTensor): FloatArray {
            val buffer = tensor.floatBuffer
            return FloatArray(buffer.remaining()).also { buffer.get(it) }
        }
        fun finite(values: FloatArray) { assertTrue("Non-finite inference output", values.all { it.isFinite() }) }
        val ownedInitial = ArrayList<OnnxTensor>()
        var mainResult: OrtSession.Result? = null
        var decoderResult: OrtSession.Result? = null
        val start = SystemClock.elapsedRealtime()
        val stamp = System.currentTimeMillis()
        fun budget() {
            if (cancelled.get() || Thread.currentThread().isInterrupted) throw CancellationException()
            check(SystemClock.elapsedRealtime() - start < 120000) { "Generation time budget exceeded" }
        }
        OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(1)
            options.setInterOpNumThreads(1)
            options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.NO_OPT)
            env.createSession(File(directory, "flow_lm_main_int8.onnx").path, options).use { main ->
                env.createSession(File(directory, "flow_lm_flow_int8.onnx").path, options).use { flow ->
                    env.createSession(File(directory, "mimi_decoder_int8.onnx").path, options).use { decoder ->
                        try {
                            val states = HashMap<String, OnnxTensor>()
                            val voice = ByteBuffer.wrap(File(directory, "estelle.f16").readBytes()).order(ByteOrder.LITTLE_ENDIAN)
                            val offsets = manifest.getJSONObject("voices").getJSONObject("estelle").getJSONArray("offsets")
                            for (i in 0..5) {
                                val offset = offsets.getInt(i)
                                assertEquals(154, offset)
                                val cache = FloatArray(2 * offset * 16 * 64) { Half.toFloat(voice.short) }
                                finite(cache)
                                states["cache_$i"] = floats(cache, 2, 1, offset.toLong(), 16, 64).also { ownedInitial.add(it) }
                                states["offset_$i"] = longs(longArrayOf(offset.toLong()), 1).also { ownedInitial.add(it) }
                            }
                            assertFalse(voice.hasRemaining())
                            val table = ByteBuffer.wrap(File(directory, "text_embeddings.f16").readBytes()).order(ByteOrder.LITTLE_ENDIAN)
                            val embedded = FloatArray(ids.size * 1024) { index ->
                                Half.toFloat(table.getShort((ids[index / 1024] * 1024 + index % 1024) * 2))
                            }
                            finite(embedded)
                            fun mainStep(sequence: FloatArray, embeddings: FloatArray): Pair<FloatArray, Float> {
                                budget()
                                floats(sequence, 1, (sequence.size / 32).toLong(), 32).use { seq ->
                                    floats(embeddings, 1, (embeddings.size / 1024).toLong(), 1024).use { emb ->
                                        val inputs = HashMap(states)
                                        inputs["sequence"] = seq
                                        inputs["text_embeddings"] = emb
                                        enteringInference()
                                        val next = main.run(inputs)
                                        val old = mainResult
                                        mainResult = next
                                        for (i in 0..5) {
                                            states["cache_$i"] = next[2 + 2 * i] as OnnxTensor
                                            states["offset_$i"] = next[3 + 2 * i] as OnnxTensor
                                        }
                                        old?.close()
                                        val conditioning = values(next[0] as OnnxTensor)
                                        val eos = values(next[1] as OnnxTensor)
                                        finite(conditioning); finite(eos)
                                        return conditioning to eos.single()
                                    }
                                }
                            }
                            mainStep(FloatArray(0), embedded)
                            ownedInitial.forEach { it.close() }; ownedInitial.clear()
                            var sequence = FloatArray(32) { Float.NaN } // Exported BOS sentinel, not random audio.
                            val latents = ArrayList<FloatArray>()
                            val noise = fixture.getJSONArray("noise")
                            assertEquals(250 * 32, noise.length())
                            val limit = minOf(250, ceil((ids.size / 3.0 + 2.0) * 12.5).toInt())
                            val tail = (if (text.split(" ").size <= 4) 3 else 1) + 2
                            var eosAt = -1
                            var terminated = false
                            for (step in 0 until limit) {
                                val (conditioning, eos) = mainStep(sequence, FloatArray(0))
                                if (step >= manifest.getInt("min_frames_before_eos") &&
                                    eos > manifest.getDouble("eos_threshold") && eosAt < 0) eosAt = step
                                if (eosAt >= 0 && step >= eosAt + tail) { terminated = true; break }
                                val x = FloatArray(32) { noise.getDouble(step * 32 + it).toFloat() }
                                floats(conditioning, 1, 1024).use { c ->
                                    floats(floatArrayOf(0f), 1, 1).use { s ->
                                        floats(floatArrayOf(1f), 1, 1).use { t ->
                                            floats(x, 1, 32).use { input ->
                                                budget()
                                                flow.run(mapOf("c" to c, "s" to s, "t" to t, "x" to input)).use { output ->
                                                    val direction = values(output[0] as OnnxTensor)
                                                    assertEquals(32, direction.size)
                                                    sequence = FloatArray(32) { x[it] + direction[it] }
                                                    finite(sequence); latents.add(sequence)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            assertTrue("EOS not reached and finalized within bound", terminated && latents.isNotEmpty())
                            val generationMs = SystemClock.elapsedRealtime() - start
                            mainResult?.close(); mainResult = null
                            val mimi = HashMap<String, OnnxTensor>()
                            val stateSpecs = manifest.getJSONArray("mimi_states")
                            assertEquals(24, stateSpecs.length())
                            for (i in 0 until stateSpecs.length()) {
                                val spec = stateSpecs.getJSONObject(i)
                                val dims = spec.getJSONArray("shape")
                                val shape = LongArray(dims.length()) { dims.getLong(it) }
                                val count = shape.fold(1L) { a, b -> a * b }.toInt()
                                val tensor = when (spec.getString("dtype")) {
                                    "float32" -> floats(FloatArray(count), *shape)
                                    "int64" -> longs(LongArray(count), *shape)
                                    "bool" -> {
                                        assertArrayEquals(longArrayOf(1), shape)
                                        OnnxTensor.createTensor(env, booleanArrayOf(spec.getString("key") == "first"))
                                    }
                                    else -> error("Unsupported decoder state")
                                }
                                mimi["mimi_$i"] = tensor.also { ownedInitial.add(it) }
                            }
                            val samples = ArrayList<Float>()
                            for (chunk in latents.indices step 12) {
                                budget()
                                val count = minOf(12, latents.size - chunk)
                                val latent = FloatArray(count * 32) { latents[chunk + it / 32][it % 32] }
                                floats(latent, 1, count.toLong(), 32).use { input ->
                                    val inputs = HashMap(mimi); inputs["latent"] = input
                                    val next = decoder.run(inputs)
                                    val old = decoderResult; decoderResult = next
                                    for (i in 0 until 24) mimi["mimi_$i"] = next[i + 1] as OnnxTensor
                                    old?.close()
                                    val pcm = values(next[0] as OnnxTensor)
                                    finite(pcm)
                                    check(samples.size + pcm.size <= 480000) { "PCM sample limit" }
                                    for (value in pcm) samples.add(value)
                                }
                            }
                            assertTrue(samples.isNotEmpty() && samples.any { it != 0f })
                            val pcmBytes = samples.size * 2
                            val wav = ByteBuffer.allocate(44 + pcmBytes).order(ByteOrder.LITTLE_ENDIAN)
                            wav.put("RIFF".toByteArray()).putInt(36 + pcmBytes).put("WAVEfmt ".toByteArray())
                                .putInt(16).putShort(1).putShort(1).putInt(manifest.getInt("sample_rate"))
                                .putInt(48000).putShort(2).putShort(16).put("data".toByteArray()).putInt(pcmBytes)
                            for (sample in samples) wav.putShort((sample.coerceIn(-1f, 1f) * 32767).toInt().toShort())
                            budget()
                            val staging = File(directory, "generation-$stamp.part")
                            val output = File(directory, "generation-$stamp.wav")
                            check(staging.createNewFile())
                            try {
                                staging.outputStream().use { it.write(wav.array()); it.fd.sync() }
                                check(!output.exists() && staging.renameTo(output))
                            } finally { staging.delete() }
                            val report = JSONObject().put("runtime", env.version).put("androidApi", android.os.Build.VERSION.SDK_INT)
                                .put("frames", latents.size).put("eosAtFrame", eosAt).put("tokens", ids.size)
                                .put("samples", samples.size).put("sampleRate", manifest.getInt("sample_rate"))
                                .put("durationSeconds", samples.size / 24000.0).put("generationMs", generationMs)
                                .put("generationAndDecodeMs", SystemClock.elapsedRealtime() - start)
                                .put("wav", output.name).put("intelligibility", "not_evaluated")
                                .put("cancellation", "not_evaluated").put("g0", "not_demonstrated")
                            val reportFile = File(directory, "generation-report-$stamp.json")
                            check(reportFile.createNewFile()); reportFile.writeText(report.toString(2))
                        } finally {
                            mainResult?.close(); decoderResult?.close()
                            ownedInitial.forEach { it.close() }
                        }
                    }
                }
            }
        }
    }
}
