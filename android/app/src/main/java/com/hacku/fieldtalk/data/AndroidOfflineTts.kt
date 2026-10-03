package com.hacku.fieldtalk.data

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.hacku.fieldtalk.domain.Language
import com.hacku.fieldtalk.domain.SpeechSynthesizer
import kotlinx.coroutines.CompletableDeferred
import java.util.UUID

/** Uses only a voice explicitly marked as not requiring a network connection. */
class AndroidOfflineTts(context: Context) : SpeechSynthesizer {
    private val initialized = CompletableDeferred<Unit>()
    private val completions = mutableMapOf<String, CompletableDeferred<Unit>>()
    private var engine: TextToSpeech? = null

    init {
        engine = TextToSpeech(context.applicationContext) { status ->
            val tts = engine
            if (status == TextToSpeech.SUCCESS && tts != null) {
                tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit
                    override fun onDone(utteranceId: String?) { utteranceId?.let { completions.remove(it)?.complete(Unit) } }
                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) { utteranceId?.let { completions.remove(it)?.completeExceptionally(IllegalStateException("TTS synthesis failed.")) } }
                    override fun onError(utteranceId: String?, errorCode: Int) = onError(utteranceId)
                })
                initialized.complete(Unit)
            } else {
                initialized.completeExceptionally(IllegalStateException("No local TTS engine is available."))
            }
        }
    }

    override suspend fun speak(text: String, language: Language) {
        initialized.await()
        val tts = requireNotNull(engine)
        val voice = tts.voices
            ?.filter { !it.isNetworkConnectionRequired && it.locale.language == language.locale.language }
            ?.maxByOrNull { it.quality }
            ?: throw IllegalStateException("Install an offline ${language.displayName} voice in Android TTS settings.")
        check(tts.setVoice(voice) == TextToSpeech.SUCCESS) { "Could not select the offline voice." }

        val utteranceId = UUID.randomUUID().toString()
        val completion = CompletableDeferred<Unit>()
        completions[utteranceId] = completion
        val result = tts.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), utteranceId)
        if (result != TextToSpeech.SUCCESS) {
            completions.remove(utteranceId)
            throw IllegalStateException("Could not start local speech synthesis.")
        }
        completion.await()
    }

    override fun stop() { engine?.stop() }

    override fun close() {
        completions.values.forEach { it.cancel() }
        completions.clear()
        engine?.shutdown()
        engine = null
    }
}
