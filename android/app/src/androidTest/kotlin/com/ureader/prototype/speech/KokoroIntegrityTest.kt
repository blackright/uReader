package com.ureader.prototype.speech

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class KokoroIntegrityTest {
    @Test fun rejectsAlteredModelBeforeCallingFrontendOrPublishingAudio() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = java.nio.file.Files.createTempDirectory(context.cacheDir.toPath(), "kokoro-integrity-").toFile()
        val output = File(root, "output").also { check(it.mkdir()) }
        val pins = linkedMapOf<String, Pair<Long, String>>()
        for (name in listOf("kokoro.onnx", "siwis.f32", "vocab.json")) {
            File(root, name).writeBytes(byteArrayOf(1))
            pins[name] = 1L to "0".repeat(64) // Deliberately mismatching fixture hash.
        }
        var frontendCalled = false
        try {
            try {
                OnnxKokoroSynthesizer(root, pins, output, {
                    frontendCalled = true
                    error("Altered model must never reach the frontend")
                }).close()
                fail("Altered model accepted")
            } catch (_: IllegalArgumentException) { }
            assertFalse(frontendCalled)
            assertTrue(output.listFiles()!!.isEmpty())
        } finally {
            require(root.canonicalFile.parentFile == context.cacheDir.canonicalFile)
            check(root.deleteRecursively())
        }
    }
}
