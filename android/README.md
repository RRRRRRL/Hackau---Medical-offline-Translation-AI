# FieldTalk Android

FieldTalk is a native Kotlin/Jetpack Compose communication aid for local speech
recognition, translation, and text-to-speech. It supports:

- English ↔ Simplified Chinese
- English ↔ Russian

> **Safety:** FieldTalk has not been clinically validated. It does not provide
> medical advice or diagnosis and does not replace a qualified interpreter. Always
> confirm critical information with the patient.

## What works

- Editable speech transcript and translated text
- Android 12+ on-device speech recognition with no network-recognition fallback
- ML Kit on-device translation after model provisioning
- Android text-to-speech using only voices marked as offline
- No Android `INTERNET` permission and no intentional medical-content logging
- Explicit errors when a required local language model or voice is unavailable

The readiness card can remain **Offline setup required** until an optional checksum
manifest is provisioned. This does not prevent Android-managed speech, translation,
and TTS models from being tested.

## Install the test APK

Copy and install this file:

```text
app/build/outputs/apk/debug/app-debug.apk
```

Full path on this Windows machine:

```text
C:\Users\user\Desktop\HackU\hackU-android\app\build\outputs\apk\debug\app-debug.apk
```

### Copy it to the phone

1. Connect the phone by USB and select **File transfer**.
2. Copy `app-debug.apk` to the phone's **Downloads** folder.
3. Open **Files** or **My Files** and tap `app-debug.apk`.
4. If blocked, enable **Allow from this source** for the file manager.
5. Tap **Install**, then open **FieldTalk**.

### Install it with ADB

1. Enable **Developer options → USB debugging** on the phone.
2. Connect and unlock the phone, then approve **Allow USB debugging**.
3. In PowerShell at the project root, run:

	```powershell
	adb devices
	adb install -r .\app\build\outputs\apk\debug\app-debug.apk
	```

If `adb` is not on `PATH`:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r .\app\build\outputs\apk\debug\app-debug.apk
```

If an emulator and phone are connected, copy the phone serial from `adb devices` and
use `adb -s PHONE_SERIAL install -r ...`.

## One-time device preparation

Keep the phone online during preparation. FieldTalk has no `INTERNET` permission, but
Android/Google system services need connectivity to install their local models.

### 1. Update speech services

In Google Play, update **Speech Recognition & Synthesis** and **Google**, then restart
the phone.

### 2. Prepare offline speech recognition

On Android 14+, FieldTalk requests the selected speech model automatically. Select a
source language, press **Start recording**, and wait for model preparation.

For manual setup, the common route is:

**Settings → System → Languages & input → Voice input → Speech Recognition and
Synthesis from Google → Offline speech recognition**

Under **All**, install:

- English (United States)
- Chinese (Mandarin/China)
- Russian (Russia)

Settings vary by manufacturer. Search Settings for **offline speech recognition** if
this route differs. See `MODEL_SETUP.md` for troubleshooting.

### 3. Install offline TTS voices

Open:

**Settings → System → Languages & input → Text-to-speech output → engine settings →
Install voice data**

Install English (US), Mandarin Chinese, and Russian voices. FieldTalk rejects voices
that report a network requirement.

### 4. Prepare translation models

While online, type a short message and press **Translate** once for each required
direction. If a local ML Kit model is absent, FieldTalk reports that it is not
installed. See `MODEL_SETUP.md` for the current provisioning limitation.

## Use FieldTalk

1. Open FieldTalk and grant microphone permission.
2. Under **From**, choose the language being spoken.
3. Under **To**, choose the translation language.
4. Press **Start recording** and speak clearly.
5. Press **Stop recording** and wait for the transcript.
6. Review and correct names, medicines, numbers, allergies, and negation.
7. Press **Translate**.
8. Show the translated text or press **Speak translation offline**.
9. Confirm all critical details instead of relying on one translation.

Chinese↔Russian and same-language pairs are intentionally unavailable. English must
be one side of every translation.

## Verify offline operation

After preparing all models and voices:

1. Enable airplane mode.
2. Turn off Wi-Fi and mobile data.
3. Force-stop and reopen FieldTalk.
4. Test ASR, translation, and TTS for all four supported directions.

Do not call the device offline-ready unless every required direction succeeds while
disconnected.

## Build from source

Requirements: JDK 17, Android SDK Platform 35, and Android SDK Build Tools.

```powershell
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
.\gradlew.bat test assembleDebug
```

The output is `app/build/outputs/apk/debug/app-debug.apk`. To install on a connected
phone or running emulator:

```powershell
.\gradlew.bat installDebug
adb shell am start -n com.hacku.fieldtalk/.MainActivity
```

The VS Code default build task is **Android: test and assemble debug**.

## Troubleshooting

### ADB shows `unauthorized`

Unlock the phone and approve the USB-debugging prompt. Try another USB data cable if
no prompt appears.

### Offline speech model is missing

- Keep the phone online during the one-time download.
- Update Speech Recognition & Synthesis and Google through Play Store.
- Confirm the **From** language matches the installed speech language.
- Restart the phone after installing language packs.
- Physical Google-certified phones are more reliable than emulators.

### No offline TTS voice

Install voice data in Android text-to-speech settings. The app intentionally rejects
network-only voices.

### Translation model is missing

The application has no `INTERNET` permission, so it cannot independently download ML
Kit models. Use an approved connected preparation build/workflow or bundled assets as
described in `MODEL_SETUP.md`.

## Privacy

- The manifest omits `INTERNET`.
- FieldTalk does not intentionally log transcripts, translations, or audio.
- Clearing app data removes FieldTalk state and cache.
- Android and the selected engine control system speech/TTS model storage.

## Desktop model compatibility

The desktop source uses faster-whisper, Argos CTranslate2 packages, and Piper ONNX
voices. Those Python/CTranslate2 assets cannot simply be renamed or copied into this
Android application. See `MODEL_SETUP.md` for mobile alternatives and limitations.
