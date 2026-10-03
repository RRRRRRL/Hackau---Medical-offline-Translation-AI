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
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class FieldTalkModule(private val ctx: ReactApplicationContext) : ReactContextBaseJavaModule(ctx),
    LifecycleEventListener {

    override fun getName() = "FieldTalk"

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val translators = mutableMapOf<String, Translator>()
    private val recording = AtomicBoolean(false)
    private val active = AtomicBoolean(false)
    private val cancelRequested = AtomicBoolean(false)
    private val speech = mutableMapOf<String, Promise>()
    private var stopPromise: Promise? = null
    private var pendingRecordingPath: String? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val supportedCodes = setOf("en", "zh", "ru")

    init {
        ctx.addLifecycleEventListener(this)
        main.post {
            tts = TextToSpeech(ctx.applicationContext) { status ->
                ttsReady = status == TextToSpeech.SUCCESS
                if (!ttsReady) {
                    emit("playback_error", "TTS engine initialization failed")
                }
            }
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String) = Unit

                override fun onDone(utteranceId: String) {
                    main.post {
                        speech.remove(utteranceId)?.resolve(null)
                    }
                }

                @Deprecated("Compatibility override")
                override fun onError(utteranceId: String) {
                    main.post {
                        speech.remove(utteranceId)?.reject("TTS", "Synthesis failed")
                        emit("playback_error", "Synthesis failed")
                    }
                }

                override fun onError(utteranceId: String, errorCode: Int) {
                    main.post {
                        speech.remove(utteranceId)?.reject("TTS", "Synthesis failed: $errorCode")
                        emit("playback_error", "Synthesis failed: $errorCode")
                    }
                }

                override fun onStop(utteranceId: String, interrupted: Boolean) {
                    main.post {
                        speech.remove(utteranceId)?.reject("STOPPED", "Playback stopped")
                        emit("playback_stopped", "Playback stopped")
                    }
                }
            })
        }
    }

    private fun emit(type: String, message: String? = null) {
        if (!ctx.hasActiveCatalystInstance()) {
            return
        }
        val payload = Arguments.createMap().apply {
            putString("type", type)
            if (message != null) {
                putString("message", message)
            }
        }
        ctx
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit("FieldTalkEvent", payload)
    }

    private fun translator(source: String, target: String): Translator =
        translators.getOrPut("$source:$target") {
            Translation.getClient(
                TranslatorOptions.Builder()
                    .setSourceLanguage(source)
                    .setTargetLanguage(target)
                    .build()
            )
        }

    @ReactMethod
    fun prepareTranslation(promise: Promise) {
        val manager = RemoteModelManager.getInstance()
        val tasks = listOf("zh", "ru").map { language ->
            manager.download(
                TranslateRemoteModel.Builder(language).build(),
                DownloadConditions.Builder().requireWifi().build()
            )
        }
        Tasks.whenAll(tasks)
            .addOnSuccessListener { promise.resolve(null) }
            .addOnFailureListener { promise.reject("DOWNLOAD", it.message ?: "Model download failed", it) }
    }

    @ReactMethod
    fun checkTranslationPair(source: String, target: String, promise: Promise) {
        if (source !in supportedCodes || target !in supportedCodes || source == target) {
            promise.reject("PAIR", "Invalid language pair")
            return
        }

        val requiredModels = listOf(source, target).filter { it != "en" }.toSet()
        RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java)
            .addOnSuccessListener { models ->
                val downloaded = models.map { it.language }.toSet()
                if (downloaded.containsAll(requiredModels)) {
                    promise.resolve(null)
                } else {
                    val missing = requiredModels.minus(downloaded)
                    promise.reject(
                        "MODELS",
                        "Missing translation model(s): ${missing.joinToString(", ")}. Run Prepare translation online first."
                    )
                }
            }
            .addOnFailureListener { promise.reject("MODELS", it.message ?: "Cannot check translation models", it) }
    }

    @ReactMethod
    fun translate(text: String, source: String, target: String, promise: Promise) {
        if (text.isBlank() || source !in supportedCodes || target !in supportedCodes || source == target) {
            promise.reject("PAIR", "Invalid text or language pair")
            return
        }

        // Inference path intentionally avoids downloadModelIfNeeded.
        translator(source, target).translate(text)
            .addOnSuccessListener { promise.resolve(it) }
            .addOnFailureListener { promise.reject("TRANSLATE", it.message ?: "Translation failed", it) }
    }

    private fun languageLocale(language: String): Locale? = when (language) {
        "en" -> Locale.US
        "zh" -> Locale.SIMPLIFIED_CHINESE
        "ru" -> Locale("ru", "RU")
        else -> null
    }

    private fun selectVoice(language: String): android.speech.tts.Voice? {
        val locale = languageLocale(language) ?: return null
        return tts?.voices.orEmpty().asSequence().filter { voice ->
            !voice.isNetworkConnectionRequired &&
                voice.locale.language == locale.language &&
                !voice.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) &&
                (language != "zh" || voice.locale.country.equals("CN", ignoreCase = true))
        }.sortedWith(
            compareByDescending<android.speech.tts.Voice> { it.locale.country.equals(locale.country, ignoreCase = true) }
                .thenByDescending { it.quality }
                .thenBy { it.latency }
        ).firstOrNull()
    }

    @ReactMethod
    fun checkVoice(language: String, promise: Promise) {
        main.post {
            val locale = languageLocale(language)
            if (locale == null) {
                promise.reject("VOICE", "Unsupported TTS language: $language")
                return@post
            }
            if (!ttsReady) {
                promise.reject("TTS", "TTS engine is still initializing")
                return@post
            }
            if (selectVoice(language) == null) {
                promise.reject(
                    "VOICE",
                    "Install an offline ${locale.toLanguageTag()} voice in Android TTS settings (network voices are rejected)."
                )
                return@post
            }
            promise.resolve(null)
        }
    }

    @ReactMethod
    fun speak(text: String, language: String, promise: Promise) {
        main.post {
            val selected = selectVoice(language)
            if (!ttsReady) {
                promise.reject("TTS", "TTS engine is not ready")
                return@post
            }
            if (selected == null) {
                promise.reject("VOICE", "Offline voice unavailable for $language")
                return@post
            }
            val trimmed = text.trim()
            if (trimmed.isEmpty() || trimmed.length > TextToSpeech.getMaxSpeechInputLength()) {
                promise.reject("TTS", "Invalid text for speech")
                return@post
            }
            if (tts?.setVoice(selected) != TextToSpeech.SUCCESS) {
                promise.reject("TTS", "Unable to select voice")
                return@post
            }
            tts?.setSpeechRate(0.9f)
            val utteranceId = UUID.randomUUID().toString()
            speech[utteranceId] = promise
            if (tts?.speak(trimmed, TextToSpeech.QUEUE_FLUSH, Bundle(), utteranceId) != TextToSpeech.SUCCESS) {
                speech.remove(utteranceId)?.reject("TTS", "Playback request rejected")
                emit("playback_error", "Playback request rejected")
            }
        }
    }

    @ReactMethod
    fun stopSpeech(promise: Promise) {
        main.post {
            tts?.stop()
            speech.values.toList().forEach { it.reject("STOPPED", "Playback stopped") }
            speech.clear()
            promise.resolve(null)
            emit("playback_stopped", "Playback stopped")
        }
    }

    private fun fileSha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) {
                    break
                }
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun streamSha256(inputStream: InputStream): String {
        val digest = MessageDigest.getInstance("SHA-256")
        inputStream.use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) {
                    break
                }
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun readExpectedAssetHash(): String? = try {
        ctx.assets.open("ggml-tiny.metadata.json").use {
            val json = JSONObject(String(it.readBytes(), StandardCharsets.UTF_8))
            json.optString("sha256", "").trim().lowercase().ifEmpty { null }
        }
    } catch (_: Exception) {
        null
    }

    private fun copyAssetAtomically(destination: File): String {
        val temp = File(destination.parentFile, "${destination.name}.tmp")
        if (temp.exists()) {
            temp.delete()
        }

        ctx.assets.open("ggml-tiny.bin").use { input ->
            temp.outputStream().use { output ->
                input.copyTo(output)
            }
        }

        check(temp.length() > 0L) { "Model asset is empty" }
        if (destination.exists()) {
            destination.delete()
        }
        check(temp.renameTo(destination)) { "Atomic model copy failed" }

        return fileSha256(destination)
    }

    @ReactMethod
    fun modelPath(promise: Promise) {
        worker.execute {
            try {
                val destination = File(ctx.filesDir, "ggml-tiny.bin")
                val expectedHash = readExpectedAssetHash()
                val assetHash = expectedHash ?: streamSha256(ctx.assets.open("ggml-tiny.bin"))

                val shouldCopy = if (!destination.exists() || destination.length() <= 0L) {
                    true
                } else {
                    val currentHash = fileSha256(destination)
                    currentHash != assetHash
                }

                if (shouldCopy) {
                    val copiedHash = copyAssetAtomically(destination)
                    check(copiedHash == assetHash) { "Model copy integrity check failed" }
                }

                promise.resolve(destination.absolutePath)
            } catch (e: Exception) {
                promise.reject("ASR_MODEL", "Bundle multilingual ggml-tiny.bin in android/app/src/main/assets", e)
            }
        }
    }

    private fun writeWav(pcmBytes: ByteArray): File {
        val output = File(ctx.cacheDir, "fieldtalk-${UUID.randomUUID()}.wav")
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
            .putInt(36 + pcmBytes.size)
            .put("WAVEfmt ".toByteArray())
            .putInt(16)
            .putShort(1.toShort())
            .putShort(1.toShort())
            .putInt(16000)
            .putInt(32000)
            .putShort(2.toShort())
            .putShort(16.toShort())
            .put("data".toByteArray())
            .putInt(pcmBytes.size)
        output.outputStream().use {
            it.write(header.array())
            it.write(pcmBytes)
        }
        return output
    }

    @ReactMethod
    fun startRecording(promise: Promise) {
        if (ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            promise.reject("MIC", "Microphone permission required")
            return
        }

        if (!active.compareAndSet(false, true)) {
            promise.reject("MIC", "Recording already active")
            return
        }

        cancelRequested.set(false)
        recording.set(true)
        pendingRecordingPath?.let { stalePath ->
            File(stalePath).delete()
            pendingRecordingPath = null
        }

        worker.execute {
            var mic: AudioRecord? = null
            var started = false
            var capped = false
            try {
                val minBuffer = AudioRecord.getMinBufferSize(
                    16000,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                check(minBuffer > 0) { "Microphone buffer initialization failed" }
                val recorder = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    16000,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(minBuffer * 2, 6400)
                )
                mic = recorder
                check(recorder.state == AudioRecord.STATE_INITIALIZED) { "Microphone is unavailable" }
                recorder.startRecording()
                check(recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Microphone did not start" }

                promise.resolve(null)
                started = true

                val pcm = ByteArrayOutputStream()
                val buffer = ByteArray(3200)
                val capBytes = 16000 * 2 * 30
                while (recording.get()) {
                    val read = recorder.read(buffer, 0, buffer.size)
                    check(read >= 0) { "Microphone read failure" }
                    if (read > 0) {
                        pcm.write(buffer, 0, read)
                    }
                    if (pcm.size() >= capBytes) {
                        capped = true
                        recording.set(false)
                    }
                }

                val bytes = pcm.toByteArray()
                if (cancelRequested.get()) {
                    emit("recording_cancelled", "Recording cancelled")
                    synchronized(this) {
                        stopPromise?.reject("CANCELLED", "Recording cancelled")
                        stopPromise = null
                    }
                    return@execute
                }

                if (bytes.isEmpty()) {
                    synchronized(this) {
                        stopPromise?.reject("MIC", "No audio captured")
                        stopPromise = null
                    }
                    emit("recording_error", "No audio captured")
                    return@execute
                }

                val output = writeWav(bytes)
                val waitingPromise = synchronized(this) {
                    val value = stopPromise
                    stopPromise = null
                    value
                }

                if (waitingPromise != null) {
                    waitingPromise.resolve(output.absolutePath)
                } else {
                    pendingRecordingPath = output.absolutePath
                    if (capped) {
                        emit("recording_auto_stopped", "Recording capped at 30 seconds and stopped automatically")
                    }
                }
            } catch (e: Exception) {
                if (!started) {
                    promise.reject("MIC", e.message ?: "Microphone start failed", e)
                } else {
                    emit("recording_error", e.message ?: "Recording failed")
                }
                synchronized(this) {
                    stopPromise?.reject("MIC", e.message ?: "Recording failed", e)
                    stopPromise = null
                }
            } finally {
                recording.set(false)
                try {
                    mic?.stop()
                } catch (_: Exception) {
                }
                mic?.release()
                active.set(false)
            }
        }
    }

    @ReactMethod
    fun stopRecording(promise: Promise) {
        synchronized(this) {
            pendingRecordingPath?.let {
                pendingRecordingPath = null
                promise.resolve(it)
                return
            }

            if (!active.get()) {
                promise.reject("MIC", "No active recording")
                return
            }
            if (stopPromise != null) {
                promise.reject("MIC", "Recording is already stopping")
                return
            }

            stopPromise = promise
            recording.set(false)
        }
    }

    @ReactMethod
    fun cancelRecording() {
        cancelRecordingInternal("Recording cancelled")
    }

    private fun cancelRecordingInternal(message: String) {
        cancelRequested.set(true)
        recording.set(false)
        synchronized(this) {
            pendingRecordingPath?.let {
                File(it).delete()
                pendingRecordingPath = null
            }
            stopPromise?.reject("CANCELLED", message)
            stopPromise = null
        }
        emit("recording_cancelled", message)
    }

    @ReactMethod
    fun deleteRecording(path: String, promise: Promise) {
        val file = File(path)
        val cachePath = ctx.cacheDir.canonicalPath
        val parentPath = file.parentFile?.canonicalPath
        if (parentPath == cachePath && file.name.startsWith("fieldtalk-") && file.extension == "wav") {
            file.delete()
            promise.resolve(null)
        } else {
            promise.reject("PATH", "Not a FieldTalk recording")
        }
    }

    override fun onHostResume() = Unit

    override fun onHostPause() {
        cancelRecordingInternal("Recording cancelled because app moved to background")
        main.post { tts?.stop() }
    }

    override fun onHostDestroy() {
        cancelRecordingInternal("Recording cancelled because app is closing")
    }

    override fun invalidate() {
        ctx.removeLifecycleEventListener(this)
        cancelRecordingInternal("Module closed")
        worker.shutdown()
        translators.values.forEach { it.close() }
        translators.clear()
        main.post {
            ttsReady = false
            tts?.stop()
            tts?.shutdown()
            speech.values.toList().forEach { it.reject("CLOSED", "Module closed") }
            speech.clear()
        }
        super.invalidate()
    }
}
