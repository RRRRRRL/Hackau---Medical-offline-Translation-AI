# FieldTalk

A hackathon prototype for offline, turn-based speech translation between a first responder and a conscious patient, with an optional local AI transcript-review step.

FieldTalk is a communication aid, not a diagnostic or treatment system. It has not been clinically validated and does not replace a qualified interpreter. Confirm critical details with the speaker.

## Current scope

This README documents the `temp` branch, inspected at commit `fb65e2f`.

- Runs on one laptop using a browser interface, a Python backend and local model inference.
- Records or uploads a short utterance, displays the raw transcript, and allows editing before translation.
- Optionally asks a local language model to suggest transcript corrections.
- Keeps the raw transcript separate from the suggestion and requires explicit human confirmation in the review workflow.
- Translates confirmed text and generates spoken output using local models.
- Includes a separate baseline demo without the review stage.
- Native Android deployment is a separate branch, not this implementation.

### Language status

| Feature                  | Current status                                                                                                     |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| English and Mandarin ASR | Accepted by the current speech adapter; requires local model testing                                               |
| Russian ASR              | Known inconsistency: exposed in the UI/API, but the current `temp` ASR adapter rejects `ru`                        |
| Translation              | Inherits English, Chinese and Russian translation configuration, including Chinese/Russian routing through English |
| Piper TTS                | Configured English, Mandarin and Russian voices                                                                    |
| Local transcript review  | Accepts `en`, `zh` and `ru`; suggestions are unverified                                                            |

Do not describe Russian speech input as working until the adapter restriction is fixed and tested. Chinese support here means Mandarin, not validated Cantonese support. Translation depends on installed Argos packages; verify each intended direction on the demo laptop.

## Architecture

### Review workflow

```text
Browser microphone / uploaded recording
    -> FastAPI recognition endpoint
    -> faster-whisper raw transcript
    -> optional local LLM suggestion
    -> validation guards + visible differences
    -> user edits and confirms source text
    -> Argos Translate
    -> Piper WAV synthesis
    -> browser playback
```

The LLM reviews text, not the original audio. It is not the main translation engine, and its suggestions are not evidence that the transcript matches what was spoken.

### Technology stack

| Layer               | Implementation                                                            |
| ------------------- | ------------------------------------------------------------------------- |
| Frontend            | React, Vite, browser MediaRecorder and CSS                                |
| API                 | Python, FastAPI and Pydantic                                              |
| ASR                 | faster-whisper / CTranslate2; default multilingual Whisper base, CPU int8 |
| Translation         | Argos Translate with locally installed packages                           |
| TTS                 | Piper with cached in-process voice synthesis                              |
| Optional LLM        | Local llama-server with an OpenAI-compatible chat-completions endpoint    |
| Chinese review      | pypinyin tone-number rendering and OpenCC script normalization            |
| Proposal validation | Protected-value checks and Python difflib comparisons                     |

The repository does not pin an LLM weight/model identity in the review request. `fieldtalk-review` is the request's model label, not proof of which weights the running server loaded.

### Transcript-review safeguards

- Presents proposed corrections without automatically replacing the raw transcript.
- Checks protected numbers, units and selected negation expressions.
- Blocks proposals when normalized edit similarity falls below 0.65.
- Converts traditional Chinese to simplified Chinese before protected-value and similarity comparison.
- Ignores selected punctuation and whitespace when computing similarity, but displays differences between the actual texts.
- Keeps the original when the model requests repetition or the guards block its proposal.
- Supports an optional previous-question/topic field, limited to 200 characters.
- Adds pinyin and a Mandarin-specific prompt for Chinese review.
- Rejects malformed or incomplete model responses.

These are heuristic guards, not clinical validation. A similarity score is not an accuracy or confidence score. The guards do not guarantee that all medication, allergy or symptom changes are detected.

## Setup and launch

Commands below use Windows PowerShell from the repository root. Prepare dependencies and models while online. If an existing environment already works, reuse it rather than rebuilding it before the demo.

### 1. Get the temp branch

```powershell
git clone --branch temp https://github.com/RRRRRRL/Hackau---Medical-offline-Translation-AI.git
cd Hackau---Medical-offline-Translation-AI
```

### 2. Install dependencies

Example for a fresh environment with Python 3.12 installed:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt -r requirements-local.txt
.\.venv\Scripts\python.exe -m pip install pypinyin opencc-python-reimplemented
.\.venv\Scripts\python.exe -m pip check
cd frontend
npm ci
cd ..
```

The explicit pypinyin/OpenCC installation supplies imports used by the new review module; do not assume the older requirements files cover them. If another compatible OpenCC implementation is already installed, verify its `opencc.OpenCC("t2s.json")` API rather than installing conflicting implementations.

### 3. Prepare speech and translation models

```powershell
.\.venv\Scripts\python.exe -m scripts.download_models
```

The default desktop assets include:

- Whisper base under `models_local/whisper-base`.
- Installed Argos translation packages.
- Piper voice files under `models_local/voices`, with both `.onnx` and `.onnx.json` metadata.

Configured voices are `en_US-lessac-medium`, `zh_CN-huayan-medium` and `ru_RU-irina-medium`. Keep downloaded assets available after disconnecting the network. Do not commit model weights or private recordings.

### 4. Start the optional local LLM

Supply a compatible local GGUF model. The following is a launch template, not a pinned or verified model configuration:

```powershell
.\tools\llama\llama-server.exe -m "C:\path\to\your-model.gguf" --host 127.0.0.1 --port 8081
```

Use a model and chat template appropriate for the languages being demonstrated. The server must support `/health`, `/v1/chat/completions`, and the JSON-schema response format used by `backend/models/transcript_review.py`. Adjust the launch configuration for the selected model and installed server version.

The backend defaults to `http://127.0.0.1:8081`. Its review client permits only HTTP loopback IP addresses and disables proxies and redirects. To change the local port, set `FIELDTALK_LLM_URL` in the backend terminal.

The LLM is optional: the review page allows manual editing and confirmation without requesting a suggestion.

### 5. Start the review backend

In a separate terminal at the repository root:

```powershell
$env:FIELDTALK_MODE = 'local'
$env:FIELDTALK_LLM_URL = 'http://127.0.0.1:8081'
.\.venv\Scripts\python.exe -m uvicorn backend.review_app:app --host 127.0.0.1 --port 8000
```

Use `backend.review_app:app`, not just `backend.main:app`, to enable the review endpoints. Review endpoints require local mode and reject mock operation.

### 6. Start the review frontend

In another terminal:

```powershell
cd frontend
npx vite --config vite.review.config.js
```

Open the URL printed by Vite and append `/review.html`, normally [the local review page](http://127.0.0.1:5173/review.html). Allow microphone access. Backend port 8000 is not the frontend page.

### Demo workflow

1. Select source and target languages; start with English and Mandarin.
2. Record a short turn, upload a recording, or use the clearly labelled fictional text-only test.
3. Inspect the raw transcript.
4. Optionally enter the previous question/topic and request a local-model suggestion.
5. Keep the original, edit manually, or copy an acceptable suggestion into the editable text.
6. Check the text with the speaker, especially medication names, numbers, units and negation.
7. Tick the confirmation checkbox and translate.
8. Display the result and play the generated speech.

A fictional text-only test demonstrates review and translation, not ASR. Recording automatically stops after 30 seconds in the review UI. Review text is limited to 600 characters, and uploads are limited to 10 MB.

### Baseline demo and mock mode

For the original pipeline without transcript review:

```powershell
$env:FIELDTALK_MODE = 'local'
.\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Then run `npm run dev` from `frontend/` and open the root page. Do not run both backend commands on port 8000 simultaneously.

Setting `FIELDTALK_MODE` to `mock` runs the baseline routing demonstration with fixed text and tone audio. Mock mode does not demonstrate recognition, translation quality or real speech synthesis. The review workflow requires `local` mode.

## API and repository layout

### Review endpoints

| Endpoint                     | Purpose                                                                                                              |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `GET /api/review/health`     | Reports mode, local review-model reachability and clinical-validation status                                         |
| `POST /api/review/recognize` | Multipart audio and `source_language`; returns raw transcript and ASR timing                                         |
| `POST /api/review/suggest`   | JSON `text`, `source_language`, optional `question_context`; returns an unverified proposal and guard results        |
| `POST /api/review/translate` | JSON `original_text`, `confirmed_text`, language pair and `confirmed: true`; returns translation and local audio URL |

Proposal statuses include `suggested`, `unchanged`, `repeat` and `blocked`. The API confirmation field enforces an explicit request flag; it cannot verify whether the user actually checked the statement with the speaker.

The baseline retains `GET /health`, `POST /process_audio` and local audio serving. A healthy/reachable service does not prove accuracy or offline readiness.

### Key files

```text
backend/main.py                      Baseline API and audio serving
backend/review_app.py                Review-enabled application entry point
backend/review_routes.py             Review API and confirmation request validation
backend/models/asr.py                Speech recognition adapter
backend/models/translation.py        Argos translation adapter
backend/models/tts.py                Piper synthesis adapter
backend/models/transcript_review.py  Local LLM client, prompts and proposal guards
frontend/src/ReviewApp.jsx           Review, editing and confirmation UI
frontend/review.html                 Review page entry point
frontend/vite.review.config.js       Review development/build configuration
frontend/tests/                     Added review-guard and speech-adapter tests
scripts/download_models.py          Online speech/translation preparation
tools/llama/                        Desktop llama runtime tools
models_local/                       Local downloaded model assets (Git ignored)
generated_audio/                    Generated WAV output (Git ignored)
```

## Verification and limitations

### Check services

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/review/health | ConvertTo-Json -Depth 5
Invoke-RestMethod http://127.0.0.1:8000/health | ConvertTo-Json -Depth 5
```

### Run tests and build

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m pytest frontend/tests -q
cd frontend
npx vite build --config vite.review.config.js
cd ..
```

Tests include mocks and dependency stubs; passing tests does not establish real-model accuracy. Some review tests predate the newer prompt/pinyin/OpenCC changes and may need updating. Inspect failures rather than assuming the branch passes.

### Offline demo checklist

1. Complete all dependency and model downloads while online, including the optional LLM weights.
2. Stop the services, disconnect Wi-Fi/Ethernet, then restart the local LLM, backend and frontend.
3. Reload the review page and test recognition, optional review, confirmed translation and speech playback.
4. Test each intended language direction using fictional statements and consenting speakers.
5. Record failures and observed timings; use an OS network monitor before asserting absence of external traffic.

The system is turn-based, not simultaneous interpretation. Backend timings exclude recording, human confirmation and browser playback. First-use model initialization may add delay. No recognition, translation or latency guarantee is made.

### Known issues and troubleshooting

| Problem                         | Action                                                                                            |
| ------------------------------- | ------------------------------------------------------------------------------------------------- |
| Review routes return 404        | Launch `backend.review_app:app` and use the review Vite configuration                             |
| Review rejects mock mode        | Restart with `FIELDTALK_MODE=local`                                                               |
| Missing pypinyin/opencc import  | Install the review dependencies in the same virtual environment                                   |
| Review model unavailable        | Check local server, loopback URL, port and `/health`                                              |
| Invalid or truncated suggestion | Keep the original or repeat a shorter turn; inspect server/schema compatibility                   |
| Russian recognition rejected    | Current ASR language validation excludes `ru`; fix and test before presenting Russian voice input |
| Missing translation package     | Prepare the required Argos route online, then repeat offline testing                              |
| Missing Piper voice             | Check both `.onnx` and `.onnx.json` assets                                                        |
| `synthesize_wav` missing        | Verify the Piper version required by `requirements-local.txt`                                     |
| Fixed allergy text and tone     | The baseline backend is running in mock mode                                                      |

### Safety and privacy

Use fictional examples for the hackathon. Do not use private patient data or upload recordings/transcripts to the public repository.

Recognition uploads use temporary storage during processing. Generated speech WAV files remain on the backend disk until removed; this is not an entirely ephemeral system. Bind services to loopback for the single-laptop demo. The local LLM restriction does not by itself constitute a complete security or privacy audit.

The model sees text, not audio, so it can propose plausible but incorrect corrections. Human confirmation and heuristic guards do not establish medical accuracy. No diagnosis, treatment recommendation or clinically validated medical-information extraction is provided.

### Credits and source snapshot

Built with faster-whisper, Argos Translate, Piper, llama.cpp tooling, FastAPI, React, Vite, pypinyin and OpenCC. Review runtime and individual model/voice licenses separately before redistribution.

This documentation is based on source inspection, not a completed runtime acceptance test:

- [temp branch](https://github.com/RRRRRRL/Hackau---Medical-offline-Translation-AI/tree/temp)
- [Local review workflow introduction](https://github.com/RRRRRRL/Hackau---Medical-offline-Translation-AI/commit/8bad0b4c285bd62913d4038f4708f53dd43e368f)
- [Mandarin review prompt and context support](https://github.com/RRRRRRL/Hackau---Medical-offline-Translation-AI/commit/ef3e6ecdbd22765cae03f5c28a3cff40e1f7c3b7)
- [Chinese-normalized comparison and guard update](https://github.com/RRRRRRL/Hackau---Medical-offline-Translation-AI/commit/fb65e2f956e64171b6c8e111d34a2e2f865a2db4)
