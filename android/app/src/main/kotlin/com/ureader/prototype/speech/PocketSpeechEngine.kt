package com.ureader.prototype.speech

import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Serial native owner. Loading/inference/cleanup never run on the caller's UI thread.
 * The host qualifies a trusted bundle (G0, or an explicit debug native probe)
 * before exposing Flutter capabilities. This owner never selects a substitute voice.
 */
internal class PocketSpeechEngine(
    private val backend: (Request, () -> Unit) -> NativeAudio,
    private val closeBackend: () -> Unit = {},
    private val tokenCounter: ((String) -> Int)? = null,
    val alignmentAvailable: Boolean = false,
    val alignmentValidated: Boolean = false,
    val voiceId: String = "estelle"
) {
    init { require(validId(voiceId)) }
    data class Token(val sessionId: String, val generation: Long) {
        init { require(validId(sessionId) && generation >= 0) }
    }
    data class Request(val requestId: String, val token: Token, val text: String) {
        init { require(validId(requestId) && text.isNotBlank() && text.length <= 4096) }
    }
    sealed class Outcome {
        data class Completed(val request: Request, val audioHandle: String, val audio: NativeAudio) : Outcome()
        data class Cancelled(val request: Request) : Outcome()
        data class Failed(val request: Request) : Outcome()
    }
    private class Work(val request: Request) {
        val cancelled = AtomicBoolean(false)
        val result = CompletableFuture<Outcome>()
    }
    private val gate = Any()
    private val worker = Executors.newSingleThreadExecutor()
    private var active: Work? = null
    private var disposed = false
    private var disposal: CompletableFuture<Unit>? = null
    private val latest = HashMap<String, Long>()
    private val cancelledThrough = HashMap<String, Long>()
    private val outputs = HashMap<String, Pair<Token, NativeAudio>>()

    private fun <T> onWorker(action: () -> T): CompletableFuture<T> = synchronized(gate) {
        val result = CompletableFuture<T>()
        if (disposed) { result.completeExceptionally(IllegalStateException("Engine disposed")); return@synchronized result }
        worker.execute {
            try { result.complete(action()) } catch (error: Exception) { result.completeExceptionally(error) }
        }
        result
    }

    fun tokenCount(text: String): CompletableFuture<Int> = onWorker {
        require(text.isNotBlank() && text.length <= 4096)
        checkNotNull(tokenCounter)(text)
    }

    fun readAudio(handle: String): CompletableFuture<ByteArray> = onWorker {
        synchronized(gate) {
            check(!disposed)
            val audio = checkNotNull(outputs[handle]).second
            require(audio.file.length() in 46..960044)
            audio.file.readBytes().also { require(it.size.toLong() == 44L + audio.samples * 2L) }
        }
    }

    fun synthesize(request: Request): CompletableFuture<Outcome> = synchronized(gate) {
        check(!disposed) { "Speech engine disposed" }
        check(active == null) { "Speech engine busy" }
        require(latest.containsKey(request.token.sessionId) || latest.size < 256) { "Session limit" }
        require(request.token.generation >= (latest[request.token.sessionId] ?: -1)) { "Stale generation" }
        require(request.token.generation > (cancelledThrough[request.token.sessionId] ?: -1)) { "Cancelled generation" }
        check(outputs.size < 4) { "Unreleased audio limit" }
        latest[request.token.sessionId] = request.token.generation
        val work = Work(request)
        active = work
        worker.execute {
            var produced: NativeAudio? = null
            try {
                fun checkActive() {
                    if (work.cancelled.get() || Thread.currentThread().isInterrupted) throw CancellationException()
                }
                checkActive()
                val audio = backend(request, ::checkActive)
                produced = audio
                synchronized(gate) {
                    val outcome = if (disposed || work.cancelled.get() ||
                        latest[request.token.sessionId] != request.token.generation) {
                        audio.file.delete()
                        Outcome.Cancelled(request)
                    } else {
                        val handle = java.util.UUID.randomUUID().toString()
                        outputs[handle] = request.token to audio
                        Outcome.Completed(request, handle, audio)
                    }
                    active = null
                    work.result.complete(outcome)
                }
            } catch (error: Exception) {
                produced?.file?.delete()
                synchronized(gate) {
                    active = null
                    work.result.complete(if (work.cancelled.get() || error is CancellationException)
                        Outcome.Cancelled(request) else Outcome.Failed(request))
                }
            }
        }
        work.result
    }

    fun cancel(token: Token) = synchronized(gate) {
        if (disposed) return@synchronized
        require(cancelledThrough.containsKey(token.sessionId) || cancelledThrough.size < 256)
        cancelledThrough[token.sessionId] = maxOf(cancelledThrough[token.sessionId] ?: -1, token.generation)
        active?.takeIf { it.request.token.sessionId == token.sessionId &&
            it.request.token.generation <= token.generation }?.cancelled?.set(true)
        val obsolete = outputs.filterValues { it.first.sessionId == token.sessionId && it.first.generation <= token.generation }.keys
        for (handle in obsolete) outputs.remove(handle)?.second?.file?.delete()
    }

    fun release(audioHandle: String) = synchronized(gate) {
        outputs.remove(audioHandle)?.second?.file?.delete()
        Unit
    }

    fun dispose(): CompletableFuture<Unit> = synchronized(gate) {
        disposal?.let { return@synchronized it }
        disposed = true
        active?.cancelled?.set(true)
        val result = CompletableFuture<Unit>()
        disposal = result
        worker.execute {
            var failure: Exception? = null
            try {
                closeBackend()
            } catch (error: Exception) { failure = error }
            try {
                synchronized(gate) {
                    for (entry in outputs.values) {
                        val file = entry.second.file
                        check(!file.exists() || file.delete()) { "Audio cleanup failed" }
                    }
                    outputs.clear(); latest.clear(); cancelledThrough.clear()
                }
            } catch (error: Exception) { if (failure == null) failure = error else failure.addSuppressed(error) }
            val error = failure
            if (error == null) result.complete(Unit) else result.completeExceptionally(error)
        }
        worker.shutdown()
        result
    }

    companion object {
        private fun validId(value: String) = Regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$").matches(value) &&
            !value.contains("..") && !value.endsWith('.')
    }
}
