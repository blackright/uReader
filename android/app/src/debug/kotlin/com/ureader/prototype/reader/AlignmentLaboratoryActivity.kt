package com.ureader.prototype.reader

import android.app.Activity
import android.os.Bundle
import android.os.Debug
import android.os.SystemClock
import android.widget.TextView
import com.ureader.prototype.speech.FrenchUnigramTokenizer
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/** Explicit debug-only inference pre-bench. No access to the product root/database. */
class AlignmentLaboratoryActivity : Activity() {
    private val cancelled = AtomicBoolean(false)
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val label = TextView(this).apply { text = "Laboratoire d’alignement — inférence isolée en cours"; textSize = 22f; setPadding(24,48,24,24) }
        setContentView(label)
        val root = File(filesDir,"ureader-alignment-lab").canonicalFile
        Thread({
            val report = JSONObject().put("androidExecuted",true).put("g1","not_evaluated").put("audibleTimingScore","not_evaluated")
            try {
                check(root.isDirectory && !File(root,"result.json").exists())
                val config = JSONObject(File(root,"experiment.json").readText())
                fun trust(key:String):Map<String,Pair<Long,String>> {
                    val entries = config.getJSONObject(key)
                    return entries.keys().asSequence().associateWith { name ->
                        val entry=entries.getJSONObject(name); Pair(entry.getLong("byteSize"),entry.getString("sha256"))
                    }
                }
                fun sha(file:File):String {
                    val digest=MessageDigest.getInstance("SHA-256")
                    file.inputStream().use { input -> val buffer=ByteArray(65536); while(true){val count=input.read(buffer);if(count<0)break;digest.update(buffer,0,count)} }
                    return digest.digest().joinToString(""){"%02x".format(it)}
                }
                val text="Chaque matin, Léa ouvre la petite porte du jardin."
                val noise=FloatArray(250*32).also { array -> val random=java.util.Random(71);for(i in array.indices)array[i]=(random.nextGaussian()*sqrt(.3)).toFloat() }
                val outputs=ArrayList<AlignmentNativeAudio>()
                val rows=JSONArray()
                val start=SystemClock.elapsedRealtime()
                for(name in listOf("baseline","candidate")) {
                    check(!cancelled.get())
                    val directory=File(root,name)
                    val engine=AlignmentLaboratorySynthesizer(directory,trust(name),168,name=="candidate",root)
                    val audio=engine.synthesize(text,{check(!cancelled.get())},noise)
                    outputs.add(audio)
                    rows.put(JSONObject().put("kind",name).put("wav",audio.file.name).put("wavSha256",sha(audio.file))
                        .put("samples",audio.samples).put("generationMs",audio.generationMs).put("totalMs",audio.totalMs))
                    if(name=="candidate") {
                        val attention=JSONArray()
                        for(row in engine.attentionRows) attention.put(JSONArray(row.map{it.toDouble()}))
                        File(root,"attention.json").writeText(JSONObject().put("layer",3).put("head",9).put("frameRate",12.5)
                          .put("rows",attention).put("tokenIds",JSONArray(FrenchUnigramTokenizer(File(directory,"tokenizer.json").readText()).encode(text))).toString())
                        report.put("attentionRows",engine.attentionRows.size)
                    }
                }
                val a=outputs[0].file.readBytes();val b=outputs[1].file.readBytes()
                report.put("status","inference_prebench_complete").put("runs",rows).put("pcmBytesIdentical",a.contentEquals(b))
                    .put("elapsedMs",SystemClock.elapsedRealtime()-start).put("pssKbAfter",Debug.getPss())
                    .put("memoryScope","single after-run PSS sample; not a peak measurement")
                    .put("clockTested",false).put("visualFollowTested",false).put("cuesStatus","raw_attention_only")
                File(root,"result.json").writeText(report.toString(2))
                runOnUiThread { label.text="Inférence terminée. G1 non évalué : captation et annotations restent à réaliser." }
            } catch(error:Throwable) {
                report.put("status",if(cancelled.get())"cancelled" else "failed").put("reason",error.javaClass.simpleName)
                if(root.isDirectory)File(root,"failure.json").writeText(report.toString(2))
                runOnUiThread { label.text="Essai interrompu. Aucune donnée produit modifiée." }
            }
        },"alignment-prebench").start()
    }
    override fun onDestroy(){cancelled.set(true);super.onDestroy()}
}
