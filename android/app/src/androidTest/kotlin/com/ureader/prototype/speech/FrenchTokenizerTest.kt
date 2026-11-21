package com.ureader.prototype.speech

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest

class FrenchTokenizerTest {
    @Test fun matchesPinnedPythonReference() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.filesDir, "ureader-g0-probe")
        val model = File(directory, "tokenizer.json")
        val fixture = JSONObject(File(directory, "tokenizer-fixtures.json").readText())
        val digest = MessageDigest.getInstance("SHA-256").digest(model.readBytes())
            .joinToString("") { "%02x".format(it) }
        assertEquals(fixture.getString("tokenizerSha256"), digest)
        val tokenizer = FrenchUnigramTokenizer(model.readText())
        val cases = fixture.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val entry = cases.getJSONObject(i)
            val expected = entry.getJSONArray("ids")
            val actual = tokenizer.encode(entry.getString("text"))
            assertArrayEquals("Tokenizer case $i", IntArray(expected.length()) { expected.getInt(it) }, actual)
        }
        val report = JSONObject().put("cases", cases.length()).put("status", "passed")
            .put("tokenizerSha256", digest).put("reference", "tokenizers 0.22.2")
            .put("androidApi", android.os.Build.VERSION.SDK_INT).put("audioGenerated", false)
        val output = File(directory, "tokenizer-report-${System.currentTimeMillis()}.json")
        check(output.createNewFile())
        output.writeText(report.toString(2))
    }

    @Test fun sourceOffsetsRemainUtf16AndIdsMatchExistingEncoding() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val tokenizer = FrenchUnigramTokenizer(File(context.filesDir, "ureader-g0-probe/tokenizer.json").readText())
        for (text in listOf("Bonjour monde.", "À Noël, Émilie.", "e\u0301 😀 vingt-et-un")) {
            val encoded = tokenizer.encodeDetailed(text)
            assertArrayEquals(tokenizer.encode(text), encoded.ids)
            assertEquals(encoded.ids.size, encoded.offsets.size)
            for ((start, end) in encoded.offsets) {
                assertTrue(start in 0..text.length && end in start..text.length)
                if (start < text.length) assertFalse(Character.isLowSurrogate(text[start]))
                if (end < text.length) assertFalse(Character.isLowSurrogate(text[end]))
            }
            assertTrue(encoded.offsets.any { it.second == text.length })
        }
    }

    @Test fun rejectsUnsupportedConfigurationAndUnsafeInputs() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = File(context.filesDir, "ureader-g0-probe/tokenizer.json").readText()
        fun rejects(block: () -> Unit) {
            try { block(); fail("Invalid tokenizer input accepted") }
            catch (expected: IllegalArgumentException) { /* Expected fail-closed behavior. */ }
        }
        val config = JSONObject(model)
        config.getJSONObject("model").put("byte_fallback", false)
        rejects { FrenchUnigramTokenizer(config.toString()) }
        val tokenizer = FrenchUnigramTokenizer(model)
        for (text in listOf("<unk>", "a<s>b", "</s>", "<pad>", "\uD800", "\uDC00", "a".repeat(4097))) {
            rejects { tokenizer.encode(text) }
        }
    }
}
