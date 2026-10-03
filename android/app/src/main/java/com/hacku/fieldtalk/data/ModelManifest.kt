package com.hacku.fieldtalk.data

import android.content.Context
import com.hacku.fieldtalk.domain.ModelReadiness
import com.hacku.fieldtalk.domain.ModelReadinessProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

class ManifestModelReadinessProvider(private val context: Context) : ModelReadinessProvider {
    override suspend fun inspect(): ModelReadiness = withContext(Dispatchers.IO) {
        val manifestFile = File(context.filesDir, "models/manifest.json")
        if (!manifestFile.isFile) {
            return@withContext ModelReadiness(false, false, false, listOf("Model manifest is missing."))
        }

        runCatching {
            val root = JSONObject(manifestFile.readText())
            val components = root.getJSONArray("components")
            val readiness = mutableMapOf("asr" to true, "translation" to true, "tts" to true)
            val details = mutableListOf<String>()
            for (index in 0 until components.length()) {
                val component = components.getJSONObject(index)
                val type = component.getString("type")
                val files = component.getJSONArray("files")
                for (fileIndex in 0 until files.length()) {
                    val entry = files.getJSONObject(fileIndex)
                    val modelFile = File(manifestFile.parentFile, entry.getString("path"))
                    val expected = entry.getString("sha256").lowercase()
                    val valid = modelFile.isFile && expected.length == 64 && sha256(modelFile) == expected
                    if (!valid) {
                        readiness[type] = false
                        details += "${entry.getString("path")} is missing or failed checksum validation."
                    }
                }
            }
            ModelReadiness(
                asrReady = readiness.getValue("asr"),
                translationReady = readiness.getValue("translation"),
                ttsReady = readiness.getValue("tts"),
                details = details,
            )
        }.getOrElse { ModelReadiness(false, false, false, listOf("Model manifest is invalid.")) }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
