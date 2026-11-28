package com.ureader.prototype.models

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONObject
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import com.ureader.prototype.speech.SpeechWireCommand

internal object LocalSourcePolicy {
    fun accepts(uri: Uri?): Boolean = uri != null && uri.scheme == "content" &&
        uri.authority in setOf("com.android.externalstorage.documents", "com.android.providers.downloads.documents") &&
        DocumentsContract.isTreeUri(uri)

    fun fileNames(context: Context): Set<String> = listOf("manifest.json", "kokoro-manifest.json")
        .flatMap { asset ->
            val manifest = context.assets.open("flutter_assets/assets/models/$asset").use {
                JSONObject(String(it.readBytes(), Charsets.UTF_8))
            }
            val files = manifest.getJSONArray("files")
            require(files.length() in 1..32)
            (0 until files.length()).map { index ->
                files.getJSONObject(index).getString("relativePath").also {
                    require(SpeechWireCommand.validId(it))
                }
            }
        }.toSet()
}

/** Read-only local SAF import. No URI, absolute path or file content enters diagnostics. */
class LocalBundlePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: ActivityPluginBinding? = null
    private var selection: MethodChannel.Result? = null
    @Volatile private var tree: Uri? = null
    @Volatile private var input: InputStream? = null
    private val streamLock = Any()
    private val epoch = AtomicInteger()
    private val worker = Executors.newSingleThreadExecutor()
    private val closer = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var allowedNames: Set<String>
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        allowedNames = runCatching { LocalSourcePolicy.fileNames(context) }.getOrElse { emptySet() }
        channel = MethodChannel(binding.binaryMessenger, "com.ureader.prototype/local_bundle/v1")
        channel.setMethodCallHandler(this)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availableBytes" -> worker.execute {
                try {
                    val bytes = android.os.StatFs(context.filesDir.path).availableBytes
                    main.post { result.success(bytes) }
                } catch (_: Exception) { main.post { result.error("storageUnavailable", "Espace libre indisponible", null) } }
            }
            "chooseFolder" -> {
                val host = activity?.activity
                if (host == null || selection != null || input != null) { result.error("resourceInUse", "Préparation indisponible", null); return }
                tree = null; epoch.incrementAndGet(); selection = result
                try { host.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply { addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) }, 4822) }
                catch (_: Exception) { selection = null; result.error("storageUnavailable", "Dossier indisponible", null) }
            }
            "close" -> {
                epoch.incrementAndGet(); tree = null
                selection?.success(false); selection = null
                val stream = synchronized(streamLock) { val previous = input; input = null; previous }
                closer.execute {
                    try { stream?.close() } catch (_: Exception) { }
                    main.post { result.success(null) }
                }
            }
            "open", "read" -> {
                val generation = epoch.get()
                val name = call.argument<String>("name")
                if (call.method == "open" && name !in allowedNames) { result.error("invalidContent", "Fichier refusé", null); return }
                worker.execute {
                    try {
                        check(epoch.get() == generation)
                        val value: Any? = if (call.method == "open") {
                            check(input == null)
                            val folder = requireNotNull(tree)
                            val children = DocumentsContract.buildChildDocumentsUriUsingTree(folder, DocumentsContract.getTreeDocumentId(folder))
                            var documentId: String? = null
                            context.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null).use { cursor ->
                                requireNotNull(cursor)
                                while (cursor.moveToNext()) {
                                    if (cursor.getString(1) == name) { check(documentId == null); documentId = cursor.getString(0) }
                                }
                            }
                            val uri = DocumentsContract.buildDocumentUriUsingTree(folder, requireNotNull(documentId))
                            val opened = requireNotNull(context.contentResolver.openInputStream(uri))
                            val accepted = synchronized(streamLock) {
                                if (epoch.get() != generation) false else { input = opened; true }
                            }
                            if (!accepted) { opened.close(); error("Cancelled") }
                            null
                        } else {
                            val buffer = ByteArray(65536)
                            val size = requireNotNull(input).read(buffer)
                            if (size < 0) { input?.close(); input = null; ByteArray(0) } else buffer.copyOf(size)
                        }
                        main.post { if (epoch.get() == generation) result.success(value) else result.error("cancelled", "Opération annulée", null) }
                    } catch (_: Exception) { main.post { result.error(if (epoch.get() == generation) "modelIntegrityFailed" else "cancelled", "Lecture locale interrompue", null) } }
                }
            }
            else -> result.notImplemented()
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 4822) return false
        val result = selection ?: return true
        selection = null
        if (resultCode != Activity.RESULT_OK) { result.success(false); return true }
        val uri = data?.data
        if (!LocalSourcePolicy.accepts(uri)) {
            result.error("unsafePath", "Choisissez un dossier local du téléphone", null); return true
        }
        tree = uri; result.success(true); return true
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding; binding.addActivityResultListener(this) }
    override fun onDetachedFromActivityForConfigChanges() { activity?.removeActivityResultListener(this); activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() { onDetachedFromActivityForConfigChanges(); selection?.success(false); selection = null }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null); epoch.incrementAndGet(); tree = null
        val stream = synchronized(streamLock) { val previous = input; input = null; previous }
        closer.execute { try { stream?.close() } catch (_: Exception) { } }
        worker.shutdown(); closer.shutdown()
    }
}
