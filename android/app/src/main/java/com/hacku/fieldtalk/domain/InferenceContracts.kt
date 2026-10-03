package com.hacku.fieldtalk.domain

data class RecognitionResult(val text: String, val confidence: Float?)

data class ModelReadiness(
    val asrReady: Boolean,
    val translationReady: Boolean,
    val ttsReady: Boolean,
    val details: List<String> = emptyList(),
) {
    val allReady: Boolean get() = asrReady && translationReady && ttsReady
}

interface SpeechRecognizer {
    fun prepare(
        language: Language,
        onReady: () -> Unit,
        onProgress: (Int?) -> Unit,
        onError: (Throwable) -> Unit,
    )
    fun start(
        language: Language,
        onResult: (RecognitionResult) -> Unit,
        onError: (Throwable) -> Unit,
    )
    fun stop()
    fun close()
}

interface OfflineTranslator {
    suspend fun translate(text: String, source: Language, target: Language): String
}

interface SpeechSynthesizer {
    suspend fun speak(text: String, language: Language)
    fun stop()
    fun close()
}

interface ModelReadinessProvider {
    suspend fun inspect(): ModelReadiness
}
