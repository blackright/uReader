package com.ureader.prototype.epub

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.Charset
import java.text.Normalizer
import java.util.Locale

class EpubZipFailure(val code: String) : Exception(code)
internal fun zipRequire(condition: Boolean, code: String = "invalidArchive") {
    if (!condition) throw EpubZipFailure(code)
}
data class CheckedZipEntry internal constructor(val name: String, val compressed: Long,
    val size: Long, val crc: Long, val method: Int, internal val dataOffset: Long,
    internal val recordStart: Long, internal val recordEnd: Long)

/** All offsets, names and index budgets are checked BEFORE constructing ZipFile. */
object ZipIndexGate {
    const val SOURCE_LIMIT = 100L * 1024 * 1024
    const val ENTRY_LIMIT = 50L * 1024 * 1024
    const val TOTAL_LIMIT = 500L * 1024 * 1024
    const val RATIO = 100L
    private fun u16(b: ByteArray, p: Int): Int {
        zipRequire(p >= 0 && p + 2 <= b.size)
        return (b[p].toInt() and 255) or ((b[p+1].toInt() and 255) shl 8)
    }
    private fun u32(b: ByteArray, p: Int): Long = u16(b,p).toLong() or (u16(b,p+2).toLong() shl 16)
    private fun u64(b: ByteArray, p: Int): Long {
        val result = u32(b,p) or (u32(b,p+4) shl 32)
        zipRequire(result >= 0); return result
    }
    private fun bytes(file: RandomAccessFile, offset: Long, count: Int): ByteArray {
        zipRequire(count >= 0 && offset >= 0 && offset <= file.length() - count)
        val out = ByteArray(count); file.seek(offset); file.readFully(out); return out
    }
    private fun safeName(raw: ByteArray, utf8: Boolean): String {
        zipRequire(raw.isNotEmpty() && raw.size <= 1024, "limitExceeded")
        val decoder = Charset.forName(if (utf8) "UTF-8" else "CP437").newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        val name = try { decoder.decode(ByteBuffer.wrap(raw)).toString() } catch (_: Exception) { throw EpubZipFailure("invalidArchive") }
        zipRequire(name.toByteArray(Charsets.UTF_8).size<=1024,"limitExceeded")
        zipRequire(!name.startsWith('/') && !name.contains('\\') && !name.contains(':') &&
            name.none { it.code < 32 || it.code == 127 })
        val parts = name.removeSuffix("/").split('/')
        zipRequire(parts.all { it.isNotEmpty() && it != "." && it != ".." })
        return name
    }
    private fun zip64(extra: ByteArray, size: Long, compressed: Long, offset: Long): Triple<Long,Long,Long> {
        var p = 0; var found: ByteArray? = null
        while (p < extra.size) {
            zipRequire(p + 4 <= extra.size)
            val id = u16(extra,p); val length = u16(extra,p+2); p += 4
            zipRequire(p + length <= extra.size)
            if (id == 1) { zipRequire(found == null); found = extra.copyOfRange(p,p+length) }
            p += length
        }
        val required = size == 0xffffffffL || compressed == 0xffffffffL || offset == 0xffffffffL
        if (!required) return Triple(size,compressed,offset)
        val data = found ?: throw EpubZipFailure("invalidArchive")
        var cursor = 0
        fun next(value: Long): Long {
            if (value != 0xffffffffL) return value
            val result = u64(data,cursor); cursor += 8; return result
        }
        return Triple(next(size),next(compressed),next(offset))
    }
    fun inspect(source: File, cancelled: () -> Boolean = { false }): List<CheckedZipEntry> = RandomAccessFile(source,"r").use { file ->
        val started=System.nanoTime()
        fun checkpoint() {
            if(cancelled()) throw EpubZipFailure("cancelled")
            if(System.nanoTime()-started>120_000_000_000L) throw EpubZipFailure("deadlineExceeded")
        }
        checkpoint()
        val length = file.length()
        zipRequire(length<=SOURCE_LIMIT,"limitExceeded")
        zipRequire(length>=22)
        val tail = bytes(file,maxOf(0,length-65557), minOf(length,65557).toInt())
        val end = (tail.size-22 downTo 0).firstOrNull { p -> u32(tail,p)==0x06054b50L && p+22+u16(tail,p+20)==tail.size }
            ?: throw EpubZipFailure("invalidArchive")
        val eocd = length-tail.size+end
        zipRequire(u16(tail,end+4)==0 && u16(tail,end+6)==0)
        var count = u16(tail,end+10).toLong()
        zipRequire(u16(tail,end+8).toLong()==count)
        var directorySize = u32(tail,end+12); var directoryOffset = u32(tail,end+16)
        var directoryEnd = eocd
        if (count==65535L || directorySize==0xffffffffL || directoryOffset==0xffffffffL) {
            val locator = bytes(file,eocd-20,20)
            zipRequire(u32(locator,0)==0x07064b50L && u32(locator,4)==0L && u32(locator,16)==1L)
            val recordOffset = u64(locator,8); val record = bytes(file,recordOffset,56)
            val extensionSize = u64(record,4)
            zipRequire(u32(record,0)==0x06064b50L && extensionSize in 44..(8L*1024*1024))
            zipRequire(recordOffset + 12 + extensionSize == eocd-20)
            zipRequire(u32(record,16)==0L && u32(record,20)==0L && u64(record,24)==u64(record,32))
            count=u64(record,32); directorySize=u64(record,40); directoryOffset=u64(record,48); directoryEnd=recordOffset
        }
        zipRequire(count in 1..5000 && directorySize in 46..(8L*1024*1024),"limitExceeded")
        zipRequire(directoryOffset>=0 && directorySize<=directoryEnd && directoryOffset==directoryEnd-directorySize)
        val directory=bytes(file,directoryOffset,directorySize.toInt())
        val entries=ArrayList<CheckedZipEntry>(); val names=HashSet<String>()
        var p=0; var totalSize=0L; var totalCompressed=0L
        repeat(count.toInt()) {
            checkpoint()
            zipRequire(p+46<=directory.size && u32(directory,p)==0x02014b50L)
            val flags=u16(directory,p+8); val method=u16(directory,p+10)
            zipRequire(flags and (0x800 or 8 or 6).inv()==0 && (method==0 || method==8))
            zipRequire(method==8 || flags and 6==0)
            val crc=u32(directory,p+16); val nameSize=u16(directory,p+28)
            val extraSize=u16(directory,p+30); val commentSize=u16(directory,p+32)
            zipRequire(nameSize in 1..1024 && p.toLong()+46+nameSize+extraSize+commentSize<=directory.size)
            zipRequire(u16(directory,p+34)==0)
            val unixMode=(u32(directory,p+38) ushr 16).toInt() and 0xf000
            zipRequire(unixMode==0 || unixMode==0x8000 || unixMode==0x4000)
            val rawName=directory.copyOfRange(p+46,p+46+nameSize)
            val name=safeName(rawName,flags and 0x800!=0)
            zipRequire(names.add(Normalizer.normalize(name.removeSuffix("/"),Normalizer.Form.NFC).lowercase(Locale.ROOT)))
            val extra=directory.copyOfRange(p+46+nameSize,p+46+nameSize+extraSize)
            val (size,compressed,offset)=zip64(extra,u32(directory,p+24),u32(directory,p+20),u32(directory,p+42))
            zipRequire(size<=ENTRY_LIMIT && compressed<=SOURCE_LIMIT,"limitExceeded")
            zipRequire(size==0L || compressed>0 && size<=compressed*RATIO,"limitExceeded")
            if (name.endsWith('/')) zipRequire(size==0L)
            totalSize+=size; totalCompressed+=compressed
            zipRequire(totalSize<=TOTAL_LIMIT && totalSize<=maxOf(1,totalCompressed)*RATIO,"limitExceeded")
            zipRequire(offset<=directoryOffset-30)
            val local=bytes(file,offset,30)
            zipRequire(u32(local,0)==0x04034b50L && u16(local,6)==flags && u16(local,8)==method)
            val localNameSize=u16(local,26); val localExtraSize=u16(local,28)
            zipRequire(localNameSize==nameSize)
            zipRequire(bytes(file,offset+30,localNameSize).contentEquals(rawName))
            val dataOffset=offset+30+localNameSize+localExtraSize
            zipRequire(dataOffset<=directoryOffset && compressed<=directoryOffset-dataOffset)
            var recordEnd=dataOffset+compressed
            if (flags and 8==0) {
                val localExtra=bytes(file,offset+30+localNameSize,localExtraSize)
                val (localSize,localCompressed,_)=zip64(localExtra,u32(local,22),u32(local,18),0)
                zipRequire(localSize==size && localCompressed==compressed && u32(local,14)==crc)
            } else {
                zipRequire(recordEnd<=directoryOffset-12)
                val signature=bytes(file,recordEnd,4)
                if (u32(signature,0)==0x08074b50L) recordEnd+=4
                val large = u32(directory,p+20)==0xffffffffL || u32(directory,p+24)==0xffffffffL
                val descriptorSize=if (large) 20 else 12
                zipRequire(recordEnd<=directoryOffset-descriptorSize)
                val descriptor=bytes(file,recordEnd,descriptorSize)
                zipRequire(u32(descriptor,0)==crc &&
                    (if (large) u64(descriptor,4) else u32(descriptor,4))==compressed &&
                    (if (large) u64(descriptor,12) else u32(descriptor,8))==size)
                recordEnd+=descriptorSize
            }
            zipRequire(recordEnd<=directoryOffset)
            entries.add(CheckedZipEntry(name,compressed,size,crc,method,dataOffset,offset,recordEnd))
            p+=46+nameSize+extraSize+commentSize
        }
        zipRequire(p==directory.size)
        val ordered=entries.sortedBy { it.recordStart }
        zipRequire(ordered.first().recordStart==0L)
        ordered.zipWithNext().forEach { (a,b) -> zipRequire(a.recordEnd<=b.recordStart) }
        entries.toList()
    }
}
