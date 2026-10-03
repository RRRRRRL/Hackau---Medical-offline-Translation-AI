# FieldTalk — Team Handoff

This document is for the next group members. It explains what the project is,
what has been built, how the two builds relate, and what remains.

## What FieldTalk is

Offline, turn-based **medical translation** for communication between a first
responder and a conscious patient. It translates a short spoken utterance
**speech → text → translated text → spoken audio**, all locally (no network).
It supports **English (en), Russian (ru) and Chinese (zh)** in all 6
directions. Chinese ↔ Russian has no bundled direct model, so it routes through
an **English pivot** (ru → en → zh).

> Safety: FieldTalk translates communication; it does not diagnose or recommend
> treatment. Confirm critical details with the patient. Not clinically validated.

## Two builds, one design

| | Laptop web app | Mobile Android app |
|---|---|---|
| Location | `frontend/` + `backend/` | `mobile/` |
| UI | React/Vite browser | Flutter (Dart) |
| ASR | faster-whisper (CTranslate2) | sherpa-onnx Whisper (ONNX) |
| Translation | Argos Translate (direct + en pivot) | MarianMT via onnxruntime (en pivot) |
| TTS | Piper (Python) | sherpa-onnx Piper (ONNX) |
| Runs | one laptop, `FIELDTALK_MODE=local` | on-phone, fully offline |

Both share the same **linguistic layer** (glossary, key-information, quick
questions) and the same language-pair design. That layer is runtime-agnostic
JSON + logic, so changes there benefit both builds.

## The linguistic layer (the core contribution)

This is the reusable, portable language logic. It lives in:

- `data/emergency_questions.json` (backend) and
  `mobile/assets/data/quick_questions.json` — curated first-responder
  questions in EN/RU/ZH.
- `backend/models/emergency_nlp.py` and
  `mobile/lib/services/nlp_service.dart` — the same rule-based
  `extract_key_information` / `extract` logic (negation, entities, question
  detection) in Python and Dart.
- `mobile/assets/data/glossary.json` — bilingual medical glossary
  (EN/RU/ZH) grouped by category (allergy, pain, bleeding, breathing,
  medication, diabetes, consciousness, body, numbers).

Adding a term or question means editing these JSON files and keeping the three
languages in sync. No model retraining is needed.

## What is done

- **Backend pipeline** (`backend/`): ASR → translation → TTS over FastAPI.
  Supports all 6 pairs, the English pivot, and a `/health` check. Tests pass.
- **Mobile app** (`mobile/`): Flutter UI (language selectors, mic, result
  card, quick-questions, play audio) + ASR/TTS/translation/NLP services.
  All 6 translation pairs work on-device (en<->ru, en<->zh directly, ru<->zh
  via English pivot). `flutter analyze` → clean, debug and arm64 release APKs
  build.
- **Toolchain**: Flutter 3.47, Android SDK 36, JDK 17 set up on macOS.

## On-device ASR (Whisper + Paraformer routing)

The mobile app uses **two** sherpa-onnx recognizers, routed by source language:
- **Whisper (multilingual)** for English and Russian.
- **Paraformer (trilingual zh/cantonese/en)** for Chinese — `model.int8.onnx`
  (~233MB) is far more accurate and stable on Mandarin than Whisper tiny, and
  handles Chinese speech that mixes English terms (e.g. drug names).

`mobile/lib/services/asr_service.dart` builds each recognizer lazily and caches
it; `transcribeFile(..., language: 'zh')` routes to Paraformer, everything else
to Whisper. The Paraformer model is downloaded by
`python -m scripts.export_models --paraformer`.

## On-device translation (MarianMT via sherpa's onnxruntime)

The mobile app does real machine translation **without bundling a second
onnxruntime** (which previously caused the `OrtGetApiBase` native-symbol crash).

- `mobile/lib/services/mt_onnx.dart` — Dart FFI to the ONNX Runtime **C API**
  (`OrtGetApiBase` -> `OrtApiBase::GetApi`), loading the `libonnxruntime.so`
  that sherpa-onnx already bundles in the APK. The `OrtApi` struct layout comes
  from onnxruntime 1.15.1 (`mt_onnx_bindings.dart`, copied from the
  `onnxruntime` pub package); the struct is backward-compatible, so the leading
  fields are valid against sherpa's newer onnxruntime. Only the functions
  MarianMT needs are wired up (CreateSessionFromArray, Run, tensor/memory-info
  helpers, releases).
- `mobile/lib/services/translation_service.dart` — loads each pair's engine,
  tokenizes, runs greedy decode (repetition penalty 1.2), and detokenizes.
  `ru<->zh` uses the English pivot. Engines are cached per pair.
- Tokenization uses `dart_sentencepiece_tokenizer` (pure Dart, no native lib).
- **ID remapping (critical)**: the optimum-exported `source.spm`/`target.spm`
  order pieces differently than the model's `vocab.json`. So:
  - source: `spm.encode` -> remap pieces to tokenizer ids via `vocab.json` ->
    append BOS;
  - target: ONNX decoder emits tokenizer ids -> remap to spm ids via
    `vid2sid.json` -> `target.spm.decode`.
  `scripts/export_models.py` generates `vid2sid.json` for each pair.

## Model export (regenerate the on-device models)

Run while online:
```bash
# tiny en<->ru + en<->zh (larger); writes quantized ONNX + spm + json into
# mobile/assets/models/mt/{pair}/
python -m scripts.export_models --mt-tiny --mt-zh
```
This uses `optimum-cli export onnx --task seq2seq-lm --opset 18`, then
dynamic-quantizes (int8) the encoder/decoder to shrink the APK, and writes
`vid2sid.json`. `ru<->zh` needs no model (English pivot). APK ~591MB.

## What remains (the next steps)

1. **Verify on a real phone** — test all 6 pairs in airplane mode on a
   low-power device; record latency and battery use.
2. **Tune speed** — pick Whisper `tiny` vs `base`, and confirm the Marian model
   choice balances speed vs. quality (speed is the priority). The zh models
   (`opus-mt`, 65001 vocab) are large; the tiny en<->ru models are faster but
   lower quality and prone to repetition.

## Known issue: espeak-ng-data must be fully bundled

sherpa-onnx Piper TTS needs the shared `espeak-ng-data` directory for
grapheme-to-phoneme conversion. **Flutter asset directories are NOT recursive**,
so a single `assets/models/voices/espeak-ng-data/` entry bundles only the
top-level 123 files — the `lang/` (146) and `voices/` (104) subdirectory files
are silently omitted, and TTS fails on-device with
`Failed to create offline tts. Please check your config`.

The fix (see `mobile/pubspec.yaml`): list **every** directory that directly
contains files under `espeak-ng-data/` as its own asset entry. All 373 files
must be present in the APK — verify with:

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -c "espeak-ng-data/"
# expected: 373 (or 374 incl. a marker)
```

`mobile/lib/services/tts_service.dart` copies espeak once via `espeak_manifest.txt`
and writes an `_espeak_ok` marker. Bump `_modelVersion` there (and the marker)
if the bundled voices/espeak change so the app re-copies instead of reusing a
stale copy.

## How to run the laptop demo

```bash
# Terminal 1
FIELDTALK_MODE=local .venv/bin/python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000
# Terminal 2
cd frontend && npm run dev
```
Open http://127.0.0.1:5173, allow the microphone, pick a pair, record, stop.

## How to build the Android APK

See `mobile/README.md` for the full steps (toolchain, model prep, build).

## Environment notes (macOS)

- Use **JDK 17** (Java 25 breaks Gradle/AGP).
- `ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools`.
- `.venv/` is Python 3.12 (needed for the Python model stack).
- Model weights and `.venv/` are git-ignored; never commit them.

## Licensing & safety

Review model/voice licenses before redistribution (Argos, faster-whisper,
Piper, Marian/opus-mt, sherpa-onnx, onnxruntime). Use fictional examples only;
never upload real patient data.