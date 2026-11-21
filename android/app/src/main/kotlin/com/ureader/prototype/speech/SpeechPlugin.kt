package com.ureader.prototype.speech

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors

/** Host-only resolver: the default build has no ready trusted bundle. Never resolves UI paths. */
internal class SpeechPlugin(
    private val resolveBundle: (String, String, String) -> PocketSpeechEngine? = { _, _, _ -> null }
) : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val loader = Executors.newSingleThreadExecutor()
    private var commands: MethodChannel? = null
    private var events: EventChannel? = null
    private var audioCommands: MethodChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var attached = false
    private var disposed = false
    private var loading = false
    private var loadCompletion: CompletableFuture<Unit>? = null
    private var epoch = 0L
    private var engine: PocketSpeechEngine? = null
    private var bundle: List<String>? = null
    private var active: SpeechWireCommand? = null
    private var disposal: CompletableFuture<Unit>? = null
    private val cancelled = HashMap<String, Long>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) = attach(binding.binaryMessenger)
    internal fun attach(messenger: BinaryMessenger) {
        check(!attached && !disposed)
        attached = true
        commands = MethodChannel(messenger, COMMAND_CHANNEL).also { it.setMethodCallHandler(this) }
        events = EventChannel(messenger, EVENT_CHANNEL).also { it.setStreamHandler(this) }
        audioCommands = MethodChannel(messenger, AUDIO_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result -> audioCommand(call, result) }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = detach()
    internal fun detach() {
        attached = false; disposed = true; epoch++
        sink = null
        commands?.setMethodCallHandler(null); events?.setStreamHandler(null)
        audioCommands?.setMethodCallHandler(null)
        engine?.dispose(); loader.shutdown()
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(arguments: Any?) {
        active?.token?.let { token ->
            cancelled[token.sessionId] = maxOf(cancelled[token.sessionId] ?: -1, token.generation)
            try { engine?.cancel(token) } catch (error: Exception) { /* Sink is invalidated below. */ }
        }
        sink = null
    }
    private fun error(result: MethodChannel.Result, code: String) {
        val message = when (code) {
            "invalidMessage" -> "Cette commande est invalide."
            "modelMissing" -> "Aucune ressource vocale utilisable n’est installée."
            "resourceInUse" -> "Cette ressource est utilisée. Arrêtez son utilisation."
            "cancelled" -> "Opération annulée."
            else -> "La synthèse vocale n’est pas encore disponible."
        }
        result.error(code, message, null)
    }
    private fun audioCommand(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "releaseBundle") {
            val args = call.arguments as? Map<*, *>
            if (args == null || args.keys != setOf("protocolVersion") || args["protocolVersion"] != 1 || loading || disposed) { error(result, "resourceInUse"); return }
            val owner = engine
            if (owner == null) { result.success(null); return }
            loading = true; epoch++
            owner.dispose().whenComplete { _, failure -> main.post {
                loading = false
                if (failure == null) { engine = null; bundle = null; active = null; result.success(null) }
                else error(result, "engineUnavailable")
            } }
            return
        }
        val owner = engine
        if (disposed || owner == null) { error(result, "engineUnavailable"); return }
        val args = call.arguments as? Map<*, *>
        val key = if (call.method == "tokenCount") "text" else "audioHandle"
        if (call.method !in setOf("readAudio", "releaseAudio", "tokenCount") || args == null ||
            args.keys != setOf("protocolVersion", key) || args["protocolVersion"] != 1 ||
            (key == "audioHandle" && !SpeechWireCommand.validId(args[key])) ||
            (key == "text" && (args[key] !is String || (args[key] as String).isBlank() || (args[key] as String).length > 4096))) {
            error(result, "invalidMessage"); return
        }
        if (call.method == "releaseAudio") { owner.release(args[key] as String); result.success(null); return }
        val currentEpoch = epoch
        val future: CompletableFuture<*> = if (call.method == "readAudio") owner.readAudio(args[key] as String)
            else owner.tokenCount(args[key] as String)
        future.whenComplete { value, failure -> main.post {
            if (attached) {
                if (failure != null || disposed || epoch != currentEpoch) error(result, "engineUnavailable")
                else result.success(value)
            }
        } }
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val command = try { SpeechWireCommand.parse(call.method, call.arguments) }
        catch (error: IllegalArgumentException) { error(result, "invalidMessage"); return }
        when (command.command) {
            "capabilities" -> result.success(mapOf("protocolVersion" to 1,
                "alignment" to mapOf("version" to 1, "available" to (engine?.alignmentAvailable == true && !disposed), "validated" to (engine?.alignmentValidated == true && !disposed)),
                "languages" to if (engine != null && !disposed) listOf("fr") else emptyList<String>(),
                "voices" to if (engine != null && !disposed) listOf("estelle") else emptyList<String>()))
            "loadBundle" -> load(command, result)
            "synthesize" -> synthesize(command, result)
            "cancel" -> {
                if (disposed) { result.success(null); return }
                val token = command.token!!
                if (!cancelled.containsKey(token.sessionId) && cancelled.size >= 256) {
                    error(result, "engineUnavailable"); return
                }
                cancelled[token.sessionId] = maxOf(cancelled[token.sessionId] ?: -1, token.generation)
                try { engine?.cancel(token); result.success(null) }
                catch (exception: Exception) { error(result, "engineUnavailable") }
            }
            "dispose" -> {
                disposed = true; epoch++
                val future = disposal ?: (loadCompletion ?: CompletableFuture.completedFuture(Unit)).thenCompose {
                    engine?.dispose() ?: CompletableFuture.completedFuture(Unit)
                }.also { disposal = it }
                future.whenComplete { _, failure -> main.post {
                    if (attached) {
                        if (failure == null) result.success(null) else error(result, "engineUnavailable")
                    }
                } }
            }
        }
    }
    private fun load(command: SpeechWireCommand, result: MethodChannel.Result) {
        if (disposed) { error(result, "engineUnavailable"); return }
        val requested = listOf("bundleId", "version", "manifestDigest").map { command.payload[it] as String }
        if (bundle == requested) { result.success(null); return }
        if (loading || engine != null) { error(result, "resourceInUse"); return }
        loading = true
        val completed = CompletableFuture<Unit>()
        loadCompletion = completed
        val loadEpoch = epoch
        loader.execute {
            var resolved: PocketSpeechEngine? = null
            var failure = false
            try { resolved = resolveBundle(requested[0], requested[1], requested[2]) }
            catch (error: Exception) { failure = true }
            val candidate = resolved
            val failed = failure
            main.post {
                loading = false
                if (!attached || disposed || loadEpoch != epoch) {
                    val cleanup = candidate?.dispose() ?: CompletableFuture.completedFuture(Unit)
                    cleanup.whenComplete { _, closeError -> main.post {
                        if (closeError == null) completed.complete(Unit) else completed.completeExceptionally(closeError)
                        if (attached) error(result, "cancelled")
                    } }
                } else if (candidate == null || failed) {
                    completed.complete(Unit)
                    error(result, if (failed) "engineUnavailable" else "modelMissing")
                } else {
                    engine = candidate; bundle = requested; completed.complete(Unit); result.success(null)
                }
            }
        }
    }
    private fun synthesize(command: SpeechWireCommand, result: MethodChannel.Result) {
        val owner = engine
        if (disposed || owner == null || sink == null) { error(result, "engineUnavailable"); return }
        if (active != null) { error(result, "resourceInUse"); return }
        if (command.payload["bundleId"] != bundle!![0] || command.payload["voiceId"] != "estelle") {
            error(result, "modelMissing"); return
        }
        val token = command.token!!
        if (token.generation <= (cancelled[token.sessionId] ?: -1)) { error(result, "cancelled"); return }
        val request = PocketSpeechEngine.Request(command.requestId, token,
            (command.payload["synthesisText"] ?: command.payload["text"]) as String)
        val future = try { owner.synthesize(request) }
        catch (failure: Exception) { error(result, "engineUnavailable"); return }
        active = command
        result.success(mapOf("accepted" to true))
        future.whenComplete { outcome, failure -> main.post {
            if (active === command) active = null
            val obsolete = disposed || sink == null || !attached ||
                token.generation <= (cancelled[token.sessionId] ?: -1)
            val event = mutableMapOf<String, Any?>("protocolVersion" to 1, "requestId" to command.requestId,
                "sessionId" to token.sessionId, "generation" to token.generation)
            if (outcome is PocketSpeechEngine.Outcome.Completed && !obsolete && failure == null) {
                val audio = outcome.audio
                event["kind"] = "completed"
                event["output"] = mapOf("audioHandle" to outcome.audioHandle, "sampleRate" to audio.sampleRate,
                    "channels" to 1, "encoding" to "pcm16", "durationMs" to audio.samples * 1000L / audio.sampleRate,
                    "timings" to audio.timings, "byteSize" to audio.file.length(), "start" to command.payload["start"], "end" to command.payload["end"]).let { metadata ->
                        if (owner.alignmentAvailable && audio.alignment != null) metadata + ("alignment" to audio.alignment)
                        else metadata
                    }
            } else {
                if (outcome is PocketSpeechEngine.Outcome.Completed) owner.release(outcome.audioHandle)
                event["kind"] = if (obsolete || outcome is PocketSpeechEngine.Outcome.Cancelled) "cancelled" else "failed"
                if (event["kind"] == "failed") event["errorCode"] = "engineUnavailable"
            }
            if (attached) sink?.success(event)
        } }
    }
    companion object {
        const val COMMAND_CHANNEL = "com.ureader.prototype/speech/v1"
        const val EVENT_CHANNEL = "com.ureader.prototype/speech_events/v1"
        const val AUDIO_CHANNEL = "com.ureader.prototype/audio/v1"
    }
}
