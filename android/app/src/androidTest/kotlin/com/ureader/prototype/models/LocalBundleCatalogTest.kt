package com.ureader.prototype.models

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class LocalBundleCatalogTest {
    @Test fun safAllowsTheEmbeddedKokoroFilesAndRetainsPocketWithoutArbitraryPaths() {
        val names = LocalSourcePolicy.fileNames(InstrumentationRegistry.getInstrumentation().targetContext)
        assertTrue(names.containsAll(setOf("kokoro.onnx", "siwis.f32", "vocab.json", "espeak-data.zip", "tokenizer.json")))
        assertTrue(names.containsAll(setOf("flow_lm_main_int8.onnx", "estelle.f16", "manifest.json")))
        assertTrue(names.size <= 64)
        assertTrue(names.none { it.contains('/') || it.contains('\\') || it.contains("..") || it.endsWith(".epub") })
        assertFalse("user-book.epub" in names)
    }
}
