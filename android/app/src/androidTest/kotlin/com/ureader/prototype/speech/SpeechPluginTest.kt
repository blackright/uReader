package com.ureader.prototype.speech

import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** Real MethodChannel/EventChannel codec with an in-memory transport, no Dart playback claim. */
class SpeechPluginTest {
    @Test fun alignmentCapabilityRequiresExplicitHostQualification() {
        for (qualified in listOf(false, true)) {
            val messenger = Messenger()
            val owner = PocketSpeechEngine(backend = { _, _ -> error("No inference requested") },
                alignmentAvailable = qualified)
            val plugin = SpeechPlugin { _, _, _ -> owner }
            main { plugin.attach(messenger) }
            try {
                val before = call(messenger, "capabilities").get(5, TimeUnit.SECONDS) as Map<*, *>
                assertEquals(false, (before["alignment"] as Map<*, *>)["available"])
                call(messenger, "loadBundle", wire("loadBundle", bundle)).get(5, TimeUnit.SECONDS)
                val after = call(messenger, "capabilities").get(5, TimeUnit.SECONDS) as Map<*, *>
                assertEquals(1, after["protocolVersion"])
                assertEquals(qualified, (after["alignment"] as Map<*, *>)["available"])
            } finally { main { plugin.detach() }; owner.dispose().get(5, TimeUnit.SECONDS) }
        }
    }

    @Test(timeout = 180000) fun alignedOutputsUseSeparateCache() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manifest = context.assets.open("flutter_assets/assets/models/manifest.json").use { JSONObject(String(it.readBytes(), Charsets.UTF_8)) }
        val entries = manifest.getJSONArray("files")
        val pins = HashMap<String, Pair<Long, String>>()
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            pins[entry.getString("relativePath")] = entry.getLong("byteSize") to entry.getString("sha256")
        }
        val models = File(context.filesDir.canonicalFile, "ureader-aligned-generation")
        val outputs = File(context.cacheDir.canonicalFile, "phase5-native-output-${System.nanoTime()}")
        check(outputs.canonicalFile.parentFile == context.cacheDir.canonicalFile && outputs.mkdir())
        try {
            val backend = OnnxFrenchSynthesizer(models, pins, 168, outputs)
            val audio = backend.synthesize("Chaque matin, Léa ouvre la petite porte du jardin.", {})
            assertEquals(outputs.canonicalFile, audio.file.canonicalFile.parentFile)
            assertTrue(audio.file.length() in 46L..960044L)
            assertFalse(File(models, audio.file.name).exists())
        } finally {
            check(outputs.canonicalFile.parentFile == context.cacheDir.canonicalFile)
            outputs.listFiles()?.forEach { check(it.isFile && it.delete()) }
            check(outputs.delete())
        }
    }
    @Test(timeout = 30000) fun bundleCanBeReleasedAndLoadedAgain() {
        val engines = ArrayList<PocketSpeechEngine>()
        val plugin = SpeechPlugin { _, _, _ -> PocketSpeechEngine({ _, _ -> error("Inference not requested") }).also { engines.add(it) } }
        val messenger = Messenger()
        main { plugin.attach(messenger) }
        try {
            call(messenger, "loadBundle", wire("loadBundle", bundle)).get(5, TimeUnit.SECONDS)
            lateinit var released: CompletableFuture<Any?>
            main { released = messenger.dispatch(SpeechPlugin.AUDIO_CHANNEL, "releaseBundle", mapOf("protocolVersion" to 1)) }
            released.get(5, TimeUnit.SECONDS)
            val capabilities = call(messenger, "capabilities").get(5, TimeUnit.SECONDS) as Map<*, *>
            assertTrue((capabilities["languages"] as List<*>).isEmpty())
            call(messenger, "loadBundle", wire("loadBundle", bundle)).get(5, TimeUnit.SECONDS)
            assertEquals(2, engines.size)
            call(messenger, "dispose").get(5, TimeUnit.SECONDS)
        } finally { main { plugin.detach() }; engines.forEach { it.dispose().get(5, TimeUnit.SECONDS) } }
    }
    private class Messenger : BinaryMessenger {
        val handlers = HashMap<String, BinaryMessenger.BinaryMessageHandler>()
        val events = LinkedBlockingQueue<Map<*, *>>()
        override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            if (channel == SpeechPlugin.EVENT_CHANNEL && message != null) {
                message.flip()
                events.add(StandardMethodCodec.INSTANCE.decodeEnvelope(message) as Map<*, *>)
            }
            callback?.reply(null)
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
        fun dispatch(channel: String, method: String, arguments: Any?): CompletableFuture<Any?> {
            val future = CompletableFuture<Any?>()
            val encoded = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments))
            encoded.flip()
            handlers.getValue(channel).onMessage(encoded) { reply ->
                try {
                    check(reply != null); reply.flip()
                    future.complete(StandardMethodCodec.INSTANCE.decodeEnvelope(reply))
                } catch (error: Exception) { future.completeExceptionally(error) }
            }
            return future
        }
    }
    private var counter = 0
    private fun main(action: () -> Unit) = InstrumentationRegistry.getInstrumentation().runOnMainSync(action)
    private fun wire(method: String, payload: Map<String, Any?> = emptyMap(), generation: Int? = null): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>("protocolVersion" to 1, "command" to method,
            "requestId" to "command-${counter++}", "payload" to payload)
        if (generation != null) { result["sessionId"] = "bridge-session"; result["generation"] = generation }
        return result
    }
    private fun call(messenger: Messenger, method: String, arguments: Any? = wire(method)): CompletableFuture<Any?> {
        lateinit var future: CompletableFuture<Any?>
        main { future = messenger.dispatch(SpeechPlugin.COMMAND_CHANNEL, method, arguments) }
        return future
    }
    private val bundle = mapOf("bundleId" to "g0-candidate", "version" to "audit-1",
        "manifestDigest" to "feeefe94c2accd81f4f4d87901dc0fe2d318bab5c073ff4fd38bed1b6aa584d8")
    private fun payload(text: String): Map<String, Any?> {
        val start = mapOf("textId" to "fr-01", "corpusVersion" to 1, "passageId" to "fr-01-p1", "offsetUtf16" to 0)
        return mapOf("text" to text, "voiceId" to "estelle", "bundleId" to "g0-candidate",
            "start" to start, "end" to start + ("offsetUtf16" to text.length))
    }
    private fun listen(messenger: Messenger) {
        lateinit var response: CompletableFuture<Any?>
        main { response = messenger.dispatch(SpeechPlugin.EVENT_CHANNEL, "listen", null) }
        response.get(5, TimeUnit.SECONDS)
    }
    private fun fails(code: String, future: CompletableFuture<Any?>) {
        try { future.get(5, TimeUnit.SECONDS); fail("Command unexpectedly succeeded") }
        catch (error: ExecutionException) {
            assertTrue(error.cause is FlutterException)
            assertEquals(code, (error.cause as FlutterException).code)
        }
    }
    @Test fun defaultBuildHasNoImplicitBundleAndRejectsInvalidMessages() {
        val plugin = SpeechPlugin()
        val messenger = Messenger()
        main { plugin.attach(messenger) }
        try {
            val capabilities = call(messenger, "capabilities").get(5, TimeUnit.SECONDS) as Map<*, *>
            assertEquals(emptyList<String>(), capabilities["languages"])
            assertEquals(emptyList<String>(), capabilities["voices"])
            fails("invalidMessage", call(messenger, "capabilities", wire("capabilities") + ("protocolVersion" to 2)))
            fails("invalidMessage", call(messenger, "capabilities", wire("capabilities") + ("path" to "/outside")))
            fails("invalidMessage", call(messenger, "cancel", wire("cancel", generation = 1) + ("generation" to 1.5)))
            fails("invalidMessage", call(messenger, "synthesize", wire("synthesize", payload("Été 🌱") +
                ("end" to mapOf("textId" to "fr-01", "corpusVersion" to 1, "passageId" to "fr-01-p1", "offsetUtf16" to 5)), 1)))
            fails("modelMissing", call(messenger, "loadBundle", wire("loadBundle", bundle)))
            call(messenger, "cancel", wire("cancel", generation = 1)).get(5, TimeUnit.SECONDS)
            call(messenger, "cancel", wire("cancel", generation = 1)).get(5, TimeUnit.SECONDS)
            call(messenger, "dispose").get(5, TimeUnit.SECONDS)
            call(messenger, "dispose").get(5, TimeUnit.SECONDS)
        } finally { main { plugin.detach() } }
        assertTrue(messenger.handlers.isEmpty())
    }
    @Test fun cancellationReturnsOriginalTokenWithoutLateCompletedEvent() {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var file: File? = null
        val engine = PocketSpeechEngine({ _, _ ->
            entered.countDown(); check(finish.await(10, TimeUnit.SECONDS))
            val output = File.createTempFile("bridge-test-", ".wav", context.cacheDir).also { it.writeBytes(byteArrayOf(1)); file = it }
            NativeAudio(output, 24000, 1, 1, 0, 0, 0)
        })
        val plugin = SpeechPlugin { _, _, _ -> engine }
        val messenger = Messenger()
        main { plugin.attach(messenger) }
        try {
            listen(messenger)
            call(messenger, "loadBundle", wire("loadBundle", bundle)).get(5, TimeUnit.SECONDS)
            val request = wire("synthesize", payload("Bonjour."), 7)
            val accepted = call(messenger, "synthesize", request).get(5, TimeUnit.SECONDS) as Map<*, *>
            assertEquals(true, accepted["accepted"])
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            call(messenger, "cancel", wire("cancel", generation = 7)).get(5, TimeUnit.SECONDS)
            finish.countDown()
            val event = messenger.events.poll(5, TimeUnit.SECONDS)!!
            assertEquals("cancelled", event["kind"])
            assertEquals(request["requestId"], event["requestId"])
            assertEquals("bridge-session", event["sessionId"])
            assertEquals(7L, (event["generation"] as Number).toLong())
            assertFalse(event.containsKey("output")); assertFalse(file!!.exists())
            fails("cancelled", call(messenger, "synthesize", wire("synthesize", payload("Bonjour."), 7)))
            call(messenger, "dispose").get(5, TimeUnit.SECONDS)
        } finally { finish.countDown(); main { plugin.detach() }; engine.dispose().get(5, TimeUnit.SECONDS) }
    }
    @Test(timeout = 180000) fun realCandidateGenerationCrossesCodecBoundaryWithOpaqueHandle() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val fixture = JSONObject(File(directory, "generation-fixtures.json").readText())
        val reference = fixture.getJSONArray("noise")
        val noise = FloatArray(reference.length()) { reference.getDouble(it).toFloat() }
        val synth = OnnxFrenchSynthesizer(directory)
        val engine = PocketSpeechEngine({ request, check -> synth.synthesize(request.text, check, noise) })
        // Test-only host resolver. The application registers the empty default resolver.
        val plugin = SpeechPlugin { id, version, digest ->
            if (id == bundle["bundleId"] && version == bundle["version"] && digest == bundle["manifestDigest"]) engine else null
        }
        val messenger = Messenger()
        main { plugin.attach(messenger) }
        try {
            listen(messenger)
            call(messenger, "loadBundle", wire("loadBundle", bundle)).get(5, TimeUnit.SECONDS)
            val text = fixture.getString("text")
            val request = wire("synthesize", payload(text), 1)
            call(messenger, "synthesize", request).get(5, TimeUnit.SECONDS)
            val event = messenger.events.poll(150, TimeUnit.SECONDS)!!
            assertEquals("completed", event["kind"])
            assertEquals(request["requestId"], event["requestId"])
            val output = event["output"] as Map<*, *>
            assertTrue(SpeechWireCommand.validId(output["audioHandle"]))
            assertEquals(24000, output["sampleRate"])
            assertEquals(138284L, (output["byteSize"] as Number).toLong())
            assertEquals("pcm16", output["encoding"])
            assertFalse(event.toString().contains(directory.path))
            assertFalse(event.containsKey("text"))
            engine.release(output["audioHandle"] as String)
            call(messenger, "dispose").get(10, TimeUnit.SECONDS)
            val report = JSONObject().put("status", "passed").put("transport", "real Flutter codec, in-memory messenger")
                .put("backend", "main-source ONNX on Samsung").put("applicationUsesEmptyResolver", true)
                .put("dartIsolateExecuted", false).put("g0", "not_demonstrated")
            val file = File(directory, "bridge-report-${System.currentTimeMillis()}.json")
            check(file.createNewFile()); file.writeText(report.toString(2))
        } finally { main { plugin.detach() }; engine.dispose().get(10, TimeUnit.SECONDS) }
    }

    @Test fun disposeWaitsForPendingLoadAndPreventsLateActivation() {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val closed = CountDownLatch(1)
        val candidate = PocketSpeechEngine({ _, _ -> error("Must not synthesize") }, { closed.countDown() })
        val plugin = SpeechPlugin { _, _, _ ->
            entered.countDown(); check(finish.await(10, TimeUnit.SECONDS)); candidate
        }
        val messenger = Messenger()
        main { plugin.attach(messenger) }
        try {
            val loading = call(messenger, "loadBundle", wire("loadBundle", bundle))
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val disposing = call(messenger, "dispose")
            assertFalse(disposing.isDone)
            assertEquals(1L, closed.count)
            finish.countDown()
            fails("cancelled", loading)
            disposing.get(5, TimeUnit.SECONDS)
            assertEquals(0L, closed.count)
            val caps = call(messenger, "capabilities").get(5, TimeUnit.SECONDS) as Map<*, *>
            assertEquals(emptyList<String>(), caps["languages"])
        } finally { finish.countDown(); main { plugin.detach() }; candidate.dispose().get(5, TimeUnit.SECONDS) }
    }
}
