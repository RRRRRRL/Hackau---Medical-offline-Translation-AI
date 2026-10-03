package com.hacku.fieldtalk.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hacku.fieldtalk.domain.Language

@Composable
fun TranslatorScreen(
    state: TranslatorUiState,
    onSourceSelected: (Language) -> Unit,
    onTargetSelected: (Language) -> Unit,
    onSwap: () -> Unit,
    onRecordingToggle: () -> Unit,
    onTranscriptChanged: (String) -> Unit,
    onTranslate: () -> Unit,
    onReplay: () -> Unit,
    onDismissError: () -> Unit,
) {
    Scaffold(containerColor = MaterialTheme.colorScheme.background) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            Column(
                Modifier.widthIn(max = 680.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text("FieldTalk", fontSize = 34.sp, fontWeight = FontWeight.Bold)
                Text("Local ambulance communication", color = MaterialTheme.colorScheme.secondary)
                SafetyCard()
                ModelCard(state)
                LanguageRow(state, onSourceSelected, onTargetSelected, onSwap)
                RecordingCard(state, onRecordingToggle)
                OutlinedTextField(
                    value = state.transcript,
                    onValueChange = onTranscriptChanged,
                    label = { Text("Original transcript — review before translating") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 3,
                    enabled = !state.busy && state.stage != WorkStage.RECORDING,
                )
                Button(
                    onClick = onTranslate,
                    enabled = state.transcript.isNotBlank() && !state.busy && state.stage != WorkStage.RECORDING,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(if (state.stage == WorkStage.TRANSLATING) "Translating locally…" else "Translate") }
                if (state.translation.isNotBlank()) TranslationCard(state, onReplay)
                Text(
                    "Medical accuracy has not been clinically validated. No transcript or audio is intentionally retained after use.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
                Spacer(Modifier.height(20.dp))
            }
        }
    }
    state.error?.let {
        AlertDialog(
            onDismissRequest = onDismissError,
            confirmButton = { TextButton(onClick = onDismissError) { Text("OK") } },
            title = { Text("Unable to continue") },
            text = { Text(it) },
        )
    }
}

@Composable
private fun SafetyCard() {
    Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(12.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Communication aid only", fontWeight = FontWeight.Bold)
            Text("Confirm critical details with the patient. This app does not diagnose, recommend treatment, or replace a qualified interpreter.")
        }
    }
}

@Composable
private fun ModelCard(state: TranslatorUiState) {
    val readiness = state.readiness
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(if (readiness.allReady) "Offline models verified" else "Offline setup required", fontWeight = FontWeight.Bold)
            Text("ASR ${mark(readiness.asrReady)}   Translation ${mark(readiness.translationReady)}   TTS ${mark(readiness.ttsReady)}")
            if (!readiness.allReady) Text("Copy converted mobile models and their checksums to app storage. See MODEL_SETUP.md.", color = MaterialTheme.colorScheme.secondary)
        }
    }
}

private fun mark(ready: Boolean) = if (ready) "✓" else "—"

@Composable
private fun LanguageRow(
    state: TranslatorUiState,
    onSourceSelected: (Language) -> Unit,
    onTargetSelected: (Language) -> Unit,
    onSwap: () -> Unit,
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
        Box(Modifier.weight(1f)) { LanguageMenu("From", state.source, Language.entries, onSourceSelected) }
        OutlinedButton(onClick = onSwap, enabled = !state.busy) { Text("⇄") }
        Box(Modifier.weight(1f)) { LanguageMenu("To", state.target, state.source.validTargets(), onTargetSelected) }
    }
}

@Composable
private fun LanguageMenu(label: String, selected: Language, choices: List<Language>, onSelected: (Language) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Text(label, style = MaterialTheme.typography.labelMedium)
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) { Text(selected.displayName) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            choices.forEach { language ->
                DropdownMenuItem(text = { Text(language.displayName) }, onClick = { expanded = false; onSelected(language) })
            }
        }
    }
}

@Composable
private fun RecordingCard(state: TranslatorUiState, onRecordingToggle: () -> Unit) {
    Card {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                when (state.stage) {
                    WorkStage.PREPARING_ASR -> state.modelDownloadProgress?.let { "Downloading offline speech model… $it%" }
                        ?: "Checking offline speech model…"
                    WorkStage.RECORDING -> "Recording… speak clearly, then stop."
                    WorkStage.RECOGNIZING -> "Recognizing speech locally…"
                    WorkStage.CHECKING_MODELS -> "Checking local models…"
                    else -> "Tap once to start recording and tap again to stop, or type a message below."
                },
            )
            Button(
                onClick = onRecordingToggle,
                enabled = state.stage == WorkStage.RECORDING || !state.busy,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (state.stage == WorkStage.RECORDING) "Stop recording" else "Start recording")
            }
        }
    }
}

@Composable
private fun TranslationCard(state: TranslatorUiState, onReplay: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Translation", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.secondary)
            Text(state.translation, fontSize = 24.sp, fontWeight = FontWeight.Medium)
            OutlinedButton(onClick = onReplay, enabled = !state.busy) {
                Text(if (state.stage == WorkStage.SPEAKING) "Speaking…" else "Speak translation offline")
            }
        }
    }
}
