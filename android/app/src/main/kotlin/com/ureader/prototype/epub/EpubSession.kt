package com.ureader.prototype.epub

import java.io.*
import java.nio.file.Files
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal data class EpubRequest(val request:String,val operation:String,val generation:Long,val payload:Map<*,*>) {
 companion object {
  private val id=Regex("[A-Za-z0-9_-]{1,128}")

  fun failure(raw:Any?,code:String):Map<String,Any?> {
   val m=raw as? Map<*,*>
   fun safeId(name:String):String?=(m?.get(name) as? String)?.takeIf{id.matches(it)}
   val version=m?.get("protocolVersion");val generation=m?.get("generation")
   return mapOf("protocolVersion" to (when(version){is Int->version;is Long->version;else->1}),
    "requestId" to safeId("requestId"),"operationId" to safeId("operationId"),
    "generation" to (when(generation){is Int->generation;is Long->generation;else->null}),
    "error" to mapOf("code" to code))
  }
  fun parse(raw:Any?):EpubRequest {
   val m=raw as? Map<*,*> ?: throw EpubZipFailure("invalidRequest")
   fun integer(x:Any?):Long? = when(x){is Int->x.toLong();is Long->x;else->null}
   val version=integer(m["protocolVersion"]) ?: throw EpubZipFailure("invalidRequest")
   if(version!=1L)throw EpubZipFailure("unsupportedProtocol")
   val request=m["requestId"] as? String ?: throw EpubZipFailure("invalidRequest")
   val operation=m["operationId"] as? String ?: throw EpubZipFailure("invalidRequest")
   val generation=integer(m["generation"]) ?: throw EpubZipFailure("invalidRequest")
   if(!id.matches(request)||!id.matches(operation)||generation<=0)throw EpubZipFailure("invalidRequest")
   return EpubRequest(request,operation,generation,m["payload"] as? Map<*,*> ?: throw EpubZipFailure("invalidRequest"))
  }
 }
 fun string(key:String,limit:Int=4096,allowEmpty:Boolean=false):String=(payload[key] as? String)?.takeIf {(allowEmpty||it.isNotEmpty())&&it.length<=limit} ?: throw EpubZipFailure("invalidRequest")
 fun count(key:String,max:Long):Int {
  val n=when(val value=payload[key]){is Int->value.toLong();is Long->value;else->throw EpubZipFailure("invalidRequest")}
  if(n !in 1..max)throw EpubZipFailure("invalidRequest")
  return n.toInt()
 }

 fun validatePayload(method:String) {
  val allowed=when(method){
   "chooseDocument","openArchive","cancel"->emptySet()
   "readSource"->setOf("sourceHandle","maxBytes")
   "listEntries"->setOf("archiveHandle","cursor","pageSize")
   "readEntry"->setOf("archiveHandle","entryHandle","maxBytes")
   "close"->setOf("handle")
   "normalizeSearchKey"->setOf("text")
   "openExternal"->setOf("url","userConfirmed") // Reserved activation in phase 4.
   else->throw EpubZipFailure("invalidRequest")
  }
  if(payload.keys.any{it !in allowed})throw EpubZipFailure("invalidRequest")
  when(method){
   "readSource"->{string("sourceHandle",256);count("maxBytes",65536)}
   "listEntries"->{string("archiveHandle",256);count("pageSize",128);if(payload["cursor"]!=null)string("cursor",256)}
   "readEntry"->{string("archiveHandle",256);string("entryHandle",256);count("maxBytes",65536)}
   "close"->string("handle",256)
   "normalizeSearchKey"->string("text",16384,true)
   "openExternal"->{string("url",16384);if(payload["userConfirmed"]!=true)throw EpubZipFailure("invalidRequest")}
  }
 }
 fun envelope(value:Map<String,Any?>?=null,error:String?=null):Map<String,Any?> = mapOf("protocolVersion" to 1,"requestId" to request,"operationId" to operation,"generation" to generation)+if(error==null)mapOf("result" to value)else mapOf("error" to mapOf("code" to error))
}

/** Process-local session, never registered globally. Single consumer of each source.
 * Entry producer has only two chunks of backpressure; all declared and real ZIP
 * limits/CRC remain owned by BoundedZipReader. Files use generated names only. */
internal class EpubSession(private val root:File,val operation:String,val generation:Long) {
 val cancelled=AtomicBoolean(false)
 @Volatile var cancellationCode="cancelled"
  private set
 @Synchronized fun invalidate(code:String="cancelled"){if(!cancelled.get()){cancellationCode=code;cancelled.set(true)}}
 fun expire()=invalidate("sourceUnavailable")
 @Volatile private var input:InputStream?=null
 private var output:FileOutputStream?=null
 private var sourceHandle:String?=null
 private var sourceTotal=0L
 private var sourceEof=false
 private val closed=mutableSetOf<String>()
 private var archive:BoundedZipReader?=null
 private var archiveHandle:String?=null
 private var entries=emptyMap<String,CheckedZipEntry>()
 private val cursors=mutableMapOf<String,Int>()
 private var active:EntryStream?=null
 private val finished=mutableMapOf<String,Long>()
 private fun id()=UUID.randomUUID().toString()
 private fun check(){if(cancelled.get())throw EpubZipFailure(cancellationCode)}
 private fun source(part:Boolean=false):File {
  if(!Regex("[A-Za-z0-9_-]{1,128}").matches(operation))throw EpubZipFailure("invalidRequest")
  if(!root.exists())root.mkdirs()
  val canonical=root.canonicalFile
  if(Files.isSymbolicLink(root.toPath())||!root.isDirectory)throw EpubZipFailure("unsafeContent")
  var current=root
  for(segment in listOf("book-staging",operation)) {
   current=File(current,segment)
   if(Files.isSymbolicLink(current.toPath())||current.exists()&&!current.isDirectory)throw EpubZipFailure("unsafeContent")
   if(!current.exists()&&!current.mkdir())throw EpubZipFailure("storageUnavailable")
   if(!current.canonicalPath.startsWith(canonical.path+File.separator))throw EpubZipFailure("unsafeContent")
  }
  val file=File(current,if(part)"source.part" else "source")
  if(Files.isSymbolicLink(file.toPath()))throw EpubZipFailure("unsafeContent")
  return file
 }
 fun select(stream:InputStream):String {
  check();if(sourceHandle!=null)throw EpubZipFailure("operationInProgress")
  try {
   val part=source(true)
   if(source().exists()||!part.createNewFile())throw EpubZipFailure("storageUnavailable")
   output=try{FileOutputStream(part)}catch(e:Exception){throw epubStorageFailure(e)};input=stream
   val h=id();sourceHandle=h;check();return h
  }catch(e:Exception){abortSource();stream.close();throw e}
 }
 fun readSource(handle:String,max:Int):Map<String,Any?> {
  check();if(handle!=sourceHandle||closed.contains(handle))throw EpubZipFailure("invalidHandle")
  if(max !in 1..65536)throw EpubZipFailure("invalidRequest")
  if(sourceEof)return mapOf("bytes" to ByteArray(0),"eof" to true,"totalBytes" to sourceTotal)
  try {
   val buffer=ByteArray(max);val n=input?.read(buffer) ?: throw EpubZipFailure("sourceUnavailable")
   check()
   if(n==0)throw EpubZipFailure("sourceUnavailable")
   if(n<0){
    input?.close();input=null;try{output?.fd?.sync();output?.close()}catch(e:Exception){throw epubStorageFailure(e)};output=null
    check();val part=source(true);val file=source()
    if(file.exists()||!part.renameTo(file))throw EpubZipFailure("storageUnavailable")
    sourceEof=true
    return mapOf("bytes" to ByteArray(0),"eof" to true,"totalBytes" to sourceTotal)
   }
   if(sourceTotal+n>ZipIndexGate.SOURCE_LIMIT)throw EpubZipFailure("limitExceeded")
   try{output?.write(buffer,0,n) ?: throw EpubZipFailure("storageUnavailable")}catch(e:Exception){throw epubStorageFailure(e)}
   sourceTotal+=n
   return mapOf("bytes" to buffer.copyOf(n),"eof" to false,"totalBytes" to sourceTotal)
  }catch(e:Exception){abortSource();if(cancelled.get())throw EpubZipFailure(cancellationCode);if(e is EpubZipFailure)throw e;throw EpubZipFailure("sourceUnavailable")}
 }
 fun openArchive():Map<String,Any?> {
  check();if(!sourceEof||archive!=null)throw EpubZipFailure("invalidRequest")
  val reader=BoundedZipReader(source()){cancelled.get()}
  archive=reader;archiveHandle=id();entries=reader.entries.associateBy {id()}
  return mapOf("archiveHandle" to archiveHandle,"entryCount" to entries.size.toLong())
 }
 fun listEntries(handle:String,cursor:String?,pageSize:Int):Map<String,Any?> {
  checkArchive(handle)
  val start=if(cursor==null)0 else cursors[cursor] ?: throw EpubZipFailure("invalidHandle")
  if(pageSize !in 1..128)throw EpubZipFailure("invalidRequest")
  val page=entries.entries.drop(start).take(pageSize)
  val end=start+page.size;val next=if(end>=entries.size)null else cursors.entries.firstOrNull {it.value==end}?.key ?: id().also {cursors[it]=end}
  return mapOf("entries" to page.map {(h,e)->mapOf("entryHandle" to h,"logicalName" to e.name,"compressedBytes" to e.compressed,"declaredBytes" to e.size,"directory" to e.name.endsWith('/'))},"nextCursor" to next,"done" to (next==null))
 }
 private fun checkArchive(handle:String){check();if(handle!=archiveHandle||closed.contains(handle)||archive==null)throw EpubZipFailure("invalidHandle")}
 private class EntryStream(val handle:String) {
  val queue=ArrayBlockingQueue<Any>(2);val stop=AtomicBoolean(false)
  var total=0L;var pending=ByteArray(0);var offset=0
  lateinit var thread:Thread
 }
 fun readEntry(handle:String,entry:String,max:Int):Map<String,Any?> {
  checkArchive(handle);if(max !in 1..65536)throw EpubZipFailure("invalidRequest")
  val metadata=entries[entry] ?: throw EpubZipFailure("invalidHandle")
  finished[entry]?.let{return mapOf("bytes" to ByteArray(0),"eof" to true,"totalBytes" to it)}
  var current=active
  if(current==null){
   current=EntryStream(entry);val stream=current;val reader=archive!!
   fun send(value:Any){while(!stream.queue.offer(value,100,TimeUnit.MILLISECONDS)){if(cancelled.get()||stream.stop.get())throw EpubZipFailure("cancelled")}}
   stream.thread=Thread({try {reader.read(metadata){b,n->if(stream.stop.get())throw EpubZipFailure("cancelled");send(b.copyOf(n))};send(true)}catch(e:Exception){if(!stream.stop.get()&&!cancelled.get())runCatching{send(if(e is EpubZipFailure)e else EpubZipFailure("invalidArchive"))}}},"ureader-epub-entry")
   active=stream;stream.thread.start()
  }
  if(current.handle!=entry)throw EpubZipFailure("operationInProgress")
  if(current.offset==current.pending.size){
   val value=current.queue.poll(30,TimeUnit.SECONDS) ?: throw EpubZipFailure("sourceUnavailable")
   check()
   when(value){
    is EpubZipFailure->throw value
    is Boolean->{finished[entry]=current.total;current.thread.join();active=null;return mapOf("bytes" to ByteArray(0),"eof" to true,"totalBytes" to current.total)}
    is ByteArray->{current.pending=value;current.offset=0}
   }
  }
  val end=minOf(current.offset+max,current.pending.size);val bytes=current.pending.copyOfRange(current.offset,end);current.offset=end;current.total+=bytes.size
  return mapOf("bytes" to bytes,"eof" to false,"totalBytes" to current.total)
 }
 private fun stopEntry(){val stream=active ?: return;stream.stop.set(true);stream.thread.interrupt();stream.thread.join(2000);if(stream.thread.isAlive)throw EpubZipFailure("sourceUnavailable");active=null}
 fun closeHandle(handle:String){
  if(closed.contains(handle))return
  when(handle){sourceHandle->{input?.close();input=null;output?.close();output=null;if(!sourceEof)source(true).delete()}
   archiveHandle->{stopEntry();archive?.close();archive=null}
   else->throw EpubZipFailure("invalidHandle")}
  closed.add(handle)
 }
 private fun abortSource(){runCatching{input?.close()};input=null;runCatching{output?.close()};output=null;runCatching{if(File(root,"book-staging/$operation").exists())source(true).delete()}}
 fun interruptSource(){runCatching{input?.close()}}
 fun cancel(){invalidate();interruptSource();stopEntry();archive?.close();archive=null;abortSource()}
}

/** Each picker launch has a fresh Android request code; detached results expire. */
internal class EpubSelectionEpoch {
 private var next=4831
 private var current=0
 fun launch():Int {if(next>=65000)throw EpubZipFailure("sourceUnavailable");current=next++;return current}
 fun accepts(code:Int):Boolean=code==current&&current!=0
 fun invalidate(){current=0}
}

/** Public storage category only; never return errno messages or personal paths. */
internal fun epubStorageFailure(error:Exception):EpubZipFailure {
 if(error is EpubZipFailure)return error
 var cause:Throwable?=error
 repeat(8){
  val value=cause
  if(value is android.system.ErrnoException && value.errno==android.system.OsConstants.ENOSPC)return EpubZipFailure("insufficientStorage")
  cause=value?.cause
 }
 return EpubZipFailure("storageUnavailable")
}
