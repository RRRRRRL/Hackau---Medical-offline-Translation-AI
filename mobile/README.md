# FieldTalk Mobile (Android APK)

Offline, on-device medical translation for first responders. This is the
**mobile build** of FieldTalk — a Flutter Android app that runs ASR → translation
→ TTS entirely on the phone, with no network. It supports **English, Russian
and Chinese** in all 6 directions (Chinese ↔ Russian goes through an English
pivot).

> Safety: FieldTalk translates communication. It does not diagnose or replace a
> qualified interpreter. Medical accuracy is not clinically validated.

## How it works

```
Flutter app (Dart)
 ├─ ASR:  sherpa-onnx Whisper (encoder/decoder ONNX)      -> text
 ├─ MT:   MarianMT via onnxruntime (encoder/decoder ONNX) -> translated text
 │        (en<->ru tiny, en<->zh larger; ru<->zh via en pivot)
 ├─ TTS:  sherpa-onnx Piper (VITS ONNX)                   -> WAV audio
 └─ NLP:  rule-based key-information extraction           -> structured signals
```

Everything is on-device. The models live in `assets/models/` (populated by the
export script) and are copied to the app's writable directory on first run.

## Project structure

```
mobile/
  pubspec.yaml               Dependencies + asset declarations
  android/                   Android project (manifest, Gradle)
  lib/
    main.dart                Entry point + HomeScreen (UI, mic, pipeline)
    config/languages.dart    Language labels, supported pairs, English pivot
    data/ (in assets)        quick_questions.json, glossary.json (EN/RU/ZH)
    services/
      asr_service.dart       sherpa-onnx Whisper (offline ASR)
      tts_service.dart       sherpa-onnx Piper (offline TTS)
      translation_service.dart  MarianMT via onnxruntime + English pivot
      nlp_service.dart       key-information extraction (negation, entities, Q)
  assets/
    data/                    Linguistic data (committed, small)
    models/                  Model weights (NOT committed; run export script)
  scripts/export_models.py   (repo root) downloads/exports models here
```

## The linguistic layer (your contribution)

The reusable, runtime-agnostic language logic lives in:
- `assets/data/glossary.json` — bilingual medical glossary (EN/RU/ZH) grouped
  by category (allergy, pain, bleeding, breathing, medication, diabetes,
  consciousness, body parts, numbers).
- `assets/data/quick_questions.json` — curated first-responder questions in
  EN/RU/ZH (breathing, allergy, pain, bleeding, meds, diabetes, etc.).
- `lib/services/nlp_service.dart` — `extract(text, language)` returns
  `KeyInformation` with `is_question`, `negated`, `entities` and `categories`.

This layer is pure Dart + JSON with no ML dependency, so it ports to any
runtime. It is the same logic that the web backend uses.

## Setup & build (macOS)

### 1. Toolchain (one-time)
```bash
brew install --cask flutter android-commandlinetools
export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
export ANDROID_SDK_ROOT="/opt/homebrew/share/android-commandlinetools"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
sdkmanager "platform-tools" "platforms;android-36" "build-tools;34.0.0"
yes | sdkmanager --licenses
flutter config --android-sdk "$ANDROID_SDK_ROOT"
flutter doctor
```
Use JDK 17 (Java 25 is too new for Gradle/AGP).

### 2. Get dependencies
```bash
cd mobile
flutter pub get
```

### 3. Prepare the models (online, one-time)
```bash
cd ..
python -m scripts.download_models    # web-model stack (already done for laptop)
python -m scripts.export_models --all  # exports into mobile/assets/models/
```
`export_models.py` produces Whisper ONNX, Piper voices (tokens + espeak-ng-data)
and MarianMT ONNX graphs for the app. See the script for per-model options.

### 4. Build the APK
```bash
cd mobile
flutter build apk --release --target-platform android-arm64
# -> build/app/outputs/flutter-apk/app-release.apk
```

### 5. Run on a device/emulator
```bash
flutter run
```
Allow microphone access, pick a language pair, press Record, speak, press Stop.

## Dependencies & native-library note

Both `sherpa_onnx` and `onnxruntime` bundle `libonnxruntime.so`. The app's
`android/app/build.gradle.kts` sets `packaging { jniLibs { pickFirsts ... } }`
to merge them, and the root `android/build.gradle.kts` forces `compileSdk = 36`
across subprojects so the older `onnxruntime` plugin builds.

## Model prep & the remaining work

The app, UI, linguistic layer and all service wiring compile and build cleanly
(`flutter analyze` → no issues; `flutter test` → pass). To run real inference
end-to-end you must:

1. Run `scripts/export_models.py` to populate `assets/models/` (Whisper, Piper,
   MarianMT). The script is written but the MarianMT full ONNX export is
   easiest via the `optimum` exporter (`optimum-cli export onnx --model ...`).
2. Install the app on a physical device (a low-power Android phone) and verify
   latency/battery in airplane mode.

## See also
- `../README.md` — the original laptop web app (FastAPI + Python models).
- `../docs/` — handoff notes for the full team.