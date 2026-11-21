package com.ureader.prototype.reports

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.Executors

/** Explicit Storage Access Framework export; no storage permission or implicit sharing. */
class ReportExportPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null
    private var payload: ByteArray? = null
    private val worker = Executors.newSingleThreadExecutor()
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.ureader.prototype/reports/v1")
        channel.setMethodCallHandler(this)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "export") { result.notImplemented(); return }
        val activity = binding?.activity
        val id = call.argument<String>("id")
        val json = call.argument<String>("json")
        if (activity == null || pending != null || id == null || !id.matches(Regex("[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}")) || json == null || json.toByteArray().size > 1048576) {
            result.error("export_unavailable", "Export indisponible", null); return
        }
        pending = result; payload = json.toByteArray(Charsets.UTF_8)
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, "$id.json")
            }, 4821)
        } catch (_: Exception) { pending = null; payload = null; result.error("export_unavailable", "Export indisponible", null) }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 4821) return false
        val result = pending ?: return true
        val bytes = payload
        val activity = binding?.activity
        pending = null; payload = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result.success(false); return true }
        val uri = data.data!!
        worker.execute {
            val success = try {
                requireNotNull(activity).contentResolver.openOutputStream(uri, "wt").use { stream ->
                    requireNotNull(stream).write(requireNotNull(bytes))
                }; true
            } catch (_: Exception) { false }
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                if (success) result.success(true) else result.error("export_failed", "Export impossible", null)
            }
        }
        return true
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { this.binding = binding; binding.addActivityResultListener(this) }
    override fun onDetachedFromActivityForConfigChanges() { binding?.removeActivityResultListener(this); binding = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() { onDetachedFromActivityForConfigChanges(); pending?.error("export_cancelled", "Export interrompu", null); pending = null; payload = null }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { channel.setMethodCallHandler(null); worker.shutdown() }
}
