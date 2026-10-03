package com.hacku.fieldtalk.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.hacku.fieldtalk.data.AndroidOnDeviceSpeechRecognizer
import com.hacku.fieldtalk.data.AndroidOfflineTts
import com.hacku.fieldtalk.data.ManifestModelReadinessProvider
import com.hacku.fieldtalk.data.MlKitOfflineTranslator
import com.hacku.fieldtalk.domain.Language
import com.hacku.fieldtalk.domain.ModelReadiness
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class WorkStage { CHECKING_MODELS, PREPARING_ASR, READY, RECORDING, RECOGNIZING, TRANSLATING, SPEAKING, ERROR }

data class TranslatorUiState(
    val source: Language = Language.ENGLISH,
    val target: Language = Language.CHINESE,
    val stage: WorkStage = WorkStage.CHECKING_MODELS,
    val transcript: String = "",
    val translation: String = "",
    val confidence: Float? = null,
    val modelDownloadProgress: Int? = null,
    val readiness: ModelReadiness = ModelReadiness(false, false, false),
    val error: String? = null,
) {
    val busy: Boolean get() = stage in setOf(WorkStage.PREPARING_ASR, WorkStage.RECOGNIZING, WorkStage.TRANSLATING, WorkStage.SPEAKING)
}

class TranslatorViewModel(application: Application) : AndroidViewModel(application) {
    private val readinessProvider = ManifestModelReadinessProvider(application)
    private val recognizer = AndroidOnDeviceSpeechRecognizer(application)
    private val translator = MlKitOfflineTranslator()
    private val synthesizer = AndroidOfflineTts(application)

    private val _state = MutableStateFlow(TranslatorUiState())
    val state: StateFlow<TranslatorUiState> = _state.asStateFlow()

    init { refreshReadiness() }

    fun refreshReadiness() = viewModelScope.launch {
        val readiness = readinessProvider.inspect()
        _state.update { it.copy(readiness = readiness, stage = WorkStage.READY, error = null) }
    }

    fun selectSource(language: Language) {
        val target = if (language.canTranslateTo(_state.value.target)) _state.value.target else language.validTargets().first()
        _state.update { it.copy(source = language, target = target, transcript = "", translation = "", error = null) }
    }

    fun selectTarget(language: Language) {
        if (_state.value.source.canTranslateTo(language)) {
            _state.update { it.copy(target = language, translation = "", error = null) }
        }
    }

    fun swapLanguages() {
        val current = _state.value
        selectSource(current.target)
    }

    fun startRecording() {
        _state.update { it.copy(stage = WorkStage.PREPARING_ASR, modelDownloadProgress = null, error = null) }
        recognizer.prepare(
            language = _state.value.source,
            onReady = ::beginRecognition,
            onProgress = { progress -> _state.update { it.copy(modelDownloadProgress = progress) } },
            onError = ::showError,
        )
    }

    private fun beginRecognition() {
        runCatching {
            recognizer.start(
                language = _state.value.source,
                onResult = { result ->
                    _state.update { it.copy(stage = WorkStage.READY, transcript = result.text, confidence = result.confidence) }
                },
                onError = ::showError,
            )
        }
            .onSuccess {
                _state.update { it.copy(stage = WorkStage.RECORDING, transcript = "", translation = "", error = null) }
            }
            .onFailure(::showError)
    }

    fun stopAndRecognize() {
        _state.update { it.copy(stage = WorkStage.RECOGNIZING) }
        runCatching { recognizer.stop() }.onFailure(::showError)
    }

    fun updateTranscript(text: String) = _state.update { it.copy(transcript = text, translation = "", error = null) }

    fun translate() = viewModelScope.launch {
        val snapshot = _state.value
        if (snapshot.transcript.isBlank()) return@launch showError(IllegalArgumentException("Enter or record a message first."))
        _state.update { it.copy(stage = WorkStage.TRANSLATING, error = null) }
        runCatching { translator.translate(snapshot.transcript.trim(), snapshot.source, snapshot.target) }
            .onSuccess { output -> _state.update { it.copy(stage = WorkStage.READY, translation = output) } }
            .onFailure(::showError)
    }

    fun replay() = viewModelScope.launch {
        val snapshot = _state.value
        if (snapshot.translation.isBlank()) return@launch
        _state.update { it.copy(stage = WorkStage.SPEAKING, error = null) }
        runCatching { synthesizer.speak(snapshot.translation, snapshot.target) }
            .onSuccess { _state.update { it.copy(stage = WorkStage.READY) } }
            .onFailure(::showError)
    }

    fun dismissError() = _state.update { it.copy(stage = WorkStage.READY, error = null) }

    private fun showError(throwable: Throwable) {
        _state.update { it.copy(stage = WorkStage.ERROR, error = throwable.message ?: "Operation failed.") }
    }

    override fun onCleared() {
        recognizer.close()
        synthesizer.close()
        super.onCleared()
    }
}
