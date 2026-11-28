package com.ureader.prototype.speech

import java.io.File

/** Compatible Misaki/eSpeak frontend candidate; parity must be verified before activation. */
internal class FrenchPhonemizer(private val dataParent: File) : AutoCloseable {
    private var closed = false
    init {
        require(dataParent.canonicalFile == dataParent.absoluteFile)
        require(File(dataParent, "espeak-ng-data").isDirectory)
        synchronized(gate) {
            check(!owned) { "French frontend already owned" }
            System.loadLibrary("ureader_french")
            owned = true
        }
    }

    internal fun original(text: String): String = synchronized(gate) {
        check(!closed)
        require(text.isNotBlank() && text.length <= 4096 && '\u0000' !in text)
        val transformed = text.replace('«', '“').replace('»', '”').replace('(', '«').replace(')', '»')
        val output = StringBuilder()
        var cursor = 0
        for (mark in punctuation.findAll(transformed)) {
            val part = transformed.substring(cursor, mark.range.first).trim()
            if (part.isNotEmpty()) output.append(convert(nativePhonemes(dataParent.path, part.toByteArray(Charsets.UTF_8))))
            output.append(mark.value)
            cursor = mark.range.last + 1
        }
        val tail = transformed.substring(cursor).trim()
        if (tail.isNotEmpty()) output.append(convert(nativePhonemes(dataParent.path, tail.toByteArray(Charsets.UTF_8))))
        output.toString().trim().replace('«', '(').replace('»', ')')
    }

    fun phonemize(text: String): OnnxKokoroSynthesizer.Phones = synchronized(gate) {
        val original = original(text)
        var corrected = original
        for ((word, before, after) in patches) {
            val count = Regex("(?<![\\p{L}\\p{N}_])${Regex.escape(word)}(?![\\p{L}\\p{N}_])", RegexOption.IGNORE_CASE)
                .findAll(text).count()
            if (count == 0) continue
            require(Regex(Regex.escape(before)).findAll(corrected).count() == count) { "Ambiguous pronunciation correction" }
            corrected = corrected.replace(before, after)
        }
        OnnxKokoroSynthesizer.Phones(original, corrected)
    }

    private fun convert(raw: String): String {
        var phones = raw.trim().replace('\n', ' ').replace("  ", " ")
            .replace(Regex("_+"), "_").replace("_ ", " ")
            .replace(Regex("\\([^)]*\\)"), "").replace('͡', '^')
        for ((before, after) in replacements) phones = phones.replace(before, after)
        return phones.replace("^", "").replace("-", "").trim()
    }

    private external fun nativePhonemes(directory: String, input: ByteArray): String
    private external fun nativeClose()
    override fun close() = synchronized(gate) {
        if (!closed) {
            nativeClose()
            closed = true
            owned = false
        }
    }

    companion object {
        private val gate = Any()
        private var owned = false
        private val punctuation = Regex("(\\s*[;:,.!?¡¿—…\"«»“”(){}\\[\\]]+\\s*)+")
        private val replacements = sortedMapOf("a^ɪ" to "I", "a^ʊ" to "W", "d^z" to "ʣ", "d^ʒ" to "ʤ",
            "e^ɪ" to "A", "o^ʊ" to "O", "ə^ʊ" to "Q", "s^s" to "S", "t^s" to "ʦ", "t^ʃ" to "ʧ", "ɔ^ɪ" to "Y")
        private val patches = listOf(Triple("gentleman", "ʒɑ̃tlmˈɑ̃", "ʤɛntləman"),
            Triple("authentiques", "ɔːθəntˈiːks", "otɑ̃tˈik"),
            Triple("enthousiastes", "ɛnθˈWziˌasts", "ɑ̃tuzjˈast"),
            Triple("rocking-chairs", "ɹˈɒkɪŋʃˈɛʁ", "ʁɔkiŋʃˈɛʁ"))
    }
}
