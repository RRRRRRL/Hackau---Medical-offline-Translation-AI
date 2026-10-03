# Mobile app source layout (canonical)

Canonical Android React Native application: `/mobile/app`.

This repository no longer uses an overlay workflow that required manually generating a second app and copying files.
All maintained mobile code now lives in the generated project under `/mobile/app`:

- `mobile/app/App.tsx` - React Native UI workflow
- `mobile/app/android/app/src/main/java/com/fieldtalk/speech/` - Kotlin native bridge module/package
- `mobile/app/android/app/src/main/assets/` - local Whisper asset (`ggml-tiny.bin`, ignored in Git) and metadata
- `mobile/app/scripts/` - PowerShell setup/download/validation scripts

Run commands from `mobile/app` unless README says otherwise.
