package com.ureader.prototype.speech

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.os.SystemClock
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.security.MessageDigest
import java.util.UUID

/** Backend only: the host must supply a verified French frontend before product activation. */
internal class OnnxKokoroSynthesizer(
    directory: File,
    trustedFiles: Map<String, Pair<Long, String>>,
    private val outputDirectory: File,
    private val phonemize: (String) -> Phones,
    threads: Int = 1
) : AutoCloseable {
    data class Phones(val original: String, val corrected: String = original)
    private val environment = OrtEnvironment.getEnvironment()
    private val vocabulary: Map<String, Int>
    private val styles: FloatArray
    private val session: OrtSession

    init {
        require(threads in 1..4)
        require(directory.canonicalFile == directory.absoluteFile && directory.isDirectory)
        require(outputDirectory.canonicalFile == outputDirectory.absoluteFile && outputDirectory.isDirectory)
        val names = setOf("kokoro.onnx", "siwis.f32", "vocab.json")
        require(trustedFiles.keys == names)
        for ((name, pin) in trustedFiles) {
            val file = File(directory, name)
            require(file.canonicalFile == file.absoluteFile && file.isFile)
            require(pin.first > 0 && pin.first <= 512L * 1024 * 1024 && file.length() == pin.first)
            require(Regex("[a-f0-9]{64}").matches(pin.second))
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            require(digest.digest().joinToString("") { "%02x".format(it) } == pin.second)
        }
        require(File(directory, "vocab.json").length() <= 65536)
        val raw = JSONObject(File(directory, "vocab.json").readText())
        vocabulary = raw.keys().asSequence().associateWith { raw.getInt(it) }
        require(vocabulary.isNotEmpty() && vocabulary.size <= 512 && vocabulary.values.all { it in 0..255 })
        val voiceFile = File(directory, "siwis.f32")
        require(voiceFile.length() == 510L * 256 * 4)
        val values = ByteBuffer.wrap(voiceFile.readBytes()).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
        styles = FloatArray(values.remaining()).also { values.get(it) }
        require(styles.all { it.isFinite() })
        session = OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(threads)
            options.setInterOpNumThreads(1)
            options.addConfigEntry("session.intra_op.allow_spinning", "0")
            environment.createSession(File(directory, "kokoro.onnx").absolutePath, options)
        }
        try {
            require(session.inputNames == setOf("input_ids", "ref_s", "speed"))
            require(session.outputNames == setOf("waveform", "duration"))
        } catch (error: Throwable) {
            session.close()
            throw error
        }
    }

    /** Called exclusively by the serial speech worker; cancellation is checked around native work. */
    fun synthesize(text: String, checkActive: () -> Unit): NativeAudio {
        require(text.isNotBlank() && text.length <= 4096)
        val start = SystemClock.elapsedRealtime()
        checkActive()
        val phones = phonemize(text)
        checkActive()
        val ids = KokoroInputs.ids(phones.corrected, vocabulary)
        val offset = KokoroInputs.styleOffset(phones.original)
        val style = styles.copyOfRange(offset, offset + 256)
        val inferenceStart = SystemClock.elapsedRealtime()
        val pcm = OnnxTensor.createTensor(environment, LongBuffer.wrap(ids), longArrayOf(1, ids.size.toLong())).use { tokens ->
            OnnxTensor.createTensor(environment, FloatBuffer.wrap(style), longArrayOf(1, 256)).use { reference ->
                OnnxTensor.createTensor(environment, FloatBuffer.wrap(floatArrayOf(1f)), longArrayOf()).use { speed ->
                    session.run(mapOf("input_ids" to tokens, "ref_s" to reference, "speed" to speed)).use { result ->
                        checkActive()
                        val waveform = result.get("waveform").get() as OnnxTensor
                        val buffer = waveform.floatBuffer
                        require(buffer.remaining() in 1..480000) { "Audio exceeds native contract" }
                        val audio = FloatArray(buffer.remaining()).also { buffer.get(it) }
                        require(audio.all { it.isFinite() } && audio.any { it != 0f })
                        val durations = (result.get("duration").get() as OnnxTensor).longBuffer
                        require(durations.remaining() == ids.size)
                        while (durations.hasRemaining()) require(durations.get() > 0)
                        audio
                    }
                }
            }
        }
        val generationMs = SystemClock.elapsedRealtime() - inferenceStart
        val wav = ByteBuffer.allocate(44 + pcm.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        wav.put("RIFF".toByteArray(Charsets.US_ASCII)).putInt(36 + pcm.size * 2)
            .put("WAVEfmt ".toByteArray(Charsets.US_ASCII)).putInt(16)
            .putShort(1).putShort(1).putInt(24000).putInt(48000)
            .putShort(2).putShort(16).put("data".toByteArray(Charsets.US_ASCII)).putInt(pcm.size * 2)
        for (sample in pcm) wav.putShort((sample.coerceIn(-1f, 1f) * 32767).toInt().toShort())
        val stamp = UUID.randomUUID()
        val part = File(outputDirectory, "generation-$stamp.part")
        val output = File(outputDirectory, "generation-$stamp.wav")
        try {
            checkActive()
            check(part.createNewFile())
            part.outputStream().use { it.write(wav.array()); it.fd.sync() }
            checkActive()
            check(!output.exists() && part.renameTo(output))
            checkActive()
            return NativeAudio(output, 24000, pcm.size, 0, -1, generationMs,
                SystemClock.elapsedRealtime() - start, timings = mapOf("generationMs" to generationMs))
        } catch (error: Throwable) {
            output.delete()
            throw error
        } finally {
            part.delete()
        }
    }

    override fun close() = session.close()
}
