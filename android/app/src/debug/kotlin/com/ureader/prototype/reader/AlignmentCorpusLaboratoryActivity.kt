package com.ureader.prototype.reader

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Debug
import android.os.SystemClock
import android.widget.TextView
import com.ureader.prototype.speech.FrenchUnigramTokenizer
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.sqrt

/** Debug only. Batch inference is silent and never opens the product database/root. */
class AlignmentCorpusLaboratoryActivity : Activity() {
    private val cancelled = AtomicBoolean(false)
    private val cancelRequestedAt = AtomicLong(0)
    private lateinit var label: TextView
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        label=TextView(this).apply{text="Corpus d’alignement — préparation silencieuse";textSize=22f;setPadding(24,48,24,24)}
        setContentView(label)
        val id=intent.getStringExtra("runId") ?: ""
        val expected=intent.getStringExtra("inputSha256") ?: ""
        if(!Regex("^corpus-[a-z0-9-]{1,48}$").matches(id) || !Regex("^[a-f0-9]{64}$").matches(expected)){label.text="Identité de banc invalide";return}
        val parent=File(filesDir,"ureader-alignment-corpus").canonicalFile
        val root=File(parent,id).canonicalFile
        if(root.parentFile!=parent || !root.isDirectory){label.text="Dossier de banc invalide";return}
        Thread({run(root,id,expected)},"alignment-corpus").start()
    }
    override fun onNewIntent(intent:Intent){
        super.onNewIntent(intent)
        if(intent.getBooleanExtra("cancel",false)) {cancelRequestedAt.compareAndSet(0,SystemClock.elapsedRealtime());cancelled.set(true)}
    }
    override fun onDestroy(){cancelRequestedAt.compareAndSet(0,SystemClock.elapsedRealtime());cancelled.set(true);super.onDestroy()}
    private fun active(){if(cancelled.get())throw CancellationException("Laboratory cancelled")}
    private fun sha(file:File):String {
        val digest=MessageDigest.getInstance("SHA-256")
        file.inputStream().use{stream->val buffer=ByteArray(65536);while(true){active();val n=stream.read(buffer);if(n<0)break;digest.update(buffer,0,n)}}
        return digest.digest().joinToString(""){"%02x".format(it)}
    }
    private fun textSha(value:String)=MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString(""){"%02x".format(it)}
    private fun publish(file:File,document:JSONObject){
        val part=File(file.parentFile,file.name+".part")
        part.outputStream().use{it.write(document.toString().toByteArray(Charsets.UTF_8));it.fd.sync()}
        check(part.renameTo(file))
    }
    private fun run(root:File,id:String,expected:String){
        val started=SystemClock.elapsedRealtime()
        val results=JSONArray();val report=JSONObject().put("schemaVersion",1).put("runId",id).put("inputSha256",expected)
          .put("androidExecuted",true).put("g1","not_evaluated").put("audioPlaybackRequested",false).put("results",results)
        var sampledMax=Debug.getPss();var lastSample=0L
        fun sample(){val now=SystemClock.elapsedRealtime();if(now-lastSample>=500){sampledMax=maxOf(sampledMax,Debug.getPss());lastSample=now}}
        try{
            check(File(root,"started.marker").createNewFile()) {"A fresh run is required"}
            val inputFile=File(root,"input.json");check(inputFile.length() in 1..3145728 && sha(inputFile)==expected)
            val input=JSONObject(inputFile.readText());check(input.getString("runId")==id)
            report.put("corpusSha256",input.getString("corpusSha256"))
            val trustFile=File(root,"experiment.json");check(trustFile.length() in 1..65536 && sha(trustFile)==input.getString("modelTrustSha256"))
            val config=JSONObject(trustFile.readText());val unique=input.getJSONArray("uniqueCases");val occurrences=input.getJSONArray("occurrences")
            check(unique.length() in 1..64 && occurrences.length() in 1..256)
            val ids=HashSet<String>()
            for(i in 0 until unique.length()){
                val spec=unique.getJSONObject(i);val digest=spec.getString("id");val text=spec.getString("prepared")
                check(Regex("^[a-f0-9]{64}$").matches(digest) && ids.add(digest) && text.length in 1..4096 && textSha(text)==digest && spec.getString("preparedSha256")==digest)
                val output=File(root,digest);check(output.mkdir())
                val caseResult=JSONObject().put("id",digest).put("seed",spec.getLong("seed"));val runs=JSONArray()
                val noise=FloatArray(250*32).also{array->val rng=java.util.Random(spec.getLong("seed"));for(n in array.indices)array[n]=(rng.nextGaussian()*sqrt(.3)).toFloat()}
                val audio=ArrayList<AlignmentNativeAudio>()
                for(kind in listOf("baseline","candidate")){
                    active()
                    publish(File(root,"progress.json"),JSONObject().put("status","running").put("uniqueIndex",i).put("uniqueTotal",unique.length()).put("kind",kind).put("stage","verifying"))
                    val entries=config.getJSONObject(kind)
                    val trust=entries.keys().asSequence().associateWith{name->val entry=entries.getJSONObject(name);Pair(entry.getLong("byteSize"),entry.getString("sha256"))}
                    val bundle=File(File(filesDir,"ureader-alignment-lab"),kind).canonicalFile
                    val tokenIds=FrenchUnigramTokenizer(File(bundle,"tokenizer.json").readText()).encode(text)
                    val expectedIds=spec.getJSONArray("tokenIds");check(tokenIds.size in 1..50 && tokenIds.size==expectedIds.length())
                    for(n in tokenIds.indices)check(tokenIds[n]==expectedIds.getInt(n))
                    val engine=AlignmentLaboratorySynthesizer(bundle,trust,168,kind=="candidate",output)
                    var entered=false
                    val generated=engine.synthesize(text,{active()},noise,{
                        active();sample()
                        if(!entered){entered=true;publish(File(root,"progress.json"),JSONObject().put("status","running").put("uniqueIndex",i).put("uniqueTotal",unique.length()).put("kind",kind).put("stage","inference"))}
                    })
                    audio.add(generated);sample()
                    runs.put(JSONObject().put("kind",kind).put("wav",digest+"/"+generated.file.name).put("wavSha256",sha(generated.file))
                      .put("samples",generated.samples).put("frames",generated.frames).put("eosAt",generated.eosAt).put("generationMs",generated.generationMs).put("totalMs",generated.totalMs))
                    if(kind=="candidate"){
                        val rows=JSONArray();for(row in engine.attentionRows)rows.put(JSONArray(row.map{it.toDouble()}))
                        val attention=JSONObject().put("tokenIds",JSONArray(tokenIds)).put("rows",rows).put("layer",3).put("head",9).put("frameRate",12.5)
                        val attentionFile=File(output,"attention.json");publish(attentionFile,attention)
                        caseResult.put("attentionFile",digest+"/attention.json").put("attentionSha256",sha(attentionFile)).put("attentionRows",engine.attentionRows.size)
                    }
                }
                val identical=audio[0].file.readBytes().contentEquals(audio[1].file.readBytes())
                caseResult.put("runs",runs).put("pcmBytesIdentical",identical);results.put(caseResult)
                publish(File(root,"checkpoint.json"),report)
                check(identical) {"Numerical parity failed"}
                runOnUiThread{label.text="Corpus silencieux : ${i+1}/${unique.length()} textes distincts préparés"}
            }
            for(i in 0 until occurrences.length())check(ids.contains(occurrences.getJSONObject(i).getString("uniqueId")))
            report.put("status","complete").put("uniquePrepared",unique.length()).put("occurrences",occurrences.length()).put("allPcmBytesIdentical",true)
              .put("elapsedMs",SystemClock.elapsedRealtime()-started).put("sampledMaxPssKb",sampledMax)
              .put("memoryScope","Samples before main inference steps at >=500ms and after synthesis; not a guaranteed native peak")
            publish(File(root,"result.json"),report)
            publish(File(root,"progress.json"),JSONObject().put("status","complete").put("uniqueCompleted",unique.length()))
            runOnUiThread{label.text="Corpus préparé sans son. G1 non évalué."}
        }catch(error:Throwable){
            val requested=cancelRequestedAt.get()
            report.put("status",if(error is CancellationException)"cancelled" else "failed").put("reason",error.javaClass.simpleName)
              .put("elapsedMs",SystemClock.elapsedRealtime()-started).put("sampledMaxPssKb",sampledMax)
            if(requested>0)report.put("cooperativeCancelLatencyMs",SystemClock.elapsedRealtime()-requested)
            publish(File(root,"failure.json"),report)
            publish(File(root,"progress.json"),JSONObject().put("status",report.getString("status")))
            runOnUiThread{label.text="Banc interrompu. Données produit conservées."}
        }
    }
}
