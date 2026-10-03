# FieldTalk Android prototype integration

Status: source integration files, not a prebuilt APK or complete generated Android project. Not compiled or phone-tested by the assistant. Generate a React Native application and integrate these files before building. The laptop frontend/backend are unchanged. Base: test commit 3e142d7.

## Architecture
React Native -> 16 kHz mono PCM WAV microphone capture -> local whisper.rn/whisper.cpp -> editable transcript -> ML Kit on-device translation -> explicitly confirmed playback through installed offline Android TTS.

English, Mandarin Chinese and Russian; all six different-language directions. ML Kit replaces Argos on Android; Piper is replaced by the device TTS engine. This is not identical model output to the laptop. No FastAPI request or laptop is in the inference path. Recognition starts after Stop; no live captions or clinical accuracy claim.

## Generate/build
Install Android Studio, its SDK/platform/build tools and the JDK/Node versions required by the chosen React Native release. Keep generated Gradle wrapper and lockfiles from that release. These are not supplied by this overlay.

From repository root:
```powershell
git switch feature/android-prototype
npx @react-native-community/cli@latest init FieldTalkMobile --directory mobile/app
Copy-Item mobile/App.tsx mobile/app/App.tsx
cd mobile/app
npm install whisper.rn
```
Pin the resolved React Native and whisper.rn versions in package.json/package-lock.json once the build works. Native binaries download during whisper.rn installation; build/setup needs internet. Use a native React Native application, not Expo Go or the existing Vite UI.

Copy mobile/native/*.kt into mobile/app/android/app/src/main/java/com/fieldtalk/speech/ (create directories). In the generated MainApplication.kt, import com.fieldtalk.speech.FieldTalkPackage and add FieldTalkPackage() to PackageList(this).packages inside getPackages(). Retain generated application code; do not replace MainApplication wholesale. Registration is mandatory. Verify legacy module interoperability with your chosen React Native release; these files are not TurboModule codegen bindings.

In app-level android/app/build.gradle dependencies add:
```groovy
implementation 'com.google.mlkit:translate:17.0.3'
```
Ensure google() is configured, minSdkVersion >=23 (or the higher RN minimum), and build native libraries for your phone ABI. If ProGuard is enabled add `-keep class com.rnwhisper.** { *; }` to app/proguard-rules.pro.

Merge into android/app/src/main/AndroidManifest.xml, outside application:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<queries><intent><action android:name="android.intent.action.TTS_SERVICE" /></intent></queries>
```
Retain generated manifest declarations. INTERNET is for model preparation and development; its presence is not evidence of online inference.

## ASR asset
Download multilingual ggml-tiny.bin from the official whisper.cpp model repository during preparation:
https://huggingface.co/ggerganov/whisper.cpp/tree/main

Place it in mobile/app/android/app/src/main/assets/ggml-tiny.bin. Create assets directory if absent. Do not use tiny.en (English-only) or models_local/whisper-base/model.bin (CTranslate2 format). Native modelPath copies the bundled asset to internal files storage; loading uses CPU initially. Verify artifact origin/checksum and license; no weights are included in this commit. Add assets/ggml-*.bin to the generated app .gitignore before staging generated files. Keep local model for builds, do not commit weights.

## Phone preparation
Connect physical Android phone with USB debugging enabled. In mobile/app:
```powershell
npm run android
```
First use, online on Wi-Fi:
1. Tap Prepare translation. Only this button requests Chinese/Russian model downloads; English is the pivot/base language.
2. In Android TTS settings install offline en-US, zh-CN and ru-RU voice data using an engine supporting them. Missing voices fail visibly; availability depends on phone/engine.
3. Tap Load offline models. It checks translation/voice availability and initializes Whisper.
4. Allow microphone permission; choose languages; Start then Stop and recognize.
5. Review/edit original text, Translate, confirm critical details, then Speak.

The initial UI requires all three language voices/models, not pair-specific readiness. Voice-list availability is not proof of actual offline synthesis. No fallback to cloud recognition or network TTS is implemented. ML Kit and installed TTS are third-party components; inspect network behavior before asserting zero telemetry.

## Offline acceptance
A debug RN build can depend on Metro for its JS bundle; it is not a standalone offline proof. Build an APK containing the JS bundle (follow your generated RN release/signing guide, or use a bundled non-debuggable variant), install it and verify launch without Metro, USB or a laptop. Do not commit signing keys/passwords. Report build/device details and failures, not an untested APK claim.

Cold-launch in airplane mode; Load offline models (not Prepare); test every direction with consenting speakers. Verify recognition/translation/voice errors, silence, negation, medicines, numbers and background/foreground behavior. UI timings show ASR and translation only, not recording or playback-start delay. No latency guarantee.

Recording capped at approximately 30 seconds; press Stop afterward. Temporary audio is deleted after inference; abrupt process termination can leave cache files. Transcripts remain in UI memory, are not saved/logged by this code. Whisper context remains process-lived for this prototype; lifecycle, cancellations and memory behavior need device testing. Text edits require retranslating before playback. Short turns only; no continuous interpretation.

## Build validation still required
Run generated RN TypeScript/lint/tests and Android assemble task. Resolve integration/API differences against pinned dependencies. Test native package registration, permissions, downloaded-model readiness and release offline launch. Mock tests from laptop do not validate Android. This source overlay is deliberately not represented as a compiled application.

## Sources and credits
https://github.com/mybigday/whisper.rn
https://developers.google.com/ml-kit/language/translation/android
https://developer.android.com/reference/android/speech/tts/Voice

Credit React Native, whisper.rn/whisper.cpp, Whisper model, ML Kit and Android TTS, plus AI coding assistance. Review engine/model terms separately. Not a diagnosis tool, treatment recommender or validated interpreter.
