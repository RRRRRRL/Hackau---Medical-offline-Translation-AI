# FieldTalk Android

FieldTalk Android is a native Kotlin/Jetpack Compose application for turn-based,
on-device speech recognition, translation, and text-to-speech.

Supported translation directions:

- English ↔ Simplified Chinese
- English ↔ Russian

> **Safety:** FieldTalk has not been clinically validated. It does not diagnose,
> provide medical advice, or replace a qualified interpreter. Review names,
> medicines, allergies, numbers, and negation, and confirm critical information.

## 1. Requirements

The following instructions use Windows PowerShell. Internet access is required for
the initial tool, dependency, and device-model downloads.

Install:

1. **JDK 17**. Android Gradle Plugin 8.7.3 in this project should be run with JDK
   17, not the system JDK 25.
2. **Android Studio** from <https://developer.android.com/studio>.
3. In **Android Studio → More Actions → SDK Manager**, install:
   - Android SDK Platform 35
   - Android SDK Build-Tools 35.0.0
   - Android SDK Platform-Tools
   - Android SDK Command-line Tools (latest)
4. For emulator use, install an API 35 **Google Play** x86_64 system image.

A separate Gradle installation is unnecessary. The repository contains `gradlew.bat`,
which downloads the correct Gradle distribution and all declared Android/Kotlin
libraries during the first build.

To work in the IDE, choose **Android Studio → Open** and select this repository's
`android` directory, not the repository root. Allow Gradle synchronization to finish.

## 2. Open the correct directory

This project may be moved anywhere. Do not copy an old absolute project path into
commands. Open PowerShell in the repository root and enter the Android directory:

```powershell
cd .\android
```

If PowerShell was opened elsewhere, first navigate to the current repository root,
then run `cd .\android`. All remaining commands in this README assume the current
directory is `android/`.

## 3. Configure JDK and Android SDK

For a standard installation:

```powershell
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
```

Verify the paths:

```powershell
& "$env:JAVA_HOME\bin\java.exe" -version
Test-Path "$env:ANDROID_HOME\platforms\android-35\android.jar"
Test-Path "$env:ANDROID_HOME\build-tools\35.0.0\aapt2.exe"
Test-Path "$env:ANDROID_HOME\platform-tools\adb.exe"
```

The Java command should report version 17, and every `Test-Path` result should be
`True`. If not, use the actual paths selected during installation.

Create the machine-specific Gradle SDK configuration:

```powershell
"sdk.dir=$($env:ANDROID_HOME -replace '\\','/')" | Set-Content .\local.properties
```

`local.properties` must contain the SDK path for the current computer. It is not a
portable project setting. Regenerate it if the Android SDK moves or the project is
used on another computer.

Optional: persist the environment variables for future PowerShell windows:

```powershell
[Environment]::SetEnvironmentVariable('JAVA_HOME', $env:JAVA_HOME, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $env:ANDROID_HOME, 'User')
```

Open a new terminal after persisting them.

## 4. Build and run automated tests

From `android/`:

```powershell
.\gradlew.bat clean test assembleDebug
```

This command downloads Gradle dependencies, compiles the app, runs JVM unit tests,
and creates a debug APK. A successful build ends with `BUILD SUCCESSFUL`.

The APK is generated at:

```text
app/build/outputs/apk/debug/app-debug.apk
```

From the repository root, the same file is:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

## 5. Run on an Android emulator

1. Open **Android Studio → Device Manager**.
2. Create a device such as Pixel 7 with an API 35 **Google Play** image.
3. Start the emulator and wait for Android to finish booting.
4. In PowerShell, from `android/`, verify the device:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" devices
```

The emulator should be listed as `device`. Install and launch FieldTalk:

```powershell
.\gradlew.bat installDebug
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell am start -n com.hacku.fieldtalk/.MainActivity
```

For microphone testing, open the emulator's **Extended controls → Microphone** and
enable host audio input. Google speech services can be unreliable on some emulator
images; a Google-certified physical phone is preferred for multilingual ASR and TTS.

## 6. Run on a physical phone

1. On the phone, open **Settings → About phone** and tap **Build number** seven
   times.
2. Enable **Developer options → USB debugging**.
3. Connect the unlocked phone with a USB data cable and accept **Allow USB
   debugging**.
4. From `android/`, run:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" devices
.\gradlew.bat installDebug
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell am start -n com.hacku.fieldtalk/.MainActivity
```

The phone must appear as `device`, not `unauthorized` or `offline`. If both an emulator
and phone are attached, target one device explicitly:

```powershell
$serial = "PHONE_SERIAL_FROM_ADB_DEVICES"
& "$env:ANDROID_HOME\platform-tools\adb.exe" -s $serial install -r .\app\build\outputs\apk\debug\app-debug.apk
& "$env:ANDROID_HOME\platform-tools\adb.exe" -s $serial shell am start -n com.hacku.fieldtalk/.MainActivity
```

### Manual APK installation

Alternatively, copy this file to the phone:

```text
app/build/outputs/apk/debug/app-debug.apk
```

Open it in the phone's Files application, allow installation from that source when
prompted, and tap **Install**.

## 7. Prepare offline speech, translation, and TTS

Keep the device online during one-time preparation. FieldTalk has no Android
`INTERNET` permission, but Android/Google system services require connectivity to
provision their own local models.

1. In Google Play, update **Speech Recognition & Synthesis** and **Google**.
2. Install offline recognition packs through the device's speech settings. The usual
   route is:
   **Settings → System → Languages & input → Voice input → Speech Recognition and
   Synthesis from Google → Offline speech recognition**.
3. Install English (United States), Chinese (Mandarin/China), and Russian (Russia).
4. Install offline TTS voices through:
   **Settings → System → Languages & input → Text-to-speech output → engine settings
   → Install voice data**.
5. While still online, open FieldTalk and exercise each source language so Android can
   prepare available speech models.

The production manifest intentionally omits `INTERNET`, so FieldTalk cannot download
missing ML Kit translation models itself. Translation works only when the required
ML Kit model has already been provisioned by an approved connected preparation build
or device-management process. A missing model produces an explicit error rather than
sending text to a server. See `MODEL_SETUP.md` before testing translation offline.

Menu names vary by manufacturer. Search Android Settings for **offline speech
recognition** or **text-to-speech** if necessary. See [`MODEL_SETUP.md`](MODEL_SETUP.md)
for model behavior and limitations.

## 8. Use the application

1. Open FieldTalk and grant microphone permission.
2. Under **From**, choose the language being spoken.
3. Under **To**, choose English, Chinese, or Russian. English must be one side of the
   pair.
4. Press **Start recording**, speak clearly, then press **Stop recording**.
5. Review and correct the transcript.
6. Press **Translate**.
7. Read the translated text or press **Speak translation offline**.
8. Confirm all critical information with the patient.

If speech recognition is unavailable, typed text can still be entered for translation.

## 9. Debugging commands

Rebuild after source changes:

```powershell
.\gradlew.bat test assembleDebug
```

Reinstall without clearing app data:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" install -r .\app\build\outputs\apk\debug\app-debug.apk
```

Follow FieldTalk logs while reproducing a problem:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" logcat --pid=$(& "$env:ANDROID_HOME\platform-tools\adb.exe" shell pidof -s com.hacku.fieldtalk)
```

Stop log output with **Ctrl+C**. Reset the app if needed:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell pm clear com.hacku.fieldtalk
```

Run connected-device tests (there may be no instrumentation tests yet):

```powershell
.\gradlew.bat connectedDebugAndroidTest
```

For interactive debugging in Android Studio, select the connected phone or emulator
in the device selector, set the run configuration to **app**, and click **Debug app**.
Set breakpoints in Kotlin source and use the **Logcat** window for runtime messages.

## 10. Verify offline operation

After all models and voices are prepared:

1. Enable airplane mode and turn off Wi-Fi.
2. Force-stop and reopen FieldTalk.
3. Test speech recognition, translation, and spoken output for:
   - English → Chinese
   - Chinese → English
   - English → Russian
   - Russian → English
4. Do not call the device offline-ready unless every required feature succeeds while
   disconnected.

## Troubleshooting

| Problem | Resolution |
| --- | --- |
| `SDK location not found` | Recreate `local.properties` using the command in section 3. |
| Gradle reports an unsupported Java version such as `25.0.3` | Set `JAVA_HOME` to JDK 17 in the current terminal and rebuild. |
| `adb` is not recognized | Use the full path `$env:ANDROID_HOME\platform-tools\adb.exe`. |
| Device is `unauthorized` | Unlock the phone and approve the USB-debugging prompt. |
| Device is `offline` | Restart the emulator/device, reconnect USB, then run `adb devices` again. |
| Offline speech model missing / error 13 | Update Google speech services, install the selected language pack, restart the device, and retry while online. |
| No offline TTS voice | Install voice data in Android TTS settings; FieldTalk rejects network-only voices. |
| Translation model missing | Keep the device online during provisioning; see `MODEL_SETUP.md` for the current ML Kit limitation. |
| Emulator receives no audio | Enable host microphone input in Extended controls and grant Windows microphone access. |

## Privacy and platform limitations

- The application manifest omits `INTERNET`.
- FieldTalk does not intentionally log transcripts, translations, or audio.
- Android and the selected speech engine control system model storage.
- Desktop faster-whisper, Argos CTranslate2, and Piper ONNX assets cannot be copied
  directly into this Android application because their runtimes and preprocessing
  differ.
