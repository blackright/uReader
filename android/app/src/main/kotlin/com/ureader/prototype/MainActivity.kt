package com.ureader.prototype

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.ureader.prototype.speech.SpeechPlugin
import com.ureader.prototype.speech.TrustedSpeechBundle
import com.ureader.prototype.reports.ReportExportPlugin
import com.ureader.prototype.models.LocalBundlePlugin
import com.ureader.prototype.epub.EpubDocumentPlugin

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(EpubDocumentPlugin::class.java)) {
            flutterEngine.plugins.add(EpubDocumentPlugin())
        }
        val trusted = TrustedSpeechBundle(applicationContext)
        if (!flutterEngine.plugins.has(SpeechPlugin::class.java)) {
            flutterEngine.plugins.add(SpeechPlugin(trusted::resolve))
        }
        if (!flutterEngine.plugins.has(ReportExportPlugin::class.java)) {
            flutterEngine.plugins.add(ReportExportPlugin())
        }
        if (!flutterEngine.plugins.has(LocalBundlePlugin::class.java)) {
            flutterEngine.plugins.add(LocalBundlePlugin())
        }
    }
}
