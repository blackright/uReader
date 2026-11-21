package com.ureader.prototype.epub

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** Debug-only explicit laboratory. Never opens the product database or root. */
class EpubDocumentLaboratoryActivity : FlutterActivity() {
 override fun configureFlutterEngine(engine:FlutterEngine){
  super.configureFlutterEngine(engine)
  if(!engine.plugins.has(EpubDocumentPlugin::class.java))engine.plugins.add(EpubDocumentPlugin("epub-source-lab"))
 }
}
