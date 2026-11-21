package com.ureader.prototype.epub

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import java.security.MessageDigest

class BoundedZipReaderTest {
    private fun archive(vararg contents: Pair<String, ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            contents.forEach { (name, bytes) -> zip.putNextEntry(ZipEntry(name)); zip.write(bytes); zip.closeEntry() }
        }
        return out.toByteArray()
    }
    private fun <T> withArchive(bytes: ByteArray, body: (File) -> T): T {
        val dir = InstrumentationRegistry.getInstrumentation().targetContext.cacheDir
        val file = File.createTempFile("epub-gate-", ".zip", dir)
        return try { file.writeBytes(bytes); body(file) } finally { file.delete() }
    }
    private fun refused(bytes: ByteArray) = withArchive(bytes) { file ->
        try { BoundedZipReader(file).use { reader -> reader.entries.forEach { reader.read(it) { _, _ -> } } }; fail("hostile archive accepted") }
        catch (expected: EpubZipFailure) { assertTrue(expected.code.isNotEmpty()) }
    }
    @Test fun streamsDataDescriptorEntriesWithActualCrc() {
        val bytes = "Bonjour Léa.".toByteArray()
        withArchive(archive("chapter.xhtml" to bytes)) { file ->
            BoundedZipReader(file).use { reader ->
                val sink = ByteArrayOutputStream()
                reader.read(reader.entries.single()) { chunk, count -> assertTrue(count <= 65536); sink.write(chunk, 0, count) }
                assertArrayEquals(bytes, sink.toByteArray())
            }
        }
    }
    @Test fun rejectsPathsBeforeOpeningSdkIndex() {
        for (name in listOf("../escape", "/absolute", "a\\b", "a/../b", "C:/escape")) {
            refused(archive(name to byteArrayOf(1)))
        }
    }
    @Test fun decodedLegacyNamesAlsoRespectUtf8ByteBudget() {
        val output=ByteArrayOutputStream()
        ZipOutputStream(output,java.nio.charset.Charset.forName("CP437")).use { zip ->
            zip.putNextEntry(ZipEntry("é".repeat(600)));zip.write(byteArrayOf(1));zip.closeEntry()
        }
        refused(output.toByteArray())
    }
    @Test fun tooShortContainerIsInvalidRatherThanOverQuota() {
        withArchive(byteArrayOf(1,2,3)) { file ->
            try { ZipIndexGate.inspect(file);fail("short container accepted") }
            catch(expected:EpubZipFailure) { assertEquals("invalidArchive",expected.code) }
        }
    }
    @Test fun rejectsCaseCollisionsAndExpansionBeforeWritingBeyondQuota() {
        refused(archive("a" to byteArrayOf(1), "A" to byteArrayOf(2)))
        refused(archive("bomb" to ByteArray(262144) { 65 }))
    }
    @Test fun rejectsTruncatedAndForgedOffsets() {
        val bytes = archive("a" to byteArrayOf(1,2,3))
        refused(bytes.copyOf(bytes.size - 12))
        val central = bytes.indices.first { it + 3 < bytes.size && bytes[it] == 0x50.toByte() && bytes[it+1] == 0x4b.toByte() && bytes[it+2] == 1.toByte() && bytes[it+3] == 2.toByte() }
        val forged = bytes.copyOf()
        repeat(4) { forged[central + 42 + it] = 0x7f }
        refused(forged)
    }
    @Test fun rejectsCrcMismatchAndEncryptedFlags() {
        val bytes = archive("a" to byteArrayOf(1,2,3))
        val central = bytes.indices.first { it + 3 < bytes.size && bytes[it+2] == 1.toByte() && bytes[it+3] == 2.toByte() && bytes[it] == 0x50.toByte() && bytes[it+1] == 0x4b.toByte() }
        val crc = bytes.copyOf(); crc[central + 16] = (crc[central + 16].toInt() xor 1).toByte(); refused(crc)
        val flags = bytes.copyOf(); flags[6] = (flags[6].toInt() or 1).toByte(); flags[central + 8] = (flags[central + 8].toInt() or 1).toByte(); refused(flags)
    }
    @Test fun cancellationPreventsSinkPublication() {
        withArchive(archive("a" to byteArrayOf(1,2,3))) { file ->
            var cancelled=false
            BoundedZipReader(file, cancelled = { cancelled }).use { reader ->
                cancelled=true
                var writes = 0
                try { reader.read(reader.entries.single()) { _, _ -> writes++ }; fail("cancelled request accepted") }
                catch (expected: EpubZipFailure) { assertEquals("cancelled", expected.code) }
                assertEquals(0, writes)
            }
        }
    }
    @Test fun cancellationAlsoStopsIndexBeforeSdkOpening() {
        withArchive(archive("a" to byteArrayOf(1))) { file ->
            try { ZipIndexGate.inspect(file) { true };fail("cancelled index accepted") }
            catch(expected:EpubZipFailure) { assertEquals("cancelled",expected.code) }
        }
    }
    @Test fun forgedActualOutputDoesNotReachSinkAndPoisonsReader() {
        val assets=InstrumentationRegistry.getInstrumentation().context.assets
        val bytes=assets.open("epub-gate/forged-real-output.epub").use { it.readBytes() }
        withArchive(bytes) { file -> BoundedZipReader(file).use { reader ->
            var published=0
            try { reader.read(reader.entries.single()) { _,n -> published+=n };fail("forged size accepted") }
            catch(expected:EpubZipFailure) { assertEquals("limitExceeded",expected.code) }
            assertEquals(0,published)
            try { reader.read(reader.entries.single()) { _,_ -> };fail("failed archive reused") }
            catch(expected:EpubZipFailure) { assertEquals("invalidHandle",expected.code) }
        } }
    }
    @Test fun preparedCorpusAndHostileArchivesMatchPinnedPolicies() {
        val assets=InstrumentationRegistry.getInstrumentation().context.assets
        val manifest=JSONArray(assets.open("epub-gate/manifest.json").bufferedReader().readText())
        assertEquals(27,manifest.length())
        for (i in 0 until manifest.length()) {
            val record=manifest.getJSONObject(i)
            val bytes=assets.open("epub-gate/"+record.getString("name")).use { it.readBytes() }
            val digest=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            assertEquals(record.getString("sha256"),digest)
            if (record.getBoolean("accepted")) {
                withArchive(bytes) { file -> BoundedZipReader(file).use { reader ->
                    reader.entries.forEach { entry -> reader.read(entry) { _, count -> assertTrue(count<=65536) } }
                } }
            } else {
                try { refused(bytes) }
                catch (failure:AssertionError) { throw AssertionError(record.getString("name")+": "+failure.message) }
            }
        }
    }
    @Test fun sourceLimitIsCheckedBeforeSdkIndexAllocation() {
        val file=File.createTempFile("epub-sparse-", ".zip", InstrumentationRegistry.getInstrumentation().targetContext.cacheDir)
        try {
            java.io.RandomAccessFile(file,"rw").use { it.setLength(ZipIndexGate.SOURCE_LIMIT+1) }
            try { ZipIndexGate.inspect(file); fail("source quota ignored") }
            catch (expected:EpubZipFailure) { assertEquals("limitExceeded",expected.code) }
        } finally { file.delete() }
    }
}
