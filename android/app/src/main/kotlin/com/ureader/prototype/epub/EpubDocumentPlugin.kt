package com.ureader.prototype.epub

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/** Local EPUB input and explicitly confirmed HTTPS delegation. No global storage
 * permissions, persistent grants, network clients or logging of personal inputs. */
class EpubDocumentPlugin(private val storageNamespace:String="ureader-prototype") : FlutterPlugin,ActivityAware,MethodChannel.MethodCallHandler,PluginRegistry.ActivityResultListener {
 private lateinit var context:android.content.Context
 private lateinit var channel:MethodChannel
 private var activity:ActivityPluginBinding?=null
 private val worker=Executors.newSingleThreadExecutor()
 private val closer=Executors.newSingleThreadExecutor()
 private val timer=Executors.newSingleThreadScheduledExecutor()
 private val main=Handler(Looper.getMainLooper())
 @Volatile private var providerCancellation:android.os.CancellationSignal?=null
 private val busyReads=ConcurrentHashMap.newKeySet<String>()
 private val inFlight=ConcurrentHashMap.newKeySet<String>()
 @Volatile private var session:EpubSession?=null
 @Volatile private var pending:Pair<EpubRequest,MethodChannel.Result>?=null
 @Volatile private var retired=false
 private var idle:java.util.concurrent.ScheduledFuture<*>?=null
 private val pickerEpoch=EpubSelectionEpoch()
 override fun onAttachedToEngine(binding:FlutterPlugin.FlutterPluginBinding){
  require(Regex("[A-Za-z0-9_-]{1,64}").matches(storageNamespace))
  context=binding.applicationContext;channel=MethodChannel(binding.binaryMessenger,"com.ureader.prototype/epub/v1");channel.setMethodCallHandler(this)
 }
 private fun armIdle(s:EpubSession){
  if(retired||timer.isShutdown||s.cancelled.get()||s!==session)return
  idle?.cancel(false)
  idle=timer.schedule({
   if(!retired&&s===session&&pending==null&&!s.cancelled.get()){
    s.expire();providerCancellation?.cancel()
    closer.execute{s.interruptSource();worker.execute{runCatching{s.cancel()}}}
   }
  },30,TimeUnit.SECONDS)
 }
 private fun reply(q:EpubRequest,result:MethodChannel.Result,value:Map<String,Any?>?=null,error:String?=null){main.post {
  inFlight.remove(q.request)
  result.success(q.envelope(value,if(q.operation==session?.operation&&q.generation==session?.generation&&session?.cancelled?.get()==true&&error==null&&value?.get("cancelled")!=true&&value?.get("status")!="cancelled")session?.cancellationCode else error))
  if(error==null&&value?.get("cancelled")!=true)session?.takeIf{it.operation==q.operation&&it.generation==q.generation}?.let{armIdle(it)}
 }}
 private fun owned(q:EpubRequest):EpubSession {
  val s=session ?: throw EpubZipFailure("invalidHandle")
  if(q.operation!=s.operation||q.generation!=s.generation)throw EpubZipFailure("invalidHandle")
  if(s.cancelled.get())throw EpubZipFailure(s.cancellationCode)
  return s
 }
 override fun onMethodCall(call:MethodCall,result:MethodChannel.Result){
  val q=try{EpubRequest.parse(call.arguments)}catch(e:EpubZipFailure){result.success(EpubRequest.failure(call.arguments,e.code));return}
  try{q.validatePayload(call.method)}catch(e:EpubZipFailure){result.success(q.envelope(error=e.code));return}
  if(retired){result.success(q.envelope(error="cancelled"));return}
  if(!inFlight.add(q.request)){result.success(q.envelope(error="invalidRequest"));return}
  try {
   when(call.method){
    "chooseDocument"->{
     if(q.payload.isNotEmpty())throw EpubZipFailure("invalidRequest")
     if(pending!=null ||session?.let{!it.cancelled.get()}==true)throw EpubZipFailure("operationInProgress")
     val host=activity?.activity ?: throw EpubZipFailure("sourceUnavailable")
     session=EpubSession(File(context.filesDir,storageNamespace),q.operation,q.generation);pending=q to result
     val pickerCode=pickerEpoch.launch()
     try{host.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply{type="application/epub+zip";addCategory(Intent.CATEGORY_OPENABLE);addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)},pickerCode)}catch(_:Exception){pending=null;session?.cancel();throw EpubZipFailure("sourceUnavailable")}
    }
    "openExternal"->{
     val uri=BookExternalLink.parse(q.string("url",16384),q.payload["userConfirmed"]==true)
     val opened=try{
      context.startActivity(Intent(Intent.ACTION_VIEW,uri).addCategory(Intent.CATEGORY_BROWSABLE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));true
     }catch(_:Exception){false}
     reply(q,result,mapOf("opened" to opened))
    }
    "cancel"->{
     if(q.payload.isNotEmpty())throw EpubZipFailure("invalidRequest")
     val s=session ?: throw EpubZipFailure("invalidHandle")
     if(q.operation!=s.operation||q.generation!=s.generation)throw EpubZipFailure("invalidHandle")
     s.invalidate();providerCancellation?.cancel()
     pending?.let{pending=null;reply(it.first,it.second,error="cancelled")}
     closer.execute {s.interruptSource();worker.execute {try{s.cancel();reply(q,result,mapOf("cancelled" to true))}catch(_:Exception){reply(q,result,error="sourceUnavailable")}}}
    }
    else->{
     val action:()->Map<String,Any?> = when(call.method){
      "readSource"->{val h=q.string("sourceHandle");val n=q.count("maxBytes",65536);{owned(q).readSource(h,n)}}
      "openArchive"->{if(q.payload.isNotEmpty())throw EpubZipFailure("invalidRequest");{owned(q).openArchive()}}
      "listEntries"->{val h=q.string("archiveHandle");val n=q.count("pageSize",128);val c=q.payload["cursor"];if(c!=null&&c !is String)throw EpubZipFailure("invalidRequest");{owned(q).listEntries(h,c,n)}}
      "readEntry"->{val h=q.string("archiveHandle");val e=q.string("entryHandle");val n=q.count("maxBytes",65536);{owned(q).readEntry(h,e,n)}}
      "close"->{val h=q.string("handle");{owned(q).closeHandle(h);mapOf("closed" to true)}}
      "normalizeSearchKey"->{val text=q.string("text",16384,true);{mapOf("key" to SearchKeyNormalizer.normalize(text))}}
      // Unknown methods have no side effects.
      else->throw EpubZipFailure("invalidRequest")
     }
     val readKey=if(call.method in setOf("readSource","readEntry")) "${q.operation}:${q.generation}:${q.payload[if(call.method=="readSource")"sourceHandle" else "entryHandle"]}" else null
     if(readKey!=null&&!busyReads.add(readKey))throw EpubZipFailure("operationInProgress")
     session?.takeIf{it.operation==q.operation&&it.generation==q.generation}?.let{idle?.cancel(false)}
     worker.execute {
      val timeout=timer.schedule({session?.takeIf{it.operation==q.operation&&it.generation==q.generation}?.let{it.expire();closer.execute{it.interruptSource()}}},30,TimeUnit.SECONDS)
      // Release the in-flight read before its reply can trigger the next read.
      var value:Map<String,Any?>?=null
      var failure:String?=null
      try {value=action()}catch(e:Exception){failure=if(e is EpubZipFailure)e.code else "sourceUnavailable"}finally{timeout.cancel(false);if(readKey!=null)busyReads.remove(readKey)}
      reply(q,result,value,error=failure)
     }
    }
   }
  }catch(e:Exception){reply(q,result,error=if(e is EpubZipFailure)e.code else "sourceUnavailable")}
 }
 override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?):Boolean {
  if(!pickerEpoch.accepts(requestCode))return false
  val selected=pending ?: return true;pending=null
  val(q,result)=selected
  if(resultCode!=Activity.RESULT_OK){session?.invalidate();reply(q,result,mapOf("status" to "cancelled"));return true}
  val uri=data?.data
  if(uri?.scheme!="content"){session?.invalidate();reply(q,result,error="sourceUnavailable");return true}
  val s=session ?: run{reply(q,result,error="cancelled");return true}
  worker.execute {
   val requestSignal=android.os.CancellationSignal();providerCancellation=requestSignal
   val timeout=timer.schedule({s.expire();requestSignal.cancel();closer.execute{s.interruptSource()}},30,TimeUnit.SECONDS)
   try {
    if(s.cancelled.get())throw EpubZipFailure(s.cancellationCode)
    var name:String?=null;var size:Long?=null
    val signal=requestSignal
    context.contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE),null,null,null,signal)?.use{c->if(c.moveToFirst()){
     val ni=c.getColumnIndex(OpenableColumns.DISPLAY_NAME);val si=c.getColumnIndex(OpenableColumns.SIZE)
     if(ni>=0&&!c.isNull(ni))name=c.getString(ni)?.take(4096)
     if(si>=0&&!c.isNull(si))size=c.getLong(si).takeIf{it>=0}
    }}
    val descriptor=context.contentResolver.openAssetFileDescriptor(uri,"r",signal) ?: throw EpubZipFailure("sourceUnavailable")
    val input=try{descriptor.createInputStream()}catch(e:Exception){descriptor.close();throw e}
    if(s.cancelled.get()){input.close();throw EpubZipFailure(s.cancellationCode)}
    val handle=s.select(input);reply(q,result,mapOf("status" to "selected","sourceHandle" to handle,"displayName" to name,"declaredBytes" to size))
   }catch(e:Exception){s.invalidate();runCatching{s.cancel()};reply(q,result,error=if(e is EpubZipFailure)e.code else "sourceUnavailable")}finally{timeout.cancel(false);providerCancellation=null}
  }
  return true
 }
 override fun onAttachedToActivity(binding:ActivityPluginBinding){activity=binding;binding.addActivityResultListener(this)}
 // Invalidate pending selection on rotation; a late result cannot satisfy a new one.
 private fun detach(){pickerEpoch.invalidate();idle?.cancel(false);activity?.removeActivityResultListener(this);activity=null;val s=session;s?.invalidate();providerCancellation?.cancel();pending?.let{pending=null;reply(it.first,it.second,error="cancelled")};closer.execute{s?.interruptSource();worker.execute{runCatching{s?.cancel()}};if(retired)worker.shutdown()}}
 override fun onDetachedFromActivityForConfigChanges()=detach()
 override fun onReattachedToActivityForConfigChanges(binding:ActivityPluginBinding)=onAttachedToActivity(binding)
 override fun onDetachedFromActivity()=detach()
 override fun onDetachedFromEngine(binding:FlutterPlugin.FlutterPluginBinding){retired=true;channel.setMethodCallHandler(null);detach();timer.shutdownNow();closer.shutdown()}
}
