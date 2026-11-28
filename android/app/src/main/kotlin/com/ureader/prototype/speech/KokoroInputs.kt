package com.ureader.prototype.speech

/** Reject unknown symbols rather than silently dropping part of a spoken word. */
internal object KokoroInputs {
    fun ids(phonemes: String, vocabulary: Map<String, Int>): LongArray {
        val symbols = phonemes.codePoints().toArray()
        require(symbols.size in 1..510) { "Kokoro context exceeded" }
        return longArrayOf(0) + symbols.map { code ->
            val symbol = String(Character.toChars(code))
            requireNotNull(vocabulary[symbol]) { "Unknown phoneme" }.toLong()
        }.toLongArray() + longArrayOf(0)
    }

    fun styleOffset(originalPhonemes: String): Int {
        val length = originalPhonemes.codePointCount(0, originalPhonemes.length)
        require(length in 1..510)
        return (length - 1) * 256
    }
}
