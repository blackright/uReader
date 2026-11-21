package com.ureader.prototype.epub
import org.junit.Test
import org.junit.Assert.*
class BookExternalLinkTest {
 @Test fun refusesUnsafeOrUnconfirmedWithoutLaunchingAnything(){
  for(url in listOf("http://example.org","file:///private","javascript:alert(1)","https://user:secret@example.org","https://example.org/%0AX","https://example.org:70000","https://example.org/\\private")){
   try{BookExternalLink.parse(url,true);fail(url)}catch(_:EpubZipFailure){}
  }
  try{BookExternalLink.parse("https://example.org",false);fail()}catch(e:EpubZipFailure){assertEquals("invalidRequest",e.code)}
  assertEquals("https://example.org/path?q=1#anchor",BookExternalLink.parse("https://example.org/path?q=1#anchor",true).toString())
 }
 @Test fun pluginBuildsOnlyAConfirmedBrowsableViewIntent(){
  val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
  val captured=java.util.concurrent.atomic.AtomicReference<android.content.Intent?>()
  val context=object:android.content.ContextWrapper(instrumentation.targetContext){override fun startActivity(intent:android.content.Intent){captured.set(intent)}}
  val plugin=EpubDocumentPlugin();val field=EpubDocumentPlugin::class.java.getDeclaredField("context");field.isAccessible=true;field.set(plugin,context)
  var seq=0
  fun invoke(confirmed:Boolean):Map<*,*> {
   val result=java.util.concurrent.atomic.AtomicReference<Map<*,*>>()
   val done=java.util.concurrent.CountDownLatch(1)
   instrumentation.runOnMainSync {
    val args=mapOf("protocolVersion" to 1,"requestId" to "external-${++seq}","operationId" to "external","generation" to 1L,"payload" to mapOf("url" to "https://example.org/read?q=1#anchor","userConfirmed" to confirmed))
    plugin.onMethodCall(io.flutter.plugin.common.MethodCall("openExternal",args),object:io.flutter.plugin.common.MethodChannel.Result {
     override fun success(value:Any?){result.set(value as Map<*,*>);done.countDown()}
     override fun error(code:String,message:String?,details:Any?){done.countDown()}
     override fun notImplemented(){done.countDown()}
    })
   }
   assertTrue(done.await(10,java.util.concurrent.TimeUnit.SECONDS));return result.get()
  }
  try{
   assertTrue(invoke(false).containsKey("error"));assertNull(captured.get())
   val reply=invoke(true);assertEquals(true,(reply["result"] as Map<*,*>)["opened"])
   val intent=captured.get()!!;assertEquals(android.content.Intent.ACTION_VIEW,intent.action)
   assertTrue(intent.hasCategory(android.content.Intent.CATEGORY_BROWSABLE));assertEquals("https://example.org/read?q=1#anchor",intent.data.toString())
   assertNull(intent.extras);assertNull(intent.clipData)
  }finally{instrumentation.runOnMainSync{};for(name in listOf("worker","closer","timer")){val f=EpubDocumentPlugin::class.java.getDeclaredField(name);f.isAccessible=true;(f.get(plugin) as java.util.concurrent.ExecutorService).shutdownNow()}}
 }
}
