package com.hacku.fieldtalk.data

import com.hacku.fieldtalk.domain.Language
import com.hacku.fieldtalk.domain.OfflineTranslator
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class MlKitOfflineTranslator : OfflineTranslator {
    override suspend fun translate(text: String, source: Language, target: Language): String {
        require(source.canTranslateTo(target)) { "Unsupported language pair" }
        val options = TranslatorOptions.Builder()
            .setSourceLanguage(source.mlKitCode())
            .setTargetLanguage(target.mlKitCode())
            .build()
        val client = Translation.getClient(options)
        try {
            // Download is attempted only to verify/provision the Play Services model. With no
            // INTERNET permission, an absent model fails rather than sending medical text away.
            awaitTask { success, failure ->
                client.downloadModelIfNeeded(DownloadConditions.Builder().build())
                    .addOnSuccessListener { success(Unit) }
                    .addOnFailureListener(failure)
            }
            return awaitTask { success, failure ->
                client.translate(text).addOnSuccessListener(success).addOnFailureListener(failure)
            }
        } catch (error: Exception) {
            throw IllegalStateException("The local ${source.displayName}–${target.displayName} translation model is not installed.", error)
        } finally {
            client.close()
        }
    }
}

private fun Language.mlKitCode(): String = when (this) {
    Language.ENGLISH -> TranslateLanguage.ENGLISH
    Language.CHINESE -> TranslateLanguage.CHINESE
    Language.RUSSIAN -> TranslateLanguage.RUSSIAN
}

private suspend fun <T> awaitTask(register: ((T) -> Unit, (Exception) -> Unit) -> Unit): T =
    suspendCancellableCoroutine { continuation ->
        register(
            { value -> if (continuation.isActive) continuation.resume(value) },
            { error -> if (continuation.isActive) continuation.resumeWithException(error) },
        )
    }
