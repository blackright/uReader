package com.ureader.prototype.epub

import java.io.Closeable
import java.io.File
import java.io.RandomAccessFile
import java.nio.charset.Charset
import java.util.zip.CRC32
import java.util.zip.Inflater
import java.util.zip.ZipFile

/** Sequential worker-owned reader. No extraction, arbitrary output path or eager inflated buffer. */
class BoundedZipReader(source: File, private val cancelled: () -> Boolean = { false }) : Closeable {
    private val started=System.nanoTime()
    val entries=ZipIndexGate.inspect(source,cancelled)
    // Only bounded, independently checked indexes may reach the SDK's index allocator.
    private val sdk=try { ZipFile(source, Charset.forName("CP437")) }
        catch (_: Exception) { throw EpubZipFailure("invalidArchive") }
    private val file=try { RandomAccessFile(source,"r") } catch (error: Exception) { sdk.close(); throw EpubZipFailure("sourceUnavailable") }
    private var closed=false
    private var active=false
    private var failed=false
    private var totalOutput=0L
    private var totalInput=0L

    fun read(entry: CheckedZipEntry, sink: (ByteArray,Int) -> Unit) {
        zipRequire(!closed && !active && !failed && entries.any { it === entry },"invalidHandle")
        if (cancelled()) throw EpubZipFailure("cancelled")
        active=true
        val inflater=if (entry.method==8) Inflater(true) else null
        var completed=false
        try {
            val metadata=sdk.getEntry(entry.name) ?: throw EpubZipFailure("invalidArchive")
            zipRequire(metadata.size==entry.size && metadata.compressedSize==entry.compressed && metadata.crc==entry.crc && metadata.method==entry.method)
            val input=ByteArray(65536); val output=ByteArray(65536); val crc=CRC32()
            var supplied=0L; var produced=0L; var accountedInput=0L
            file.seek(entry.dataOffset)
            while (true) {
                if (cancelled()) throw EpubZipFailure("cancelled")
                if (System.nanoTime()-started>120_000_000_000L) throw EpubZipFailure("deadlineExceeded")
                val count: Int
                val consumed: Long
                if (inflater==null) {
                    if (supplied==entry.compressed) break
                    count=file.read(output,0,minOf(65536L,entry.compressed-supplied).toInt())
                    zipRequire(count>0); supplied+=count; consumed=supplied
                } else {
                    if (inflater.finished()) break
                    if (inflater.needsInput()) {
                        zipRequire(supplied<entry.compressed)
                        val n=file.read(input,0,minOf(65536L,entry.compressed-supplied).toInt())
                        zipRequire(n>0); supplied+=n; inflater.setInput(input,0,n)
                    }
                    count=try { inflater.inflate(output) } catch (_: Exception) { throw EpubZipFailure("invalidArchive") }
                    consumed=inflater.bytesRead
                    zipRequire(!inflater.needsDictionary() && (count>0 || inflater.finished() || inflater.needsInput()))
                }
                totalInput+=consumed-accountedInput; accountedInput=consumed
                // Verify actual output BEFORE publishing the next chunk to a staging sink.
                zipRequire(produced+count<=entry.size && produced+count<=ZipIndexGate.ENTRY_LIMIT &&
                    totalOutput+count<=ZipIndexGate.TOTAL_LIMIT &&
                    produced+count<=maxOf(1,consumed)*ZipIndexGate.RATIO &&
                    totalOutput+count<=maxOf(1,totalInput)*ZipIndexGate.RATIO,"limitExceeded")
                if (count>0) {
                    if (cancelled()) throw EpubZipFailure("cancelled")
                    crc.update(output,0,count); sink(output,count); produced+=count; totalOutput+=count
                }
            }
            val actualInput=inflater?.bytesRead ?: supplied
            zipRequire(actualInput==entry.compressed && produced==entry.size && crc.value==entry.crc)
            completed=true
        } finally { if(!completed) failed=true; inflater?.end(); active=false }
    }
    override fun close() {
        if (closed) return
        closed=true
        try { file.close() } finally { sdk.close() }
    }
}
