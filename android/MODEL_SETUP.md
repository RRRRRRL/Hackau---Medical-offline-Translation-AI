# FieldTalk offline model setup

This guide explains which local models FieldTalk uses and how to prepare a device.
FieldTalk contains no `INTERNET` permission and cannot send medical content to an
application server. Android/Google system components still need connectivity during
one-time model provisioning.

After provisioning, enable airplane mode, disable Wi-Fi, restart FieldTalk, and test
every required feature. Never claim offline readiness based only on a download message.

## Why the desktop models are not copied

The original project uses faster-whisper and Argos Translate CTranslate2 `model.bin`
files through Python. Those artifacts and runtimes are not directly Android-compatible.
The Piper `.onnx` weights also require an espeak-ng phonemizer and token metadata;
copying only the ONNX files would not produce valid speech.

## Translation

The Android app uses ML Kit's on-device translator for English↔Simplified Chinese and
English↔Russian. Translation runs locally after the required Play Services language
models have been provisioned. Because this app deliberately has no `INTERNET`
permission, provision the models on the test device before offline deployment (for
example with an approved connected preparation build or device-management process).
If a model is missing, the app fails closed and does not submit text elsewhere.
ML Kit models are general-domain and are not medically validated.

For fully app-bundled deployment, replace `MlKitOfflineTranslator` behind
`OfflineTranslator` with quantized Marian/OPUS-MT ONNX models and SentencePiece,
then add all artifacts and checksums to the manifest.

## Text-to-speech (TTS)

`AndroidOfflineTts` selects only Android `Voice` entries where
`isNetworkConnectionRequired == false`. Install offline English (US), Mandarin
Chinese, and Russian voices in the device's Text-to-speech settings during device
preparation. The app rejects missing/network-only voices.

The common route is:

**Settings → System → Languages & input → Text-to-speech output → engine settings →
Install voice data**

For reproducible Piper voices, port the original three voices using a maintained
Android Piper/sherpa-onnx package containing the ONNX model, `tokens.txt`, and
`espeak-ng-data`; then implement `SpeechSynthesizer`. Review model/runtime licenses
before distribution.

## Speech recognition (ASR)

On Android 12/API 31 or newer, `AndroidOnDeviceSpeechRecognizer` calls only
`createOnDeviceSpeechRecognizer`; it never falls back to the potentially networked
default recognizer. On Android 14/API 34 or newer, FieldTalk requests a missing model
through `triggerModelDownload` and displays progress before opening the microphone.
Keep the emulator online during this one-time preparation. Use a Google APIs or Google
Play image; model availability varies by image, and host microphone passthrough must
be enabled. A failed language download produces a clear error and typed translation
remains available.

To install language packs manually, open:

**Settings → System → Languages & input → Voice input → Speech Recognition and
Synthesis from Google → Offline speech recognition**

Under **All**, install English (United States), Chinese (Mandarin/China), and Russian
(Russia), then restart the device. An Android error 13 means the requested language is
supported but its local pack is unavailable. Update **Speech Recognition & Synthesis**
and **Google** through Play Store if the download menu is missing.

For a reproducible app-bundled ASR model on all API 26+ devices, replace this service
behind `SpeechRecognizer` with `whisper.cpp` JNI and a multilingual GGML/GGUF model
generated from original Whisper weights. The source project's CTranslate2 Whisper
`model.bin` cannot be used directly.

## Device manifest

Place `manifest.json` under the app-private `files/models/` directory and place model
artifacts beneath that directory. Start from `models/manifest.example.json`, replace
every placeholder checksum with the exact lowercase SHA-256, and keep prepared
artifacts out of logs and shared storage.

The UI can display **Offline setup required** until this optional checksum manifest is
complete. Android-managed models may still work, but each feature must be verified in
airplane mode.

## Final acceptance checklist

- [ ] English, Mandarin Chinese, and Russian ASR work in airplane mode.
- [ ] All four supported translation directions work in airplane mode.
- [ ] All three target languages speak through offline voices.
- [ ] Names, allergies, medicine terms, numbers, units, and negation were reviewed.
- [ ] No transcript, translation, or audio appears in logs.
- [ ] Critical details are confirmed by a human rather than trusted blindly.
