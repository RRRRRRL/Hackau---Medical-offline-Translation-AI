# FieldTalk frontend

The frontend has four workflows: Quick Questions, Yes / No, Free Conversation, and Handoff. It supports the current backend pair only: English (`en`) and Chinese (`zh`). Russian is hidden until its backend models and language codes are integrated.

## API contract

- `GET /health` returns `mode`, `ready`, and `components` (`asr`, `translation`, `tts`). The UI labels `mock` as **Demo**, not offline ready.
- `POST /process_audio` sends multipart fields `audio`, `source_language`, `target_language`. It reads `original_text`, `translation`, `confidence`, `key_information`, `audio_url`, `warning`, `timings_ms`, and `mode` from the response. Errors use FastAPI `detail`.
- `GET /audio/{filename}` plays the returned WAV file. If playback fails, translated text stays visible.

The frontend does not synthesize a confidence value. The current `key_information` hook returns `{}`, so Critical Information stays hidden unless a later backend response contains entries. A patient speech result is added to Handoff only after a responder presses **Add patient statement**. Mock results, responder speech, and responses with recognition warnings cannot be added. Yes / No answers also require an explicit confirmation. Handoff data lives in browser memory and clears on reload or with **Clear this session**.

## Quick Questions

Seven English/Chinese phrases are stored in `src/phrases.js`. The first three came from `data/emergency_questions.json`; four more support the requested demo workflow. These phrases have **not** been clinically or linguistically reviewed. Arrange review before field use.

The current API has no text-to-speech endpoint. Quick Questions and Yes / No use browser speech synthesis only if the browser reports an installed `localService` voice for the patient language. Otherwise the large patient-language text remains visible and an audio warning appears. No cloud speech fallback is used. The integration teammate can later provide reviewed local audio assets or a backend speech endpoint.

## Run and verify

With the backend running on `127.0.0.1:8000`:

```powershell
cd frontend
npm ci
npm run dev
npm test
npm run build
```

Vite proxies `/health`, `/process_audio`, and `/audio` to the local backend in development. A production deployment must proxy those paths to the same local service. The frontend build itself makes no remote requests.
