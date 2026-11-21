package com.ureader.prototype.epub

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.Assert.*
import java.io.ByteArrayInputStream
import java.io.File

class EpubDocumentPluginTest {
 private fun envelope(payload:Map<String,Any?> = emptyMap()) = mapOf<String,Any?>("protocolVersion" to 1,"requestId" to "r","operationId" to "op","generation" to 1L,"payload" to payload)
 @Test fun replyAllowsImmediateSequentialSourceRead() {
  val root=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"epub-reply-${System.nanoTime()}")
  val session=EpubSession(root,"op",1)
  val bytes=ByteArray(100){it.toByte()}
  val handle=session.select(ByteArrayInputStream(bytes))
  val plugin=EpubDocumentPlugin()
  val field=EpubDocumentPlugin::class.java.getDeclaredField("session");field.isAccessible=true;field.set(plugin,session)
  val done=java.util.concurrent.CountDownLatch(1)
  val failure=java.util.concurrent.atomic.AtomicReference<Throwable?>()
  val output=java.io.ByteArrayOutputStream()
  var sequence=0
  lateinit var read:()->Unit
  read={
   val request=envelope(mapOf("sourceHandle" to handle,"maxBytes" to 1))+mapOf("requestId" to "next-${++sequence}")
   plugin.onMethodCall(io.flutter.plugin.common.MethodCall("readSource",request),object:io.flutter.plugin.common.MethodChannel.Result {
    override fun success(value:Any?){try {
     val reply=value as Map<*,*>;assertFalse(reply.containsKey("error"))
     val result=reply["result"] as Map<*,*>;output.write(result["bytes"] as ByteArray)
     if(result["eof"]==true)done.countDown() else read()
    }catch(e:Throwable){failure.set(e);done.countDown()}}
    override fun error(code:String,message:String?,details:Any?){failure.set(AssertionError(code));done.countDown()}
    override fun notImplemented(){failure.set(AssertionError("missing method"));done.countDown()}
   })
  }
  try {
   InstrumentationRegistry.getInstrumentation().runOnMainSync{read()}
   assertTrue("sequential replies timed out",done.await(20,java.util.concurrent.TimeUnit.SECONDS))
   failure.get()?.let{throw AssertionError("sequential read rejected",it)}
   assertArrayEquals(bytes,output.toByteArray())
  }finally{
   session.cancel()
   for(name in listOf("worker","closer","timer")){
    val executor=EpubDocumentPlugin::class.java.getDeclaredField(name);executor.isAccessible=true
    (executor.get(plugin) as java.util.concurrent.ExecutorService).shutdownNow()
   }
   assertTrue(root.canonicalPath.startsWith(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir.canonicalPath+File.separator))
   root.deleteRecursively()
  }
 }
 @Test fun validatesEnvelopeBeforeAnySideEffect() {
  assertEquals("op",EpubRequest.parse(envelope()).operation)
  val unsupported=EpubRequest.failure(envelope()+mapOf("protocolVersion" to 9),"unsupportedProtocol")
  assertEquals(9,unsupported["protocolVersion"]);assertEquals("r",unsupported["requestId"]);assertEquals("op",unsupported["operationId"]);assertEquals(1L,unsupported["generation"])
  for(value in listOf(0,65537,1.5,Long.MAX_VALUE)){
   try{EpubRequest.parse(envelope(mapOf("maxBytes" to value))).count("maxBytes",65536);fail()}catch(e:EpubZipFailure){assertEquals("invalidRequest",e.code)}
  }

  for(value in listOf(null, mapOf("protocolVersion" to 1), envelope()+mapOf("generation" to 1.0),envelope()+mapOf("operationId" to "../outside"))) {
   try {EpubRequest.parse(value);fail("invalid request accepted")}catch(e:EpubZipFailure){assertEquals("invalidRequest",e.code)}
  }
  try {EpubRequest.parse(envelope()+mapOf("protocolVersion" to 9));fail()}catch(e:EpubZipFailure){assertEquals("unsupportedProtocol",e.code)}
 }
 @Test fun sourceEofCloseAndForeignHandleAreDeterministic() {
  val root=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"epub-source-${System.nanoTime()}")
  val session=EpubSession(root,"op",1)
  try {
   val handle=session.select(ByteArrayInputStream(byteArrayOf(1,2,3)))
   val first=session.readSource(handle,2)
   assertEquals(2L,first["totalBytes"]);assertEquals(false,first["eof"])
   val last=session.readSource(handle,2);assertEquals(3L,last["totalBytes"])
   assertEquals(true,session.readSource(handle,2)["eof"])
   assertArrayEquals(byteArrayOf(),session.readSource(handle,2)["bytes"] as ByteArray)
   session.closeHandle(handle);session.closeHandle(handle)
   try {session.readSource(handle,2);fail()}catch(e:EpubZipFailure){assertEquals("invalidHandle",e.code)}
   try {session.closeHandle("foreign");fail()}catch(e:EpubZipFailure){assertEquals("invalidHandle",e.code)}
  } finally {session.cancel();assertTrue(root.canonicalPath.startsWith(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir.canonicalPath+File.separator));root.deleteRecursively()}
 }
 @Test fun cancellationInvalidatesGenerationAndDoesNotPublishSource() {
  val root=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"epub-cancel-${System.nanoTime()}")
  val session=EpubSession(root,"op",1)
  try {
   val handle=session.select(ByteArrayInputStream(byteArrayOf(1,2,3)))
   session.cancel();session.cancel()
   try {session.readSource(handle,1);fail()}catch(e:EpubZipFailure){assertEquals("cancelled",e.code)}
   assertFalse(File(root,"book-staging/op/source").exists())
  } finally {root.deleteRecursively()}
 }
 @Test fun searchKeysUseIcuAndIgnoreDefaultLocale() {
  val previous=java.util.Locale.getDefault()
  try {
   java.util.Locale.setDefault(java.util.Locale("tr","TR"))
   assertEquals("ecole fi strasse i i",SearchKeyNormalizer.normalize("ÉCOLE ﬁ Straße I İ"))
   assertEquals("",SearchKeyNormalizer.normalize(""))
  } finally {java.util.Locale.setDefault(previous)}
 }

 @Test fun detachedPickerResultNeverSatisfiesNewSelection() {
  val epoch=EpubSelectionEpoch();val first=epoch.launch();assertTrue(epoch.accepts(first));epoch.invalidate();assertFalse(epoch.accepts(first));val next=epoch.launch();assertNotEquals(first,next);assertFalse(epoch.accepts(first));assertTrue(epoch.accepts(next))
 }
 @Test fun archivePagesAndEntryEofAreBoundToTheirHandles() {
  val root=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"epub-pages-${System.nanoTime()}")
  val bytes=java.io.ByteArrayOutputStream().apply {java.util.zip.ZipOutputStream(this).use{z->for(name in listOf("one","two")){z.putNextEntry(java.util.zip.ZipEntry(name));z.write(byteArrayOf(1,2,3));z.closeEntry()}}}.toByteArray()
  val session=EpubSession(root,"op",1)
  try {
   val source=session.select(ByteArrayInputStream(bytes));while(session.readSource(source,65536)["eof"]!=true){}
   session.closeHandle(source);val archive=session.openArchive()["archiveHandle"] as String
   val first=session.listEntries(archive,null,1);assertEquals(false,first["done"])
   val cursor=first["nextCursor"] as String
   val page=session.listEntries(archive,cursor,1);assertEquals(page,session.listEntries(archive,cursor,1));assertEquals(true,page["done"])
   try{session.listEntries(archive,"foreign",1);fail()}catch(e:EpubZipFailure){assertEquals("invalidHandle",e.code)}
   val entries=first["entries"] as List<*>
   val entry=(entries.single() as Map<*,*>)["entryHandle"] as String
   val output=java.io.ByteArrayOutputStream()
   while(true){val part=session.readEntry(archive,entry,1);output.write(part["bytes"] as ByteArray);if(part["eof"]==true)break}
   assertArrayEquals(byteArrayOf(1,2,3),output.toByteArray());assertEquals(3L,session.readEntry(archive,entry,1)["totalBytes"])
   session.closeHandle(archive);session.closeHandle(archive)
   try{session.readEntry(archive,entry,1);fail()}catch(e:EpubZipFailure){assertEquals("invalidHandle",e.code)}
  }finally{session.cancel();root.deleteRecursively()}
 }
 @Test fun partialCopyCannotOpenArchiveAndCancellationClosesBlockedProvider() {
  val root=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"epub-blocked-${System.nanoTime()}")
  val entered=java.util.concurrent.CountDownLatch(1);val released=java.util.concurrent.CountDownLatch(1)
  val stream=object:java.io.InputStream(){override fun read():Int {entered.countDown();released.await();return -1};override fun close(){released.countDown()}}
  val session=EpubSession(root,"op",1);val error=java.util.concurrent.atomic.AtomicReference<String>()
  try {
   val handle=session.select(stream)
   try{session.openArchive();fail()}catch(e:EpubZipFailure){assertEquals("invalidRequest",e.code)}
   val thread=Thread{try{session.readSource(handle,65536)}catch(e:EpubZipFailure){error.set(e.code)}};thread.start()
   assertTrue(entered.await(2,java.util.concurrent.TimeUnit.SECONDS));session.cancel();thread.join(2000)
   assertFalse(thread.isAlive);assertEquals("cancelled",error.get());assertFalse(File(root,"book-staging/op/source").exists())
  }finally{session.cancel();root.deleteRecursively()}
 }

 @Test fun fullPrivateDiskHasActionableErrorWithoutRawDetails() {
  val error=java.io.IOException("private path",android.system.ErrnoException("write",android.system.OsConstants.ENOSPC))
  assertEquals("insufficientStorage",epubStorageFailure(error).code)
  assertEquals("storageUnavailable",epubStorageFailure(java.io.IOException("private path")).code)
 }

 @Test fun everyV1MethodHasBoundedPayloadSchemaBeforeDispatch() {
  val valid=mapOf<String,Map<String,Any?>>("chooseDocument" to emptyMap(),"openArchive" to emptyMap(),"cancel" to emptyMap(),"readSource" to mapOf("sourceHandle" to "s","maxBytes" to 65536L),"listEntries" to mapOf("archiveHandle" to "a","cursor" to null,"pageSize" to 128),"readEntry" to mapOf("archiveHandle" to "a","entryHandle" to "e","maxBytes" to 1),"close" to mapOf("handle" to "h"),"normalizeSearchKey" to mapOf("text" to ""),"openExternal" to mapOf("url" to "https://example.org","userConfirmed" to true))
  for((method,payload)in valid){
   EpubRequest.parse(envelope(payload)).validatePayload(method)
   try{EpubRequest.parse(envelope(payload+mapOf("destination" to "/outside"))).validatePayload(method);fail("unexpected field accepted")}catch(e:EpubZipFailure){assertEquals("invalidRequest",e.code)}
  }
  for((method,payload)in mapOf("listEntries" to mapOf("archiveHandle" to "a","cursor" to 1,"pageSize" to 129),"close" to mapOf("handle" to false),"openExternal" to mapOf("url" to "https://example.org","userConfirmed" to false))){
   try{EpubRequest.parse(envelope(payload)).validatePayload(method);fail()}catch(e:EpubZipFailure){assertEquals("invalidRequest",e.code)}
  }
 }

 @Test fun sourceExpirationIsNotReportedAsUserCancellation() {
  val root=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"epub-expired-${System.nanoTime()}")
  val session=EpubSession(root,"op",1)
  try{
   val handle=session.select(ByteArrayInputStream(byteArrayOf(1)))
   session.expire()
   try{session.readSource(handle,1);fail()}catch(e:EpubZipFailure){assertEquals("sourceUnavailable",e.code)}
  }finally{session.cancel();root.deleteRecursively()}
 }

}
