package com.ureader.prototype.speech

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class KokoroFrontendDataTest {
    private val required = listOf("phontab", "phondata", "phonindex", "fr_dict", "lang/roa/fr")
    private fun run(body: (File, File) -> Unit) {
        val root = Files.createTempDirectory("kokoro-data-test-").toFile().canonicalFile
        try { body(root, File(root, "data.zip")) } finally { root.deleteRecursively() }
    }
    private fun archive(file: File, extra: String? = null) {
        ZipOutputStream(file.outputStream()).use { zip ->
            for (name in required.map { "espeak-ng-data/$it" } + listOfNotNull(extra)) {
                zip.putNextEntry(ZipEntry(name)); zip.write(byteArrayOf(1, 2, 3)); zip.closeEntry()
            }
        }
    }
    private fun sha(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes())
        .joinToString("") { "%02x".format(it) }

    @Test fun extractsAndRevalidatesTheSameTrustedData() = run { root, zip ->
        archive(zip, "espeak-ng-data/voices/!v/Mr serious")
        val result = KokoroFrontendData.prepare(zip, root, sha(zip))
        assertTrue(File(result, "espeak-ng-data/lang/roa/fr").isFile)
        assertEquals(result, KokoroFrontendData.prepare(zip, root, sha(zip)))
    }
    @Test(expected = IllegalArgumentException::class) fun refusesChangedArchive() = run { root, zip ->
        archive(zip); KokoroFrontendData.prepare(zip, root, "0".repeat(64))
    }
    @Test fun rejectsTraversalWithoutPublishingOrLeavingStaging() = run { root, zip ->
        archive(zip, "espeak-ng-data/../../escape")
        try { KokoroFrontendData.prepare(zip, root, sha(zip)); fail("Traversal accepted") }
        catch (_: IllegalArgumentException) { }
        assertEquals(listOf("data.zip"), root.listFiles()!!.map { it.name })
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsChangedExtractedData() = run { root, zip ->
        archive(zip)
        val ready = KokoroFrontendData.prepare(zip, root, sha(zip))
        File(ready, "espeak-ng-data/fr_dict").writeBytes(byteArrayOf(9))
        KokoroFrontendData.prepare(zip, root, sha(zip))
    }
    @Test fun refusesIncompleteDataWithoutPublishing() = run { root, zip ->
        ZipOutputStream(zip.outputStream()).use { stream ->
            stream.putNextEntry(ZipEntry("espeak-ng-data/fr_dict")); stream.write(1); stream.closeEntry()
        }
        try { KokoroFrontendData.prepare(zip, root, sha(zip)); fail("Missing data accepted") }
        catch (_: IllegalArgumentException) { }
        assertEquals(listOf("data.zip"), root.listFiles()!!.map { it.name })
    }
    @Test fun rejectsBackslashPaths() = run { root, zip ->
        archive(zip, "espeak-ng-data/voices\\outside")
        try { KokoroFrontendData.prepare(zip, root, sha(zip)); fail("Backslash accepted") }
        catch (_: IllegalArgumentException) { }
        assertEquals(listOf("data.zip"), root.listFiles()!!.map { it.name })
    }
    @Test fun releasesOnlyItsOwnDerivedDirectory() = run { root, zip ->
        archive(zip)
        val digest = sha(zip)
        val ready = KokoroFrontendData.prepare(zip, root, digest)
        KokoroFrontendData.release(ready, root, digest)
        assertFalse(ready.exists())
        assertTrue(zip.isFile)
        try { KokoroFrontendData.release(root, root, digest); fail("Parent deletion accepted") }
        catch (_: IllegalArgumentException) { }
        assertTrue(root.isDirectory)
    }
}
