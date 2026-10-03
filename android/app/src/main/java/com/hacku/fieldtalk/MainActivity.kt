package com.hacku.fieldtalk

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.hacku.fieldtalk.ui.TranslatorScreen
import com.hacku.fieldtalk.ui.TranslatorViewModel
import com.hacku.fieldtalk.ui.theme.FieldTalkTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            FieldTalkTheme {
                val viewModel: TranslatorViewModel = viewModel()
                val state by viewModel.state.collectAsStateWithLifecycle()
                val context = LocalContext.current
                val permissionLauncher = rememberLauncherForActivityResult(
                    ActivityResultContracts.RequestPermission(),
                ) { granted -> if (granted) viewModel.startRecording() }

                TranslatorScreen(
                    state = state,
                    onSourceSelected = viewModel::selectSource,
                    onTargetSelected = viewModel::selectTarget,
                    onSwap = viewModel::swapLanguages,
                    onRecord = {
                        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                            viewModel.startRecording()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    },
                    onStop = viewModel::stopAndRecognize,
                    onTranscriptChanged = viewModel::updateTranscript,
                    onTranslate = viewModel::translate,
                    onReplay = viewModel::replay,
                    onDismissError = viewModel::dismissError,
                )
            }
        }
    }
}
