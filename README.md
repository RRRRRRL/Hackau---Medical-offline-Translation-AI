# FieldTalk

Offline, turn-based speech translation prototype for communication between a first responder and a conscious patient. Built for HacKU 2026 Deep Tech: The Capability That Hasn't Travelled.

FieldTalk translates communication; it does not diagnose, recommend treatment, or replace a qualified interpreter. Confirm critical details with the patient. Medical accuracy has not been clinically validated.

## Current scope

- Runs locally on one laptop: browser UI, Python backend, and model inference.
- Supports English <-> Mandarin Chinese, English <-> Russian, and Chinese <-> Russian.
- Language codes: `en`, `zh`, `ru`. Chinese <-> Russian is translated through an English pivot (ru -> en -> zh) because no direct Argos package exists.
- Press Start recording, speak, then press Stop recording. Processing begins after recording stops; this is not simultaneous interpretation or streaming captions.
- Phone deployment is future work, not part of this implementation.

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
```

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
- FastAPI, React and Vite.

Review engine and individual model/voice licenses separately before redistribution. AI coding assistance was used during development; the team remains responsible for validation and explaining the implementation.