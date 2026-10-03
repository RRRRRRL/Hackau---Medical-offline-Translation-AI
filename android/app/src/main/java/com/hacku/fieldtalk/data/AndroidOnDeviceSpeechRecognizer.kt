package com.hacku.fieldtalk.data

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer as AndroidSpeechRecognizer
import com.hacku.fieldtalk.domain.Language
import com.hacku.fieldtalk.domain.RecognitionResult
import com.hacku.fieldtalk.domain.SpeechRecognizer

/** Uses only Android's explicitly on-device recognition service (API 31+). */
class AndroidOnDeviceSpeechRecognizer(private val context: Context) : SpeechRecognizer {
    private var recognizer: AndroidSpeechRecognizer? = null

    override fun prepare(
        language: Language,
        onReady: () -> Unit,
        onProgress: (Int?) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            onError(IllegalStateException("On-device speech recognition requires Android 12 or newer."))
            return
        }
        if (!AndroidSpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            onError(IllegalStateException("No on-device speech recognizer is installed on this device."))
            return
        }
        val service = AndroidSpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        recognizer = service
        val intent = recognitionIntent(language)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            service.checkRecognitionSupport(intent, context.mainExecutor, object : RecognitionSupportCallback {
                override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                    if (recognitionSupport.installedOnDeviceLanguages.supports(language)) {
                        onReady()
                    } else {
                        requestModelDownload(service, intent, language, onReady, onProgress, onError)
                    }
                }

                override fun onError(error: Int) {
                    close()
                    onError(IllegalStateException("Could not check offline ${language.displayName} speech support (error $error)."))
                }
            })
        } else {
            close()
            onError(IllegalStateException("Install the offline ${language.displayName} speech model in the device's speech settings."))
        }
    }

    private fun requestModelDownload(
        service: AndroidSpeechRecognizer,
        intent: Intent,
        language: Language,
        onReady: () -> Unit,
        onProgress: (Int?) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            service.triggerModelDownload(intent, context.mainExecutor, object : ModelDownloadListener {
                override fun onProgress(completedPercent: Int) = onProgress(completedPercent)
                override fun onSuccess() {
                    verifyDownloadedModel(service, intent, language, onReady, onError)
                }
                override fun onScheduled() {
                    close()
                    onProgress(null)
                    onError(IllegalStateException("The ${language.displayName} speech model download was scheduled. Keep the emulator online, wait a few minutes, then try again."))
                }
                override fun onError(error: Int) {
                    close()
                    onError(IllegalStateException("Could not download the offline ${language.displayName} speech model (error $error). Check Play Store updates and internet access."))
                }
            })
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            service.triggerModelDownload(intent)
            close()
            onError(IllegalStateException("The ${language.displayName} speech model download was requested. Keep the device online, wait for completion, then try again."))
        }
    }

    private fun verifyDownloadedModel(
        service: AndroidSpeechRecognizer,
        intent: Intent,
        language: Language,
        onReady: () -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        service.checkRecognitionSupport(intent, context.mainExecutor, object : RecognitionSupportCallback {
            override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                if (recognitionSupport.installedOnDeviceLanguages.supports(language)) {
                    onReady()
                } else {
                    close()
                    onError(IllegalStateException("The ${language.displayName} speech model is downloading in the background. Keep the device online and try Start recording again when the download finishes."))
                }
            }

            override fun onError(error: Int) {
                close()
                onError(IllegalStateException("The ${language.displayName} model was requested but its installation could not be verified (error $error)."))
            }
        })
    }

    override fun start(
        language: Language,
        onResult: (RecognitionResult) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            "On-device speech recognition requires Android 12 or newer."
        }
        check(AndroidSpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            "No on-device speech recognizer is installed. Use a Google APIs/Play emulator image and install the offline ${language.displayName} speech model."
        }

        val service = recognizer ?: AndroidSpeechRecognizer.createOnDeviceSpeechRecognizer(context).also {
            recognizer = it
        }
        var finished = false
        service.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = Unit
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit
            override fun onPartialResults(partialResults: Bundle?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit

            override fun onError(error: Int) {
                if (finished) return
                finished = true
                close()
                onError(IllegalStateException(errorMessage(error, language)))
            }

            override fun onResults(results: Bundle) {
                if (finished) return
                finished = true
                val texts = results.getStringArrayList(AndroidSpeechRecognizer.RESULTS_RECOGNITION)
                val text = texts?.firstOrNull().orEmpty()
                if (text.isBlank()) {
                    close()
                    onError(IllegalStateException("No speech was recognized. Please try again."))
                    return
                }
                val confidence = results.getFloatArray(AndroidSpeechRecognizer.CONFIDENCE_SCORES)
                    ?.firstOrNull()
                    ?.takeIf { it >= 0f }
                close()
                onResult(RecognitionResult(text, confidence))
            }
        })
        service.startListening(recognitionIntent(language))
    }

    private fun recognitionIntent(language: Language) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language.recognitionLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

    private fun Language.recognitionLanguageTag(): String = when (this) {
        Language.ENGLISH -> "en-US"
        // Google's SODA language pack is advertised under this BCP-47 tag. Requesting
        // zh-CN returns ERROR_LANGUAGE_NOT_SUPPORTED even when Mandarin is available.
        Language.CHINESE -> "cmn-Hans-CN"
        Language.RUSSIAN -> "ru-RU"
    }

    private fun List<String>.supports(language: Language): Boolean {
        val requested = language.recognitionLanguageTag()
        return any { installed ->
            installed.equals(requested, ignoreCase = true) ||
                (language == Language.CHINESE && installed.equals("zh-CN", ignoreCase = true))
        }
    }

    override fun stop() {
        recognizer?.stopListening()
    }

    override fun close() {
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    private fun errorMessage(error: Int, language: Language): String = when (error) {
        AndroidSpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
            "The offline ${language.displayName} speech model is supported but not installed on this device."
        AndroidSpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ->
            "This device's on-device recognizer does not support ${language.displayName}. Update Android speech services or use typed input."
        AndroidSpeechRecognizer.ERROR_NO_MATCH -> "No speech was recognized. Please try again."
        AndroidSpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech was detected. Please try again."
        AndroidSpeechRecognizer.ERROR_AUDIO -> "The microphone could not capture audio."
        AndroidSpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission is required."
        AndroidSpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "The speech recognizer is busy. Please try again."
        else -> "On-device speech recognition failed (error $error)."
    }
}