# FieldTalk

Offline, turn-based speech translation prototype for communication between a first responder and a conscious patient. Built for HacKU 2026 Deep Tech: The Capability That Hasn't Travelled.

FieldTalk translates communication; it does not diagnose, recommend treatment, or replace a qualified interpreter. Confirm critical details with the patient. Medical accuracy has not been clinically validated.

## Current scope

- Laptop pipeline is still available (`frontend` + `backend`) for local demo/testing.
- Android React Native app now lives at `mobile/app` and is the canonical mobile source tree.
- Mobile app supports English, Mandarin Chinese, and Russian (`en`, `zh`, `ru`) in all six translation directions.
- Mobile workflow is turn-based Start/Stop recording. Recognition begins only after Stop (or automatic 30s cap stop).
- Inference is device-local only: microphone WAV -> whisper.rn/whisper.cpp -> editable transcript -> ML Kit translation -> Android offline TTS.

## Architecture

```text
React/Vite microphone UI
  -> multipart POST /process_audio
  -> FastAPI: ASR -> translation -> TTS
  -> result JSON + local WAV URL
  -> browser playback
```

| Component | Implementation |
| --- | --- |
| ASR | Multilingual faster-whisper base, local CPU int8 |
| Translation | Direct installed Argos Translate packages |
| TTS | Cached in-process PiperVoice synthesis |
| Frontend | React/Vite on localhost |

Keep these interfaces stable:

| Interface | Return |
| --- | --- |
| `speech_to_text(audio_path, language=None)` | ASRResult: text, language, confidence |
| `translate_and_extract(text, source_language, target_language)` | TranslationResult: translation, key_information |
| `text_to_speech(text, language)` | Local WAV Path |
| `POST /process_audio` | original_text, translation, confidence, key_information, audio_url, warning, timings_ms, mode |

Confidence is null when no calibrated utterance confidence is available. The emergency NLP hook currently returns an empty object.

## Repository structure

```text
backend/config.py          Paths, mode, voices, supported pairs
backend/main.py            API, health checks, audio serving
backend/models/            ASR, translation, TTS and NLP adapters
frontend/                  React/Vite microphone interface
scripts/download_models.py Online preparation of model assets
scripts/benchmark_speech.py ASR/TTS timing benchmark
 tests/                    Mock pipeline and dependency-stub tests
models_local/              Downloaded models, ignored by Git
 generated_audio/          Output WAV files, ignored by Git
 mobile/app/               Canonical React Native Android app (generated project + native bridge)
```

## Android (React Native, canonical at `mobile/app`)

> Use a **fresh clone in a different local folder** so you do not overwrite your conflicted nested checkout.

### Fresh clone (PowerShell)

```powershell
cd C:\dev
git clone --branch feature/android-prototype https://github.com/RRRRRRL/Hackau---Medical-offline-Translation-AI.git Hackau-android-clean
cd .\Hackau-android-clean\mobile\app
```

### Install JS deps and offline ASR asset

Run from `mobile/app`:

```powershell
npm ci
.\scripts\setup-android.ps1
.\scripts\validate-android-model.ps1
```

What setup does:
- Creates `android/app/src/main/assets` if missing.
- Downloads **official multilingual** `ggml-tiny.bin` from `ggerganov/whisper.cpp`.
- Rejects empty/HTML downloads.
- Stores computed checksum + source in `ggml-tiny.metadata.json`.
- Keeps model weights out of Git (`ggml-*.bin` is ignored).

### Authorize adb + run debug build (Metro-dependent)

From `mobile/app`:

```powershell
adb devices
npm run android
```

Accept USB debugging prompt on phone. Debug mode needs Metro (`npm start`) and is not standalone offline proof.

### One-time online preparation in app

1. Tap **Prepare translation (online only)** (downloads required ML Kit language models).
2. In Android TTS settings install offline voices:
   - English (`en-US`)
   - Mandarin Chinese (`zh-CN`)
   - Russian (`ru-RU`)
3. Tap **Load offline models**.
4. Pick source/target pair, Start, Stop, edit transcript, Translate, Speak.

Pair-specific readiness is enforced. Missing Russian voice does not block English/Chinese turns.

### Standalone APK / bundle (no Metro)

From `mobile/app`:

```powershell
npm run android:release-apk
npm run android:release-bundle
```

- Release uses explicit **debug signing config** only (development/non-production).
- Do **not** add private production keystores to this repository.
- Install release APK with `adb install -r .\android\app\build\outputs\apk\release\app-release.apk`.
- Verify cold launch in airplane mode (Metro off, USB disconnected).

### Android acceptance checklist (offline)

- [ ] Airplane mode cold launch works without Metro/laptop.
- [ ] All six directions tested (`en↔zh`, `en↔ru`, `zh↔ru`).
- [ ] Translation button works only after explicit online preparation.
- [ ] Recording cancellation/backgrounding is reflected in UI.
- [ ] Empty/cancelled turns do not run inference.
- [ ] Transcript edit or language switch invalidates stale translation.
- [ ] Offline TTS errors are explicit for missing/network-only voices.
- [ ] Sensitive data is not logged; temporary WAV files are cleaned after successful/failed/cancelled turns (process crashes can still leave cache leftovers).

### Mobile troubleshooting

| Symptom | Action |
| --- | --- |
| `verifyWhisperAsset` Gradle error | Run `.\scripts\setup-android.ps1` from `mobile/app` and retry |
| `ggml-tiny.bin` checksum mismatch | Re-run setup script; it rewrites model + metadata atomically |
| `Missing translation model(s)` in app | Tap **Prepare translation (online only)** while connected to Wi-Fi |
| `Install an offline ... voice` | Install the exact offline voice in Android TTS settings |
| Playback stopped/error | Use Stop playback, then retry after confirming TTS engine initialization |
| Microphone denied/read failure | Grant RECORD_AUDIO permission and retry short turns |

## Prepare the laptop

The commands below use Windows PowerShell from the repository root. Internet is required for dependency and model preparation. Use a current Node.js LTS release compatible with Vite. Python 3.11 or 3.12 is a conservative starting point for a new environment; an existing working environment need not be replaced. Native package wheel availability depends on Python/platform.

For a fresh checkout:

```powershell
git clone --branch test https://github.com/RRRRRRL/Hackau---Medical-offline-Translation-AI.git
cd Hackau---Medical-offline-Translation-AI
```

For a fresh environment (example using installed Python 3.12):

```powershell
py -3.12 -m venv .venv
```

If `.venv` already exists, use it instead of recreating it. Activation is optional because these commands explicitly select its interpreter.

```powershell
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt -r requirements-local.txt
.\.venv\Scripts\python.exe -m pip check
cd frontend
npm ci
cd ..
```

`requirements-local.txt` includes `piper-tts>=1.3,<2` for the synthesize_wav API and `av>=16,<19` to avoid the PyAV 19 metadata_errors incompatibility with faster-whisper 1.2.1. Stop and inspect installation errors before continuing. Do not use a different global Python/pip to install backend dependencies.

Download assets while online:

```powershell
.\.venv\Scripts\python.exe -m scripts.download_models
```

This prepares:

- Multilingual Whisper base in `models_local/whisper-base`.
- Argos packages en->zh, zh->en, en->ru and ru->en.
- Piper voices `en_US-lessac-medium`, `zh_CN-huayan-medium`, `ru_RU-irina-medium`, each with `.onnx` and `.onnx.json` files in `models_local/voices`.

Keep all downloaded model files. Do not commit weights or patient recordings. The setup script performs network downloads; inference adapters load local assets.

## Run real translation

Terminal 1, repository root:

```powershell
$env:FIELDTALK_MODE = 'local'
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Terminal 2, repository root:

```powershell
cd frontend
npm run dev
```

Open the URL printed by Vite, normally http://127.0.0.1:5173. Use the frontend URL, not backend port 8000, and allow microphone access. Select a supported direction, record a short utterance, stop, and inspect both texts. If autoplay is blocked, use the audio player's Play button. Do not record while output speech is playing.

Example: English -> Russian, say "Where does it hurt?"; then reverse the direction with a consenting Russian speaker. Repeat English <-> Chinese. Use fictional examples, not patient records.

Check health in another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health | ConvertTo-Json -Depth 5
```

Expected mode is local. `ready: true` checks required asset/package presence; it does not prove successful inference, clinical accuracy, or absence of network traffic. Refresh the frontend after preparing assets because it fetches health on mount.

Stop the backend with Ctrl+C and restart after changing code or environment variables; the command above does not enable auto-reload.

## Mock demonstration

Start the backend with:

```powershell
$env:FIELDTALK_MODE = 'mock'
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Mock mode returns fixed allergy text and an audible tone, not recognized speech or translated spoken audio. The UI labels it MOCK DEMO. It checks routing and display only. The default mode is mock; always set local explicitly for real-model testing.

## Verify offline operation

1. Finish all installation and model downloads while online.
2. Stop both servers, disable Wi-Fi and disconnect Ethernet.
3. Restart both servers without rerunning downloads and reload the local frontend.
4. Complete all four supported directions and record observed failures and timings.
5. Use an OS network monitor if asserting that no external connections occur.

No latency guarantee is made. First use may include model initialization. `timings_ms` measures backend stages, not microphone recording, browser upload/playback or human confirmation time.

## Tests and benchmarks

Servers are not needed to run automated tests:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
cd frontend
npm run build
cd ..
```

The existing pipeline tests force mock mode; speech adapter tests use fake model objects. Passing them does not establish real model operation or medical accuracy.

Benchmark a real recording in local mode:

```powershell
$env:FIELDTALK_MODE = 'local'
.\.venv\Scripts\python.exe -m scripts.benchmark_speech --audio sample_en.wav --language en --runs 5 --out speech_en.csv
.\.venv\Scripts\python.exe -m scripts.benchmark_speech --audio sample_ru.wav --language ru --runs 5 --out speech_ru.csv
```

Use an existing recording and `en`, `zh` or `ru`. The benchmark measures ASR then TTS in the same language, excluding translation and browser playback. It reports first-call and subsequent timings; output speech files are removed by the benchmark. The CSV stores timings, not transcripts.

## Troubleshooting

| Symptom | Check or action |
| --- | --- |
| No module named faster_whisper | Install requirements-local.txt with `.venv\Scripts\python.exe -m pip` |
| av.open rejects metadata_errors | Reinstall `av>=16,<19`, run pip check, restart backend |
| Translation model en->ru missing | Rerun download_models online; check both Russian directions are installed |
| TTS assets missing | Check voice `.onnx` and `.onnx.json` files; rerun setup |
| synthesize_wav API missing | Install `piper-tts>=1.3,<2` in the backend environment |
| Fixed allergy text and tone | Backend is in mock mode; restart with FIELDTALK_MODE=local |
| Backend unavailable | Check backend terminal and port 8000; use Vite dev server for the UI |
| Microphone denied | Allow browser microphone permission and use localhost |
| No speech recognized | Repeat a short clear utterance; test the recording and local model |
| Ready but processing fails | Read the complete backend traceback; health only checks assets |

Model paths can be overridden with FIELDTALK_MODEL_DIR, FIELDTALK_ASR_DIR and FIELDTALK_VOICES_DIR. Restart after overrides. Confirm the running branch and imported files when debugging.

## Safety, privacy and limitations

The backend is intended for one local demo user. Audio uploads are temporarily stored and removed after processing. Synthesized WAV files remain in generated_audio until manually deleted; this is not an all-ephemeral pipeline. The UI currently attempts playback automatically and has no transcript-edit/confirmation stage. Confirm critical statements separately. Do not upload private medical data to the public repository.

Evaluate negation, medication names, numbers, noise and unfamiliar speakers. Chinese voice output is Mandarin, not Cantonese validation. Accuracy and offline behavior must be demonstrated with actual models. Quick-question content is placeholder data and is not currently shown in the UI.

## Credits and licenses

- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- [Argos Translate](https://github.com/argosopentech/argos-translate)
- [Piper](https://github.com/OHF-Voice/piper1-gpl) and its [Python API](https://github.com/OHF-Voice/piper1-gpl/blob/main/docs/API_PYTHON.md)
- [Piper voice catalog](https://huggingface.co/rhasspy/piper-voices)
- [React Native](https://reactnative.dev/)
- [whisper.rn](https://github.com/mybigday/whisper.rn) and [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [Google ML Kit Translation](https://developers.google.com/ml-kit/language/translation/android)
- [Android TextToSpeech](https://developer.android.com/reference/android/speech/tts/TextToSpeech)
- FastAPI, React and Vite.

Review engine and individual model/voice licenses separately before redistribution. AI coding assistance was used during development; the team remains responsible for validation and explaining the implementation.