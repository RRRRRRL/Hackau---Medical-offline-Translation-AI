# Model assets

Large model binaries are intentionally not committed or bundled in the base APK.
The desktop CTranslate2 files from the source project cannot be renamed and used
on Android. The current APK uses Android-managed on-device speech/TTS assets and
ML Kit translation assets after device provisioning.

Read the repository-level `README.md` for APK installation and usage. Read
`MODEL_SETUP.md` for language-pack setup, mobile alternatives, and optional checksum
manifest provisioning.
