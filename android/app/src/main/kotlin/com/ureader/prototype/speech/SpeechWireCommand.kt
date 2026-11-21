package com.ureader.prototype.speech

/** Strict counterpart of speech_messages.dart v1. Never accepts a caller-provided path. */
internal data class SpeechWireCommand(val command: String, val requestId: String,
    val token: PocketSpeechEngine.Token?, val payload: Map<String, Any?>) {
    companion object {
        private val commands = setOf("capabilities", "loadBundle", "synthesize", "cancel", "dispose")
        fun validId(value: Any?): Boolean = value is String &&
            Regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$").matches(value) &&
            !value.contains("..") && !value.endsWith('.')
        private fun integer(value: Any?): Long {
            require(value is Int || value is Long)
            return (value as Number).toLong().also { require(it >= 0) }
        }
        private fun locator(value: Any?): Map<String, Any?> {
            require(value is Map<*, *> && value.keys == setOf("textId", "corpusVersion", "passageId", "offsetUtf16"))
            require(validId(value["textId"]) && validId(value["passageId"]))
            require(integer(value["corpusVersion"]) in 1..Int.MAX_VALUE.toLong())
            require(integer(value["offsetUtf16"]) <= Int.MAX_VALUE)
            return value.entries.associate { it.key as String to it.value }
        }
        fun parse(method: String, arguments: Any?): SpeechWireCommand {
            require(method in commands && arguments is Map<*, *>)
            val allowed = setOf("protocolVersion", "command", "requestId", "sessionId", "generation", "payload")
            require(arguments.keys.all { it in allowed })
            require(arguments["protocolVersion"] == 1 && arguments["command"] == method && validId(arguments["requestId"]))
            require(arguments.containsKey("sessionId") == arguments.containsKey("generation"))
            val token = if (arguments.containsKey("sessionId")) {
                require(validId(arguments["sessionId"]))
                PocketSpeechEngine.Token(arguments["sessionId"] as String, integer(arguments["generation"]))
            } else null
            if (method in setOf("synthesize", "cancel")) require(token != null)
            val raw = arguments["payload"]
            require(raw is Map<*, *>)
            val keys = when (method) {
                "loadBundle" -> setOf("bundleId", "version", "manifestDigest")
                "synthesize" -> setOf("text", "voiceId", "bundleId", "start", "end")
                else -> emptySet()
            }
            require(raw.keys == keys || (method == "synthesize" && raw.keys == keys + "synthesisText"))
            val payload = raw.entries.associate { it.key as String to it.value }.toMutableMap()
            if (method == "loadBundle") {
                require(validId(raw["bundleId"]) && validId(raw["version"]))
                require(raw["manifestDigest"] is String && Regex("^[a-f0-9]{64}$").matches(raw["manifestDigest"] as String))
            }
            if (method == "synthesize") {
                if (raw.containsKey("synthesisText")) {
                    val prepared = raw["synthesisText"]
                    require(prepared is String && prepared.isNotBlank() && prepared.length <= 4096)
                }
                val text = raw["text"]
                require(text is String && text.isNotBlank() && text.length <= 4096)
                require(validId(raw["voiceId"]) && validId(raw["bundleId"]))
                val start = locator(raw["start"]); val end = locator(raw["end"])
                require(listOf("textId", "corpusVersion", "passageId").all { start[it] == end[it] })
                val first = integer(start["offsetUtf16"]); val last = integer(end["offsetUtf16"])
                require(last > first && last - first == text.length.toLong())
                payload["start"] = start; payload["end"] = end
            }
            return SpeechWireCommand(method, arguments["requestId"] as String, token, payload.toMap())
        }
    }
}
