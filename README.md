# FieldTalk

FieldTalk is a 48-hour hackathon prototype for offline speech translation between a first responder and a conscious patient. It translates communication; it does not diagnose, recommend treatment, or make medical decisions. Confirm critical details with the patient.

## Current scope

English ↔ Chinese speech translation. The frontend now includes Quick Questions, Yes / No, Free Conversation, and an explicit Handoff workflow. Russian and medical NLP still require teammate integration. See [frontend/README.md](frontend/README.md) for frontend behavior and limitations.

## Architecture and stable interfaces

```text
React/Vite emergency communication workflows
                ↓ multipart POST /process_audio
FastAPI orchestrator (backend/main.py)
                ↓
ASR → Translation (+ empty NLP hook) → TTS
                ↓
JSON result + local /audio/{id}.wav → browser playback
```

Keep these public interfaces and response keys stable when replacing a model:

| Module | Function | Return |
| --- | --- | --- |
| ASR | `speech_to_text(audio_path, language=None)` | `{text: str, language: str, confidence: float or null}` |
| Translation | `translate_and_extract(text, source_language, target_language)` | `{translation: str, key_information: object}` |
| TTS | `text_to_speech(text, language)` | Path to a local WAV file |
| API | `POST /process_audio` multipart fields `audio`, `source_language`, `target_language` | `{original_text, translation, confidence, key_information, audio_url, warning, timings_ms, mode}` |

Language codes are `en` and `zh`. Confidence is `null` when the ASR model has no calibrated utterance confidence. The current emergency NLP hook returns `{}`. Do not infer an allergy, symptom, or confidence value from model output without a reviewed method.

## Repository structure

```text
backend/                 FastAPI, contracts, configuration, model adapters
backend/models/          asr.py, translation.py, tts.py, emergency_nlp.py
frontend/                React/Vite emergency workflow UI and frontend tests
data/                    Original quick-question seed content
scripts/download_models.py  Online setup for local model assets
tests/                   Mock interface and backend pipeline tests
models_local/             Downloaded ASR and Piper assets (Git ignored)
generated_audio/          Synthesized WAV files (Git ignored)
```

## Setup and mock baseline (Windows PowerShell)

Run these commands from the repository root. Python 3.10+ and Node.js 20+ are needed.

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
cd frontend
npm ci
cd ..
$env:FIELDTALK_MODE = 'mock'
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

In a second terminal:

```powershell
cd frontend
npm run dev
```

Open `http://127.0.0.1:5173`. The system status says **Demo mode**. For the mock speech path, choose Free Conversation, select **Responder · English**, hold the recording button, speak, and release. The mock returns fixed allergy text and an audible **tone**, not spoken Chinese. Mock speech cannot be added to Handoff. This stage verifies routing, file upload, response display, audio serving, and playback controls; it does not verify speech translation.

## Install real local models (internet needed once)

From the repository root, with the Python virtual environment created:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-local.txt
.\.venv\Scripts\python.exe -m scripts.download_models
```

The script downloads a multilingual faster-whisper `base` model to `models_local/whisper-base`, installs both direct Argos Translate packages (`en→zh`, `zh→en`), and downloads Piper voices `en_US-lessac-medium` and `zh_CN-huayan-medium` to `models_local/voices`. The script should be run only during setup. Its network access and disk use depend on the model providers. Do not commit the downloaded assets.

Piper's voice catalog and install command are documented in the [Piper CLI guide](https://github.com/OHF-Voice/piper1-gpl/blob/main/docs/CLI.md). The [faster-whisper project](https://github.com/SYSTRAN/faster-whisper) documents local model loading. [Argos Translate](https://github.com/argosopentech/argos-translate) documents downloadable offline language packages.

Start the real backend:

```powershell
$env:FIELDTALK_MODE = 'local'
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Start the frontend with `cd frontend; npm run dev` in another terminal. `GET http://127.0.0.1:8000/health` shows whether the required local assets are present. In local mode, ASR loads only from the local model directory, Argos translates from installed packages, and Piper reads local voice files. Inference code does not call a cloud API or download models.

## Test the complete pipeline

Run interface and mock backend tests:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
cd frontend
npm run build
```

For the real speech test, use the running local backend and frontend. Record **“I am allergic to penicillin.”** with English as source and Chinese as target. Check the recognized English text, Chinese translation, and played Chinese audio. Repeat in the opposite direction with a Chinese spoken phrase. Check the returned `timings_ms` or backend logs for ASR, translation, TTS, and total latency. There is no fixed expected latency; it depends on CPU and model warm-up.

## Verify without internet

1. Finish dependency and model downloads while online.
2. Start both servers and confirm `/health` returns `{"mode":"local","ready":true,...}`.
3. Disable Wi-Fi and unplug Ethernet or enable Airplane Mode.
4. Reload `http://127.0.0.1:5173` and run both directions again. The page should still load because Vite and FastAPI are local processes.
5. If you need strict proof of no network calls, monitor the processes with an OS network monitor while recording and processing.

The mock mode also works without internet but does **not** prove offline inference.

## Error handling and limitations

The UI reports microphone permission, empty recording, backend errors, and model failures. The API rejects unsupported pairs and empty/oversized audio. The local ASR result has `confidence: null`; Whisper's segment statistics are not a calibrated utterance confidence, so no confidence warning is generated. Model accuracy, medical terminology quality, voice intelligibility, and real offline operation must be checked with the downloaded models and a microphone. Generated WAV files remain on disk until manually removed. The backend is intended for a single local demo user.

Team members can work within `backend/models/asr.py`, `translation.py`, `tts.py`, `emergency_nlp.py`, or `frontend/` independently. Keep the tabled function signatures, language codes, and API response keys stable; coordinate any needed contract change before merging branches.
