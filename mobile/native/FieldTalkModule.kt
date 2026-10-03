package com.fieldtalk.speech

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.facebook.react.bridge.*
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.*
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class FieldTalkModule(private val ctx: ReactApplicationContext) : ReactContextBaseJavaModule(ctx) {
    override fun getName() = "FieldTalk"
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val recording = AtomicBoolean(false)
    private val active = AtomicBoolean(false)
    private var stopPromise: Promise? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val speech = mutableMapOf<String, Promise>()
    private val translators = mutableMapOf<String, Translator>()
    private val codes = setOf("en", "zh", "ru")

    init {
        main.post {
            tts = TextToSpeech(ctx.applicationContext) { status ->
                main.post {
                    ttsReady = status == TextToSpeech.SUCCESS
                    tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(id: String) {}
                        override fun onDone(id: String) { main.post { speech.remove(id)?.resolve(null) } }
                        @Deprecated("Compatibility override")
                        override fun onError(id: String) { main.post { speech.remove(id)?.reject("TTS", "Synthesis failed") } }
                        override fun onError(id: String, code: Int) { main.post { speech.remove(id)?.reject("TTS", "Synthesis failed: $code") } }
                        override fun onStop(id: String, interrupted: Boolean) { main.post { speech.remove(id)?.reject("STOPPED", "Playback stopped") } }
                    })
                }
            }
        }
    }
    private fun translator(source: String, target: String): Translator = translators.getOrPut("$source:$target") {
        Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(source).setTargetLanguage(target).build())
    }
    @ReactMethod fun prepareTranslation(p: Promise) {
        val manager = RemoteModelManager.getInstance()
        val tasks = listOf("zh", "ru").map {
            manager.download(TranslateRemoteModel.Builder(it).build(), DownloadConditions.Builder().requireWifi().build())
        }
        Tasks.whenAll(tasks).addOnSuccessListener { p.resolve(null) }.addOnFailureListener { p.reject("DOWNLOAD", it) }
    }
    @ReactMethod fun checkTranslation(p: Promise) {
        RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java)
            .addOnSuccessListener { models ->
                if (models.map { it.language }.toSet().containsAll(listOf("zh", "ru"))) p.resolve(null)
                else p.reject("MODELS", "Prepare Chinese and Russian translation models online first")
            }.addOnFailureListener { p.reject("MODELS", it) }
    }
    @ReactMethod fun translate(text: String, source: String, target: String, p: Promise) {
        if (source !in codes || target !in codes || source == target || text.isBlank()) {
            p.reject("PAIR", "Invalid text or language pair"); return
        }
        // No downloadModelIfNeeded call in the inference path.
        translator(source, target).translate(text).addOnSuccessListener { p.resolve(it) }.addOnFailureListener { p.reject("TRANSLATE", it) }
    }
    private fun voice(language: String): android.speech.tts.Voice? {
        val locale = when(language) { "en" -> Locale.US; "zh" -> Locale.SIMPLIFIED_CHINESE; "ru" -> Locale("ru", "RU"); else -> return null }
        return tts?.voices.orEmpty().filter {
            !it.isNetworkConnectionRequired && it.locale.language == locale.language &&
                (language != "zh" || it.locale.country == "CN") &&
                !it.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
        }.sortedWith(compareByDescending<android.speech.tts.Voice> { it.locale.country == locale.country }
            .thenByDescending { it.quality }.thenBy { it.latency }).firstOrNull()
    }
    @ReactMethod fun checkVoice(language: String, p: Promise) { main.post {
        if (!ttsReady) p.reject("TTS", "TTS engine is initializing or unavailable; retry")
        else if (voice(language) == null) p.reject("VOICE", "Install an offline $language voice in Android TTS settings")
        else p.resolve(null)
    } }
    @ReactMethod fun speak(text: String, language: String, p: Promise) { main.post {
        val selected = voice(language)
        if (!ttsReady || selected == null || text.isBlank() || text.length > TextToSpeech.getMaxSpeechInputLength()) {
            p.reject("TTS", "Offline voice unavailable or invalid text"); return@post
        }
        if (tts?.setVoice(selected) != TextToSpeech.SUCCESS) { p.reject("TTS", "Cannot select voice"); return@post }
        tts?.setSpeechRate(0.9f)
        val id = UUID.randomUUID().toString(); speech[id] = p
        if (tts?.speak(text, TextToSpeech.QUEUE_ADD, Bundle(), id) != TextToSpeech.SUCCESS) speech.remove(id)?.reject("TTS", "Request rejected")
    } }
    @ReactMethod fun stopSpeech(p: Promise) { main.post {
        tts?.stop(); speech.values.toList().forEach { it.reject("STOPPED", "Playback stopped") }; speech.clear(); p.resolve(null)
    } }
    @ReactMethod fun modelPath(p: Promise) {
        worker.execute {
            try {
                val dest = File(ctx.filesDir, "ggml-tiny.bin")
                if (!dest.exists()) {
                    val temp = File(ctx.filesDir, "ggml-tiny.bin.tmp")
                    try {
                        ctx.assets.open("ggml-tiny.bin").use { input -> temp.outputStream().use { input.copyTo(it) } }
                        check(temp.length() > 0 && temp.renameTo(dest)) { "Model copy failed" }
                    } finally { temp.delete() }
                }
                check(dest.length() > 0) { "Empty model" }; p.resolve(dest.absolutePath)
            } catch (e: Exception) { p.reject("ASR_MODEL", "Bundle multilingual ggml-tiny.bin in Android assets", e) }
        }
    }
    @ReactMethod fun startRecording(p: Promise) {
        if (ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) { p.reject("MIC", "Permission required"); return }
        if (!active.compareAndSet(false, true)) { p.reject("MIC", "Recording is active/finalizing"); return }
        recording.set(true)
        worker.execute {
            var mic: AudioRecord? = null
            try {
                val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                check(minimum > 0)
                val input = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum * 2, 6400))
                mic = input; check(input.state == AudioRecord.STATE_INITIALIZED)
                input.startRecording(); check(input.recordingState == AudioRecord.RECORDSTATE_RECORDING)
                p.resolve(null)
                val data = ByteArrayOutputStream(); val buffer = ByteArray(3200)
                while(recording.get()) {
                    val n = input.read(buffer, 0, buffer.size); check(n >= 0) { "Microphone read error" }
                    if (n > 0) data.write(buffer, 0, n)
                    // Bound memory; a capped recording waits for Stop before completing.
                    if (data.size() >= 16000 * 2 * 30) break
                }
                while (recording.get()) Thread.sleep(25)
                val finalPromise = synchronized(this) { val value = stopPromise; stopPromise = null; value }
                if (finalPromise != null) {
                    try {
                        check(data.size() > 0) { "No audio" }
                        val bytes = data.toByteArray(); val output = File(ctx.cacheDir, "fieldtalk-${UUID.randomUUID()}.wav")
                        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
                        header.put("RIFF".toByteArray()).putInt(36 + bytes.size).put("WAVEfmt ".toByteArray())
                            .putInt(16).putShort(1.toShort()).putShort(1.toShort()).putInt(16000).putInt(32000)
                            .putShort(2.toShort()).putShort(16.toShort()).put("data".toByteArray()).putInt(bytes.size)
                        output.outputStream().use { it.write(header.array()); it.write(bytes) }
                        finalPromise.resolve(output.absolutePath)
                    } catch(e: Exception) { finalPromise.reject("MIC", e) }
                }
            } catch(e: Exception) {
                p.reject("MIC", e)
                synchronized(this) { stopPromise?.reject("MIC", e); stopPromise = null }
            } finally {
                recording.set(false); try { mic?.stop() } catch (_: Exception) {}; mic?.release(); active.set(false)
            }
        }
    }
    @ReactMethod fun stopRecording(p: Promise) {
        synchronized(this) {
            if (!active.get() || stopPromise != null) { p.reject("MIC", "No recording or already stopping"); return }
            stopPromise = p; recording.set(false)
        }
    }
    @ReactMethod fun cancelRecording() {
        synchronized(this) { stopPromise?.reject("CANCELLED", "Recording cancelled"); stopPromise = null; recording.set(false) }
    }
    @ReactMethod fun deleteRecording(path: String, p: Promise) {
        val file = File(path)
        if (file.parentFile?.canonicalPath == ctx.cacheDir.canonicalPath && file.name.startsWith("fieldtalk-") && file.extension == "wav") { file.delete(); p.resolve(null) }
        else p.reject("PATH", "Not a FieldTalk recording")
    }
    override fun invalidate() {
        cancelRecording(); worker.shutdown()
        translators.values.forEach { it.close() }; translators.clear()
        main.post { ttsReady = false; tts?.stop(); tts?.shutdown(); speech.values.toList().forEach { it.reject("CLOSED", "Module closed") }; speech.clear() }
        super.invalidate()
    }
}
