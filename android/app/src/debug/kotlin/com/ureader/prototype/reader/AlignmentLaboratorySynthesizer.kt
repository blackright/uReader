package com.ureader.prototype.reader

import com.ureader.prototype.speech.FrenchUnigramTokenizer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.os.SystemClock
import android.util.Half
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.security.MessageDigest
import kotlin.math.ceil

internal data class AlignmentNativeAudio(val file: File, val sampleRate: Int, val samples: Int,
    val frames: Int, val eosAt: Int, val generationMs: Long, val totalMs: Long)

/** DEBUG ONLY. Frozen copy of the audited synthesizer, augmented with raw L3H9 attention.
 * Never used by SpeechPlugin or a product capability. */
internal class AlignmentLaboratorySynthesizer(directory: File,
    trustedFiles: Map<String, Pair<Long, String>> = previousCandidateFiles(),
    private val expectedVoiceOffset: Int = 168,
    private val captureAttention: Boolean = false,
    outputDirectory: File = directory) {
    // Trust metadata is supplied by the native host, never by a Flutter message or model file.
    private val expectedFiles = trustedFiles.toMap()
    init {
        require(expectedVoiceOffset in setOf(154, 168)) { "Unsupported host voice protocol" }
        require(expectedFiles.keys == previousCandidateFiles().keys) { "Unexpected bundle files" }
        for ((_, entry) in expectedFiles) {
            require(entry.first > 0 && Regex("^[a-f0-9]{64}$").matches(entry.second)) { "Invalid trust metadata" }
        }
    }
    private val directory = directory.canonicalFile
    private val outputDirectory = outputDirectory.canonicalFile
    val attentionRows = ArrayList<FloatArray>()
    private val random = java.util.Random()
    fun synthesize(text: String, checkActive: () -> Unit, referenceNoise: FloatArray? = null,
                   beforeInference: () -> Unit = {}): AlignmentNativeAudio {
        ensureDifferent(android.os.Looper.getMainLooper().thread, Thread.currentThread())
        require(directory.isDirectory && directory.canonicalFile == directory.absoluteFile) { "Private bundle root invalid" }
        require(outputDirectory.isDirectory && outputDirectory.canonicalFile == outputDirectory.absoluteFile) { "Private audio root invalid" }
        for ((name, expected) in expectedFiles) {
            checkActive()
            val file = File(directory, name)
            require(file.canonicalFile.parentFile == directory.canonicalFile && file.length() == expected.first) { "Bundle file invalid" }
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) { checkActive(); val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
            }
            require(digest.digest().joinToString("") { "%02x".format(it) } == expected.second) { "Bundle integrity failure" }
        }
        val manifest = JSONObject(File(directory, "manifest.json").readText())
        ensureEqual(24000, manifest.getInt("sample_rate"))
        ensureEqual(1, manifest.getInt("sampler_decode_steps"))
        require(text.isNotBlank() && text.length <= 4096) { "Invalid speech input" }
        val ids = FrenchUnigramTokenizer(File(directory, "tokenizer.json").readText()).encode(text)
        ensure(ids.size in 1..50)
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
        fun finite(values: FloatArray) { ensure("Non-finite inference output", values.all { it.isFinite() }) }
        val ownedInitial = ArrayList<OnnxTensor>()
        var mainResult: OrtSession.Result? = null
        var decoderResult: OrtSession.Result? = null
        val start = SystemClock.elapsedRealtime()
        val stamp = java.util.UUID.randomUUID().toString()
        fun budget() {
            checkActive()
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
                                ensureEqual(expectedVoiceOffset, offset)
                                val cache = FloatArray(2 * offset * 16 * 64) { Half.toFloat(voice.short) }
                                finite(cache)
                                states["cache_$i"] = floats(cache, 2, 1, offset.toLong(), 16, 64).also { ownedInitial.add(it) }
                                states["offset_$i"] = longs(longArrayOf(offset.toLong()), 1).also { ownedInitial.add(it) }
                            }
                            ensureFalse(voice.hasRemaining())
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
                                        beforeInference()
                                        val next = main.run(inputs)
                                        if (captureAttention && sequence.isNotEmpty()) {
                                            val attention = next[14] as OnnxTensor
                                            val shape = attention.info.shape
                                            ensure(shape.size == 4 && shape[0] == 1L && shape[1] == 16L && shape[2] in 1..50 && shape[3] in 1..1024)
                                            val raw = values(attention)
                                            val keys = shape[3].toInt()
                                            val base = (9 * shape[2].toInt() + shape[2].toInt() - 1) * keys + expectedVoiceOffset
                                            ensure(base + ids.size <= raw.size && attentionRows.size < 250)
                                            val row = raw.copyOfRange(base, base + ids.size)
                                            finite(row); attentionRows.add(row)
                                        }
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
                            val noise = referenceNoise ?: FloatArray(250 * 32) { random.nextGaussian().toFloat() * kotlin.math.sqrt(0.3f) }
                            ensureEqual(250 * 32, noise.size)
                            val limit = minOf(250, ceil((ids.size / 3.0 + 2.0) * 12.5).toInt())
                            val tail = (if (text.split(" ").size <= 4) 3 else 1) + 2
                            var eosAt = -1
                            var terminated = false
                            for (step in 0 until limit) {
                                val (conditioning, eos) = mainStep(sequence, FloatArray(0))
                                if (step >= manifest.getInt("min_frames_before_eos") &&
                                    eos > manifest.getDouble("eos_threshold") && eosAt < 0) eosAt = step
                                if (eosAt >= 0 && step >= eosAt + tail) { terminated = true; break }
                                val x = FloatArray(32) { noise[step * 32 + it] }
                                floats(conditioning, 1, 1024).use { c ->
                                    floats(floatArrayOf(0f), 1, 1).use { s ->
                                        floats(floatArrayOf(1f), 1, 1).use { t ->
                                            floats(x, 1, 32).use { input ->
                                                budget()
                                                flow.run(mapOf("c" to c, "s" to s, "t" to t, "x" to input)).use { output ->
                                                    val direction = values(output[0] as OnnxTensor)
                                                    ensureEqual(32, direction.size)
                                                    sequence = FloatArray(32) { x[it] + direction[it] }
                                                    finite(sequence); latents.add(sequence)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            ensure("EOS not reached and finalized within bound", terminated && latents.isNotEmpty())
                            val generationMs = SystemClock.elapsedRealtime() - start
                            mainResult?.close(); mainResult = null
                            val mimi = HashMap<String, OnnxTensor>()
                            val stateSpecs = manifest.getJSONArray("mimi_states")
                            ensureEqual(24, stateSpecs.length())
                            for (i in 0 until stateSpecs.length()) {
                                val spec = stateSpecs.getJSONObject(i)
                                val dims = spec.getJSONArray("shape")
                                val shape = LongArray(dims.length()) { dims.getLong(it) }
                                val count = shape.fold(1L) { a, b -> a * b }.toInt()
                                val tensor = when (spec.getString("dtype")) {
                                    "float32" -> floats(FloatArray(count), *shape)
                                    "int64" -> longs(LongArray(count), *shape)
                                    "bool" -> {
                                        ensureShape(longArrayOf(1), shape)
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
                            ensure(samples.isNotEmpty() && samples.any { it != 0f })
                            val pcmBytes = samples.size * 2
                            val wav = ByteBuffer.allocate(44 + pcmBytes).order(ByteOrder.LITTLE_ENDIAN)
                            wav.put("RIFF".toByteArray()).putInt(36 + pcmBytes).put("WAVEfmt ".toByteArray())
                                .putInt(16).putShort(1).putShort(1).putInt(manifest.getInt("sample_rate"))
                                .putInt(48000).putShort(2).putShort(16).put("data".toByteArray()).putInt(pcmBytes)
                            for (sample in samples) wav.putShort((sample.coerceIn(-1f, 1f) * 32767).toInt().toShort())
                            budget()
                            val staging = File(outputDirectory, "generation-$stamp.part")
                            val output = File(outputDirectory, "generation-$stamp.wav")
                            check(staging.createNewFile())
                            try {
                                staging.outputStream().use { it.write(wav.array()); it.fd.sync() }
                                check(!output.exists() && staging.renameTo(output))
                            } finally { staging.delete() }
                            return AlignmentNativeAudio(output, 24000, samples.size, latents.size, eosAt,
                                generationMs, SystemClock.elapsedRealtime() - start)

                        } finally {
                            mainResult?.close(); decoderResult?.close()
                            ownedInitial.forEach { it.close() }
                        }
                    }
                }
            }
        }
    }
    private fun ensure(value: Boolean) { check(value) { "Invalid inference result" } }
    private fun ensure(message: String, value: Boolean) { check(value) { message } }
    private fun ensureFalse(value: Boolean) = ensure(!value)
    private fun ensureEqual(expected: Any, actual: Any) { check(expected == actual) { "Incompatible tensor protocol" } }
    private fun ensureDifferent(expected: Any, actual: Any) { check(expected != actual) { "Inference on main thread" } }
    private fun ensureShape(expected: LongArray, actual: LongArray) { check(expected.contentEquals(actual)) { "Invalid tensor shape" } }
    companion object {
        private fun previousCandidateFiles(): Map<String, Pair<Long, String>> = mapOf(
            "flow_lm_main_int8.onnx" to Pair(76063417L, "fbdafb5f3f004565114aca628ebf96c4c5c6e861d953f293351c2c585fbc211f"),
            "flow_lm_flow_int8.onnx" to Pair(9966003L, "edee960ed0d3783bc31c9d3ae182884562193d78bbc3ab28fefa23bd2949e0e4"),
            "mimi_decoder_int8.onnx" to Pair(22688110L, "b7fd081d6ee991521553a32ffc19981bc40a68042c3219cd1b6845c983c84e21"),
            "text_embeddings.f16" to Pair(8194048L, "00cbfe5ea0e0a93689e07917750cc99193af02800e35190333dbbcef50a6d2af"),
            "tokenizer.json" to Pair(246403L, "6211acffe9cb95172f71f0051f18e26ea305b2b32ea00b331ee976551c70887f"),
            "estelle.f16" to Pair(3784704L, "24b8fed0f9b0b959960c05008b77c1df7d436bd269121dc235b1cc8bd48b26f1"),
            "manifest.json" to Pair(5318L, "feeefe94c2accd81f4f4d87901dc0fe2d318bab5c073ff4fd38bed1b6aa584d8")
        )
    }

}
